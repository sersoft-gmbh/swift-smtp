import NIO

final class SMTPResponseDecoder: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = SMTPResponse

    func channelRead(context ctx: ChannelHandlerContext, data: NIOAny) {
        var response = unwrapInboundIn(data)
        guard let firstFourBytes = response.readString(length: 4), let code = Int(firstFourBytes.dropLast()) else {
            ctx.fireErrorCaught(MalformedSMTPMessageError())
            return
        }

        let remainder = response.readString(length: response.readableBytes) ?? ""
        switch (firstFourBytes[firstFourBytes.startIndex], firstFourBytes[firstFourBytes.index(before: firstFourBytes.endIndex)]) {
        case ("2", " "), ("3", " "): ctx.fireChannelRead(wrapInboundOut(.ok(code, remainder)))
        case (_, "-"): break // intermediate message, ignore
        default: ctx.fireChannelRead(wrapInboundOut(.error(firstFourBytes + remainder)))
        }
    }
}
