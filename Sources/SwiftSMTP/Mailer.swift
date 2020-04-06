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
            let sslContext = try NIOSSLContext(configuration: .forClient())
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
    /// The timeout to set for a connection.
    public let connectionTimeOut: TimeAmount
    /// The logger to use for logging all transmissions. If `nil` no messages will be logged.
    public let transmissonLogger: SMTPLogger?

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
    ///   - connectionTimeOut: The timeout for connections of this mailer. Defaults to 60s.
    ///   - transmissonLogger: The logger to use for logging all transmissions. If `nil` no messages will be logged.
    public init(group: EventLoopGroup,
                configuration: Configuration,
                maxConnections: Int? = 2,
                connectionTimeOut: TimeAmount = .seconds(60),
                transmissonLogger: SMTPLogger? = nil) {
        self.group = group
        self.configuration = configuration
        self.maxConnections = maxConnections
        self.connectionTimeOut = connectionTimeOut
        self.transmissonLogger = transmissonLogger

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
            .connectTimeout(connectionTimeOut)
            .channelInitializer { [configuration, transmissonLogger] in
                do {
                    var handlers: [ChannelHandler] = [
                        ByteToMessageHandler(LineBasedFrameDecoder()),
                        SMTPResponseDecoder(),
                        MessageToByteHandler(SMTPRequestEncoder()),
                        SMTPHandler(configuration: configuration, email: email.email, allDonePromise: email.promise),
                    ]
                    if let logger = transmissonLogger {
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

    /// Schedules an email for delivery. Returns a future that will succeed once the email is sent, or fail with any error that occurrs during sending.
    /// - Parameter email: The email to send.
    /// - Returns: A future that will complete with the result of sending the email.
    public func send(email: Email) -> EventLoopFuture<Void> {
        let promise = group.next().makePromise(of: Void.self)
        pushEmail(ScheduledEmail(email: email, promise: promise))
        scheduleMailDelivery()
        return promise.futureResult
    }
}
