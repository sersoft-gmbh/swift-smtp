import NIO

// Not a ByteToMessageDecoder since we already receive lines due to the `LineBasedFrameDecoder` in front of us.
final class SMTPResponseDecoder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = SMTPResponse

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard let firstFourBytes = buffer.readString(length: 4),
            let code = Int(firstFourBytes.dropLast())
            else { return context.fireErrorCaught(MalformedSMTPMessageError()) }

        let remainder = buffer.readString(length: buffer.readableBytes) ?? ""
        switch (firstFourBytes[firstFourBytes.startIndex], firstFourBytes[firstFourBytes.index(before: firstFourBytes.endIndex)]) {
        case ("2", " "), ("3", " "): context.fireChannelRead(wrapInboundOut(.ok(code, remainder)))
        case (_, "-"): break // intermediate message, ignore
        default: context.fireChannelRead(wrapInboundOut(.error(firstFourBytes + remainder)))
        }
    }
}
