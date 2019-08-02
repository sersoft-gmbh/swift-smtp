import NIO

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
        case idle
        case helloSent
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
    private var state = State.idle

    init(configuration: Configuration, email: Email, allDonePromise: EventLoopPromise<Void>) {
        self.configuration = configuration
        self.email = email
        self.allDonePromise = allDonePromise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard unwrapInboundIn(data).verify(failing: allDonePromise) else { return }

        func send(command: SMTPRequest) {
            context.writeAndFlush(wrapOutboundOut(command)).cascadeFailure(promise: allDonePromise)
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
        case .idle:
            send(command: .sayHello(serverName: configuration.server.hostname))
            state = .helloSent
        case .helloSent:
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
            context.close(promise: allDonePromise)
            state = .idle
        }
    }

    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        allDonePromise.fail(error: error)
    }
}
