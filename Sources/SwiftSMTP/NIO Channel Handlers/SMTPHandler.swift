import NIO
import NIOOpenSSL

fileprivate extension SMTPResponse {
    func verify<T>(failing promise: EventLoopPromise<T>) -> Bool {
        do {
            try validate()
            return true
        } catch {
            promise.fail(error: error)
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

    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        guard unwrapInboundIn(data).verify(failing: allDonePromise) else { return }

        func send(command: SMTPRequest) {
            ctx.writeAndFlush(wrapOutboundOut(command)).cascadeFailure(promise: allDonePromise)
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
            let promise = ctx.eventLoop.newPromise(of: Void.self)
            promise.futureResult.whenSuccess(allDonePromise.succeed)
            promise.futureResult.whenFailure(handleFailure)
            ctx.close(promise: promise)
            state = .idle(didSend: true)
        case .idle(didSend: true):
            break
        }
    }

    private func handleFailure(error: Error) {
        // It seems that if the remote closes the connection, we're left with unclean shutdowns... :/
        if error as? OpenSSLError == .uncleanShutdown || error is LeftOverBytesError {
            switch state {
            case .quitSent, .idle(didSend: true): return
            default: break
            }
        }
        allDonePromise.fail(error: error)
    }

    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        handleFailure(error: error)
    }
}
