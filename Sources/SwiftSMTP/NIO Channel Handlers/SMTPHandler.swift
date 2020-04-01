import NIO
import NIOSSL

fileprivate extension SMTPResponse {
    func verify<T>(failing promise: EventLoopPromise<T>) -> Bool {
        do {
            try validate()
            return true
        } catch {
            promise.fail(error)
            return false
        }
    }
}

final class SMTPHandler: ChannelInboundHandler {
    typealias InboundIn = SMTPResponse
    typealias OutboundIn = Email
    typealias OutboundOut = SMTPRequest

    private enum State {
        case idle(didSend: Bool)
        case helloSent(afterStartTLS: Bool)
        case startTLSSent
        case authBegan
        case usernameSent
        case passwordSent
        case mailFromSent
        case recipientSent(IndexingIterator<[Email.Contact]>)
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

    func channelRead(context ctx: ChannelHandlerContext, data: NIOAny) {
        guard unwrapInboundIn(data).verify(failing: allDonePromise) else { return }

        func send(command: SMTPRequest) {
            ctx.writeAndFlush(wrapOutboundOut(command)).cascadeFailure(to: allDonePromise)
        }

        func nextState(for iterator: inout IndexingIterator<[Email.Contact]>) -> State {
            if let next = iterator.next() {
                send(command: .recipient(next.emailAddress))
                return .recipientSent(iterator)
            } else {
                send(command: .data)
                return .dataCommandSent
            }
        }

        switch state {
        case .idle(didSend: false):
            send(command: .sayHello(serverName: configuration.server.hostname))
            state = .helloSent(afterStartTLS: false)
        case .helloSent(afterStartTLS: false):
            if case .startTLS(_) = configuration.server.encryption {
                send(command: .startTLS)
                state = .startTLSSent
            } else {
                send(command: .beginAuthentication)
                state = .authBegan
            }
        case .startTLSSent:
            send(command: .sayHello(serverName: configuration.server.hostname))
            state = .helloSent(afterStartTLS: true)
        case .helloSent(afterStartTLS: true):
            send(command: .beginAuthentication)
            state = .authBegan
        case .authBegan:
            send(command: .authUser(configuration.credentials.username))
            state = .usernameSent
        case .usernameSent:
            send(command: .authPassword(configuration.credentials.password))
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
            send(command: .transferData(email))
            state = .mailDataSent
        case .mailDataSent:
            send(command: .quit)
            state = .quitSent
        case .quitSent:
            let promise = ctx.eventLoop.makePromise(of: Void.self)
            promise.futureResult.flatMapErrorThrowing {
                guard !self.shouldIgnore(error: $0) else { return }
                throw $0
            }.cascade(to: allDonePromise)
            ctx.close(promise: promise)
            state = .idle(didSend: true)
        case .idle(didSend: true):
            break
        }
    }

    private func shouldIgnore(error: Error) -> Bool {
        // It seems that if the remote closes the connection, we're left with unclean shutdowns... :/
        guard error as? NIOSSLError == .uncleanShutdown || error is LeftOverBytesError else { return false }
        switch state {
        case .quitSent, .idle(didSend: true): return true
        default: return false
        }
    }

    func errorCaught(context ctx: ChannelHandlerContext, error: Error) {
        guard !shouldIgnore(error: error) else { return }
        allDonePromise.fail(error)
    }
}
