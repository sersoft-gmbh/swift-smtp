import Dispatch
import Foundation
import NIO
import NIOOpenSSL
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
            let sslContext = try SSLContext(configuration: .forClient())
            let sslHandler = try OpenSSLClientHandler(context: sslContext, serverHostname: hostname)
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

    public let maxConnections: Int
    public let group: EventLoopGroup
    public let configuration: Configuration

    private let connectionsSemaphore: DispatchSemaphore
    private let senderQueue = DispatchQueue(label: "SMTP Mailer Sender Queue")

    private let emailsLock = Lock()
    private var emailsStack = Array<ScheduledEmail>()

    private let bootstrapsLock = Lock()
    private var bootstraps = Dictionary<ScheduledEmail, ClientBootstrap>()

    public init(maxConnections: Int = 2, group: EventLoopGroup, configuration: Configuration) {
        assert(maxConnections > 0)

        self.maxConnections = maxConnections
        self.group = group
        self.configuration = configuration

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
            .channelInitializer { [configuration] in
                do {
                    var handlers: [ChannelHandler] = [
                        LineBasedFrameDecoder(),
                        SMTPResponseDecoder(),
                        SMTPRequestEncoder(),
                        SMTPHandler(configuration: configuration, email: email.email, allDonePromise: email.promise),
                    ]
                    switch try configuration.server.createEncryptionHandlers() {
                    case .none: break
                    case .atBeginning(let handler): handlers.insert(handler, at: 0)
                    case .beforeSMTPHandler(let handler): handlers.insert(handler, at: handlers.index(handlers.endIndex, offsetBy: -2))
                    }
                    return $0.pipeline.addHandlers(handlers, first: true)
                } catch {
                    return $0.eventLoop.newFailedFuture(error: error)
                }
        }
        bootstrapsLock.withLockVoid { bootstraps[email] = bootstrap }
        let connectionFuture = bootstrap.connect(host: configuration.server.hostname, port: configuration.server.port)
        connectionFuture.cascadeFailure(promise: email.promise)
        email.promise.futureResult.whenComplete { [weak self] in
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
        let promise = group.next().newPromise(of: Void.self)
        pushEmail(ScheduledEmail(email: email, promise: promise))
        scheduleMailDelivery()
        return promise.futureResult
    }
}
