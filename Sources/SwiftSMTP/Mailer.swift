import Dispatch
import Foundation
import NIO
import NIOExtras
import NIOSSL
import NIOConcurrencyHelpers

fileprivate extension Configuration.Server {
    enum EncryptionHandler {
        case none
        case atBeginning(ChannelHandler)
        case beforeSMTPHandler(ChannelHandler)
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
public final class Mailer {
    private struct ScheduledEmail: Hashable {
        private let uuid = UUID()

        let email: Email
        let promise: EventLoopPromise<Void>

        func hash(into hasher: inout Hasher) {
            hasher.combine(uuid)
        }

        static func ==(lhs: ScheduledEmail, rhs: ScheduledEmail) -> Bool {
            lhs.uuid == rhs.uuid
        }
    }

    /// The event loop group this mailer uses.
    public let group: EventLoopGroup
    /// The configuration used by this mailer.
    public let configuration: Configuration
    /// The maximum number of connections this mailer should open. `nil` if no limit is set.
    public let maxConnections: Int?
    /// The logger to use for logging all transmissions. If `nil` no messages will be logged.
    public let transmissionLogger: SMTPLogger?

    private let connectionsSemaphore: DispatchSemaphore?
    private let senderQueue = DispatchQueue(label: "SMTP Mailer Sender Queue")

    private let emailsLock = Lock()
    private var emailsStack = Array<ScheduledEmail>()

    private let bootstrapsLock = Lock()
    private var bootstraps = Dictionary<ScheduledEmail, ClientBootstrap>()

    /// Creates a new mailer with the given parameters.
    /// - Parameters:
    ///   - group: The event loop group the new mailer should use.
    ///   - configuration: The configuration to use for the new mailer.
    ///   - maxConnections: The maximum number of connections this mailer should open. `nil` if no limit should be set. Defaults to 2.
    ///   - transmissionLogger: The logger to use for logging all transmissions. If `nil` no messages will be logged.
    public init(group: EventLoopGroup,
                configuration: Configuration,
                maxConnections: Int? = 2,
                transmissionLogger: SMTPLogger? = nil) {
        self.group = group
        self.configuration = configuration
        self.maxConnections = maxConnections
        self.transmissionLogger = transmissionLogger

        if let maxConnections = maxConnections {
            assert(maxConnections > 0)
            connectionsSemaphore = DispatchSemaphore(value: maxConnections)
            bootstraps.reserveCapacity(maxConnections)
        } else {
            connectionsSemaphore = nil
        }
    }

    private func pushEmail(_ email: ScheduledEmail) {
        emailsLock.withLockVoid { emailsStack.append(email) }
    }

    private func popEmail() -> ScheduledEmail? {
        emailsLock.withLock { emailsStack.isEmpty ? nil : emailsStack.removeFirst() }
    }

    private func connectBootstrap(sending email: ScheduledEmail) {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
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
                    var handlers: [ChannelHandler] = [
                        ByteToMessageHandler(LineBasedFrameDecoder()),
                        SMTPResponseDecoder(),
                        MessageToByteHandler(SMTPRequestEncoder(base64EncodingOptions: base64Options)),
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
        bootstrapsLock.withLockVoid { bootstraps[email] = bootstrap }
        let connectionFuture = bootstrap.connect(host: configuration.server.hostname, port: configuration.server.port)
        connectionFuture.cascadeFailure(to: email.promise)
        email.promise.futureResult.whenComplete { [weak self] _ in
            connectionFuture.whenSuccess { $0.close(mode: .all, promise: nil) }
            guard let self = self else { return }
            self.bootstrapsLock.withLockVoid { self.bootstraps.removeValue(forKey: email) }
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
    public func send(email: Email) -> EventLoopFuture<Void> {
        _sendFuture(for: email)
    }

#if compiler(>=5.5.2) && canImport(_Concurrency)
    @inlinable
    public func send(email: Email) async throws {
        try await _sendFuture(for: email).get()
    }
#endif
}
