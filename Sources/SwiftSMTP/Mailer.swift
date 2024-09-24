fileprivate import Dispatch
#if swift(>=6.0)
import Foundation
#else
public import Foundation
#endif
public import NIO
import NIOExtras
import NIOSSL
fileprivate import NIOConcurrencyHelpers

fileprivate extension Configuration.Server {
    enum EncryptionHandler {
        case none
        case atBeginning(any ChannelHandler)
        case beforeSMTPHandler(any ChannelHandler)
    }
    
    func createEncryptionHandlers() throws -> EncryptionHandler {
        switch encryption {
        case .plain: return .none
        case .ssl:
            let sslContext = try NIOSSLContext(configuration: .makeClientConfiguration())
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: hostname)
            return .atBeginning(sslHandler)
        case .startTLS(let mode):
            return .beforeSMTPHandler(StartTLSDuplexHandler(server: self, tlsMode: mode))
        }
    }
}

/// A Mailer is responsible for opening server connections and dispatching emails.
public final class Mailer: @unchecked Sendable {
    private struct ScheduledEmail: Sendable, Hashable {
        private let uuid = UUID()

        let email: Email
        let promise: EventLoopPromise<Void>

        func hash(into hasher: inout Hasher) {
            hasher.combine(uuid)
        }

        static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.uuid == rhs.uuid
        }
    }

    /// The event loop group this mailer uses.
    public let group: any EventLoopGroup
    /// The configuration used by this mailer.
    public let configuration: Configuration
    /// The maximum number of connections this mailer should open. `nil` if no limit is set.
    public let maxConnections: Int?
    /// The logger to use for logging all transmissions. If `nil` no messages will be logged.
    public let transmissionLogger: (any SMTPLogger)?

    private let connectionsSemaphore: DispatchSemaphore?
    private let senderQueue = DispatchQueue(label: "SMTP Mailer Sender Queue")

    private let emailsStack = NIOLockedValueBox(Array<ScheduledEmail>())

    private let bootstraps: NIOLockedValueBox<Dictionary<ScheduledEmail, ClientBootstrap>>

    /// Creates a new mailer with the given parameters.
    /// - Parameters:
    ///   - group: The event loop group the new mailer should use.
    ///   - configuration: The configuration to use for the new mailer.
    ///   - maxConnections: The maximum number of connections this mailer should open. `nil` if no limit should be set. Defaults to 2.
    ///   - transmissionLogger: The logger to use for logging all transmissions. If `nil` no messages will be logged.
    public init(group: any EventLoopGroup,
                configuration: Configuration,
                maxConnections: Int? = 2,
                transmissionLogger: (any SMTPLogger)? = nil) {
        self.group = group
        self.configuration = configuration
        self.maxConnections = maxConnections
        self.transmissionLogger = transmissionLogger

        var _bootstraps = Dictionary<ScheduledEmail, ClientBootstrap>()
        if let maxConnections = maxConnections {
            assert(maxConnections > 0)
            connectionsSemaphore = DispatchSemaphore(value: maxConnections)
            _bootstraps.reserveCapacity(maxConnections)
        } else {
            connectionsSemaphore = nil
        }
        bootstraps = .init(_bootstraps)
    }

    private func pushEmail(_ email: ScheduledEmail) {
        emailsStack.withLockedValue { $0.append(email) }
    }

    private func popEmail() -> ScheduledEmail? {
        emailsStack.withLockedValue { $0.isEmpty ? nil : $0.removeFirst() }
    }

    private func connectBootstrap(sending email: ScheduledEmail) {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(configuration.connectionTimeOut)
            .channelInitializer { [configuration, transmissionLogger] in
                do {
                    var base64Options: Data.Base64EncodingOptions = []
                    if configuration.featureFlags.contains(.maximumBase64LineLength64) {
                        base64Options.insert(.lineLength64Characters)
                    }
                    if configuration.featureFlags.contains(.maximumBase64LineLength76) {
                        base64Options.insert(.lineLength76Characters)
                    }
                    var handlers: Array<any ChannelHandler> = [
                        ByteToMessageHandler(LineBasedFrameDecoder()),
                        SMTPResponseDecoder(),
                        MessageToByteHandler(SMTPRequestEncoder(
                            base64EncodeAllMessages: configuration.featureFlags.contains(.base64EncodeAllMessages),
                            base64EncodingOptions: base64Options
                        )),
                        SMTPHandler(configuration: configuration, email: email.email, allDonePromise: email.promise),
                    ]
                    if let logger = transmissionLogger {
                        handlers.insert(LogDuplexHandler(logger: logger), at: handlers.startIndex)
                    }
                    switch try configuration.server.createEncryptionHandlers() {
                    case .none: break
                    case .atBeginning(let handler): handlers.insert(handler, at: handlers.startIndex)
                    case .beforeSMTPHandler(let handler): handlers.insert(handler, at: handlers.index(before: handlers.endIndex))
                    }
                    return $0.pipeline.addHandlers(handlers, position: .last)
                } catch {
                    return $0.eventLoop.makeFailedFuture(error)
                }
            }
        bootstraps.withLockedValue { $0[email] = bootstrap }
        let connectionFuture = bootstrap.connect(host: configuration.server.hostname, port: configuration.server.port)
        connectionFuture.cascadeFailure(to: email.promise)
        email.promise.futureResult.whenComplete { [weak self] _ in
            connectionFuture.whenSuccess { $0.close(mode: .all, promise: nil) }
            guard let self else { return }
            self.bootstraps.withLockedValue { _ = $0.removeValue(forKey: email) }
            self.connectionsSemaphore?.signal()
            self.scheduleMailDelivery()
        }
    }

    private func scheduleMailDelivery() {
        guard let next = popEmail() else { return }
        senderQueue.async { [weak self] in
            self?.connectionsSemaphore?.wait()
            self?.connectBootstrap(sending: next)
        }
    }

    @usableFromInline
    func _sendFuture(for email: Email) -> EventLoopFuture<Void> {
        let promise = group.next().makePromise(of: Void.self)
        pushEmail(ScheduledEmail(email: email, promise: promise))
        scheduleMailDelivery()
        return promise.futureResult
    }

    /// Schedules an email for delivery. Returns a future that will succeed once the email is sent, or fail with any error that occurrs during sending.
    /// - Parameter email: The email to send.
    /// - Returns: A future that will complete with the result of sending the email.
    @inlinable
    public func send(_ email: Email) -> EventLoopFuture<Void> {
        _sendFuture(for: email)
    }

    /// Schedules an email for delivery. Returns when once the email is successfully sent, or throws any error that occurrs during sending.
    /// - Parameter email: The email to send.
    public func send(_ email: Email) async throws {
        try await _sendFuture(for: email).get()
    }
}

extension Mailer {
    /// Schedules an email for delivery. Returns a future that will succeed once the email is sent, or fail with any error that occurrs during sending.
    /// - Parameter email: The email to send.
    /// - Returns: A future that will complete with the result of sending the email.
    @inlinable
    @available(*, deprecated, renamed: "send(_:)")
    public func send(email: Email) -> EventLoopFuture<Void> { send(email) }

    /// Schedules an email for delivery. Returns when once the email is successfully sent, or throws any error that occurrs during sending.
    /// - Parameter email: The email to send.
    @available(*, deprecated, renamed: "send(_:)")
    public func send(email: Email) async throws { try await send(email) }
}
