import NIO
import NIOSSL

internal final class StartTLSDuplexHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = SMTPResponse
    typealias InboundOut = SMTPResponse
    typealias OutboundIn = SMTPRequest
    typealias OutboundOut = SMTPRequest

    private enum State {
        case idle
        case waitingForStartTLSResponse
        case finished
    }

    private let server: Configuration.Server
    private let tlsMode: Configuration.Server.Encryption.StartTLSMode

    private var state = State.idle

    init(server: Configuration.Server, tlsMode: Configuration.Server.Encryption.StartTLSMode) {
        self.server = server
        self.tlsMode = tlsMode
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .waitingForStartTLSResponse = state else {
            context.fireChannelRead(data)
            return
        }

        defer { state = .finished }

        do {
            try unwrapInboundIn(data).validate()
        } catch {
            switch tlsMode {
            case .always: context.fireErrorCaught(error)
            case .ifAvailable:
                context.fireChannelRead(wrapInboundOut(.ok(201, "STARTTLS is not supported")))
            }
            return
        }
        do {
            let sslContext = try NIOSSLContext(configuration: .forClient())
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: server.hostname)
            _ = context.channel.pipeline.addHandler(sslHandler, position: .first)
            context.fireChannelRead(data)
            _ = context.channel.pipeline.removeHandler(self)
        } catch {
            context.fireErrorCaught(error)
        }
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if case .startTLS = unwrapOutboundIn(data) {
            state = .waitingForStartTLSResponse
        }
        context.write(data, promise: promise)
    }
}
