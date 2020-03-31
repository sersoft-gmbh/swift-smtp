import Dispatch
import Foundation
import NIO
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

public final class Mailer {
    private struct ScheduledEmail: Hashable {
        private let uuid = UUID()

        let email: Email
        let promise: EventLoopPromise<Void>

        func hash(into hasher: inout Hasher) {
            hasher.combine(uuid)
        }

        static func ==(lhs: ScheduledEmail, rhs: ScheduledEmail) -> Bool {
            return lhs.uuid == rhs.uuid
        }
    }

    public let group: EventLoopGroup
    public let configuration: Configuration
    public let maxConnections: Int
    public let connectionTimeOut: TimeAmount
    public let logTransmissions: Bool

    private let connectionsSemaphore: DispatchSemaphore
    private let senderQueue = DispatchQueue(label: "SMTP Mailer Sender Queue")

    private let emailsLock = Lock()
    private var emailsStack = Array<ScheduledEmail>()

    private let bootstrapsLock = Lock()
    private var bootstraps = Dictionary<ScheduledEmail, ClientBootstrap>()

    public init(group: EventLoopGroup, configuration: Configuration, maxConnections: Int = 2, connectionTimeOut: TimeAmount = .seconds(60), logTransmissions: Bool = false) {
        assert(maxConnections > 0)

        self.group = group
        self.configuration = configuration
        self.maxConnections = maxConnections
        self.connectionTimeOut = connectionTimeOut
        self.logTransmissions = logTransmissions

        connectionsSemaphore = DispatchSemaphore(value: maxConnections)
        bootstraps.reserveCapacity(maxConnections)
    }

    private func pushEmail(_ email: ScheduledEmail) {
        emailsLock.withLockVoid { emailsStack.append(email) }
    }

    private func popEmail() -> ScheduledEmail? {
        return emailsLock.withLock {
            guard !emailsStack.isEmpty else { return nil }
            return emailsStack.removeFirst()
        }
    }

    private func connectBootstrap(sending email: ScheduledEmail) {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .connectTimeout(connectionTimeOut)
            .channelInitializer { [configuration, logTransmissions] in
                do {
                    var handlers: [ChannelHandler] = [
                        LineBasedFrameDecoder(),
                        SMTPResponseDecoder(),
                        SMTPRequestEncoder(),
                        SMTPHandler(configuration: configuration, email: email.email, allDonePromise: email.promise),
                    ]
                    if logTransmissions {
                        handlers.insert(LogDuplexHandler(), at: 0)
                    }
                    switch try configuration.server.createEncryptionHandlers() {
                    case .none: break
                    case .atBeginning(let handler): handlers.insert(handler, at: 0)
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
            self.connectionsSemaphore.signal()
            self.scheduleMailDelivery()
        }
    }

    private func scheduleMailDelivery() {
        guard let next = popEmail() else { return }
        senderQueue.async { [weak self] in
            self?.connectionsSemaphore.wait()
            self?.connectBootstrap(sending: next)
        }
    }

    public func send(email: Email) -> EventLoopFuture<Void> {
        let promise = group.next().makePromise(of: Void.self) // could this be .makePromise()
        pushEmail(ScheduledEmail(email: email, promise: promise))
        scheduleMailDelivery()
        return promise.futureResult
    }
}
