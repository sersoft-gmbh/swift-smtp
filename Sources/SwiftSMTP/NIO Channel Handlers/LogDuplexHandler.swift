import NIO
import Foundation

final class LogDuplexHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        print("☁️ \(String(decoding: unwrapInboundIn(data).readableBytesView, as: UTF8.self))")
        ctx.fireChannelRead(data)
    }

    func write(ctx: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        print("💻 \(String(decoding: unwrapOutboundIn(data).readableBytesView, as: UTF8.self))")
        ctx.write(data, promise: promise)
    }
}
