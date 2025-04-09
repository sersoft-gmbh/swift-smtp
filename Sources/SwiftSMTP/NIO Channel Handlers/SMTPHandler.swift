#if swift(>=6.0)
import Foundation
import NIO
#else
public import Foundation
public import NIO
#endif
import NIOExtras
import NIOSSL

fileprivate extension SMTPResponse {
    func verify<T>(failing promise: EventLoopPromise<T>) -> Bool {
        switch self {
        case .success(_): return true
        case .failure(let error):
            promise.fail(error)
            return false
        }
    }
}

final class SMTPHandler: ChannelInboundHandler {
    typealias InboundIn = SMTPResponse
    typealias OutboundIn = Email
    typealias OutboundOut = SMTPRequest

    private enum State: Sendable {
        case idle(didSend: Bool)
        case helloSent(afterStartTLS: Bool)
        case startTLSSent
        case authBegan(Configuration.Credentials)
        case usernameSent(Configuration.Credentials)
        case passwordSent
        case mailFromSent
        case recipientSent(IndexingIterator<Array<Email.Contact>>)
        case dataCommandSent
        case mailDataSent
        case quitSent
    }

    private let configuration: Configuration
    private let email: Email
    private let allDonePromise: EventLoopPromise<Void>
    private var state = State.idle(didSend: false)

    init(configuration: Configuration, email: Email, allDonePromise: EventLoopPromise<Void>) {
        self.configuration = configuration
        self.email = email
        self.allDonePromise = allDonePromise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard unwrapInboundIn(data).verify(failing: allDonePromise) else { return }

        @inline(__always)
        func send(command: SMTPRequest) {
            context.writeAndFlush(wrapOutboundOut(command)).cascadeFailure(to: allDonePromise)
        }

        func nextState(for iterator: inout IndexingIterator<Array<Email.Contact>>) -> State {
            if let next = iterator.next() {
                send(command: .recipient(next.emailAddress))
                return .recipientSent(iterator)
            } else {
                send(command: .data)
                return .dataCommandSent
            }
        }

        func nextStateAfterSayHello(afterStartTLS: Bool) -> State {
            if !afterStartTLS, case .startTLS(_) = configuration.server.encryption {
                send(command: .startTLS)
                return .startTLSSent
            } else if let creds = configuration.credentials {
                send(command: .beginAuthentication)
                return .authBegan(creds)
            } else {
                send(command: .mailFrom(email.sender.emailAddress))
                return .mailFromSent
            }
        }

        switch state {
        case .idle(didSend: false):
            send(command: .sayHello(serverName: configuration.server.hostname,
                                    useEHello: configuration.featureFlags.contains(.useESMTP)))
            state = .helloSent(afterStartTLS: false)
        case .helloSent(let afterStartTLS):
            state = nextStateAfterSayHello(afterStartTLS: afterStartTLS)
        case .startTLSSent:
            send(command: .sayHello(serverName: configuration.server.hostname,
                                    useEHello: configuration.featureFlags.contains(.useESMTP)))
            state = .helloSent(afterStartTLS: true)
        case .authBegan(let credentials):
            send(command: .authUser(credentials.username))
            state = .usernameSent(credentials)
        case .usernameSent(let credentials):
            send(command: .authPassword(credentials.password))
            state = .passwordSent
        case .passwordSent:
            send(command: .mailFrom(email.sender.emailAddress))
            state = .mailFromSent
        case .mailFromSent:
            var iterator = email.allRecipients.makeIterator()
            state = nextState(for: &iterator)
        case .recipientSent(var iterator):
            state = nextState(for: &iterator)
        case .dataCommandSent:
            send(command: .transferData(date: Date(), email: email))
            state = .mailDataSent
        case .mailDataSent:
            send(command: .quit)
            state = .quitSent
        case .quitSent:
            let promise = context.eventLoop.makePromise(of: Void.self)
            promise.futureResult.flatMapErrorThrowing { [state] in
                guard !Self.shouldIgnoreError($0, forState: state) else { return }
                throw $0
            }.cascade(to: allDonePromise)
            context.close(promise: promise)
            state = .idle(didSend: true)
        case .idle(didSend: true):
            break
        }
    }

    private static func shouldIgnoreError(_ error: any Error, forState state: State) -> Bool {
        // It seems that if the remote closes the connection, we're left with unclean shutdowns... :/
        guard error as? NIOSSLError == .uncleanShutdown || error is NIOExtrasErrors.LeftOverBytesError else { return false }
        switch state {
        case .quitSent, .idle(didSend: true): return true
        default: return false
        }
    }

    func errorCaught(ctx: ChannelHandlerContext, error: any Error) {
        guard !Self.shouldIgnoreError(error, forState: state) else { return }
        allDonePromise.fail(error)
    }
}
