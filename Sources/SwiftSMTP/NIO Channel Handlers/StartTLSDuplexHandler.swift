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

    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        guard case .waitingForStartTLSResponse = state else {
            ctx.fireChannelRead(data)
            return
        }
        defer { state = .finished }

        do {
            try unwrapInboundIn(data).validate()
        } catch {
            switch tlsMode {
            case .always: ctx.fireErrorCaught(error)
            case .ifAvailable:
                ctx.fireChannelRead(wrapInboundOut(.ok(201, "STARTTLS is not supported")))
            }
            return
        }
        do {
            let sslContext = try NIOSSLContext(configuration: .forClient())
            let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: server.hostname)
            _ = ctx.channel.pipeline.addHandler(sslHandler, name: nil, position: .first)
            ctx.fireChannelRead(data)
            _ = ctx.channel.pipeline.removeHandler(self)
        } catch {
            ctx.fireErrorCaught(error)
        }
    }

    func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        if case .startTLS = unwrapOutboundIn(data) {
            state = .waitingForStartTLSResponse
        }
        ctx.write(data, promise: promise)
    }
}
