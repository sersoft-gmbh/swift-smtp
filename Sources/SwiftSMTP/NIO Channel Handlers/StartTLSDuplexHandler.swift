import NIO
import NIOSSL

final class StartTLSDuplexHandler: ChannelDuplexHandler, RemovableChannelHandler {
    typealias InboundIn = SMTPResponse
    typealias InboundOut = SMTPResponse
    typealias OutboundIn = SMTPRequest
    typealias OutboundOut = SMTPRequest

    private enum State: Sendable {
        case idle
        case waitingForStartTLSResponse
        case finished
    }

    private let server: Configuration.Server
    private let tlsMode: Configuration.Server.Encryption.StartTLSMode
    private let sslContextProvider: () throws -> NIOSSLContext

    private var state = State.idle

    init(server: Configuration.Server,
         tlsMode: Configuration.Server.Encryption.StartTLSMode,
         sslContextProvider: @escaping () throws -> NIOSSLContext) {
        self.server = server
        self.tlsMode = tlsMode
        self.sslContextProvider = sslContextProvider
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .waitingForStartTLSResponse = state else {
            context.fireChannelRead(data)
            return
        }

        defer { state = .finished }

        switch (unwrapInboundIn(data), tlsMode) {
        case (.success(_), _): break
        case (.failure(_), .ifAvailable):
            context.fireChannelRead(wrapInboundOut(.success((201, "STARTTLS is not supported"))))
            return
        case (.failure(let error), .always):
            context.fireErrorCaught(error)
            return
        }

        do {
            let sslHandler = try NIOSSLClientHandler(context: sslContextProvider(), serverHostname: server.hostname)
            try context.channel.pipeline.syncOperations.addHandler(sslHandler, position: .first)
            state = .finished // set before continuing.
            context.fireChannelRead(data)
            // We can safely ignore the result of this.
            // If it fails, the guard at the beginning of the method will just make this handler "transparent".
            _ = context.channel.pipeline.syncOperations.removeHandler(self)
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

@available(*, unavailable)
extension StartTLSDuplexHandler: Sendable {}
