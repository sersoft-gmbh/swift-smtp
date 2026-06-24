import Foundation
import NIO
fileprivate import Algorithms

struct SMTPRequestEncoder: MessageToByteEncoder {
    typealias OutboundIn = SMTPRequest

    let base64EncodeAllMessages: Bool
    let base64EncodingOptions: Data.Base64EncodingOptions

    /// Writes `data` to `out`, doubling any `.` byte that appears at the start of a line.
    /// Per RFC 5321 §4.5.2 — the receiving server strips the leading dot to recover the original payload.
    /// "Start of line" means the byte at offset 0 of the payload, or any byte immediately following a CRLF.
    /// A `.` following a bare CR or bare LF is left untouched: SMTP lines are CRLF-delimited, so a receiver
    /// frames such a dot mid-line and does not un-stuff it. Doubling it there would corrupt the payload.
    private func writeDotStuffed(_ bytes: ByteBufferView, to out: inout ByteBuffer) {
        // Write contiguous runs in bulk, only breaking to insert an extra dot at a line-leading `.`.
        // Payloads with no leading dots (the common case) are written in a single `writeBytes`.
        var atStartOfLine = true
        var previousByte: UInt8 = 0
        var segmentStart = bytes.startIndex
        for (index, byte) in bytes.indexed() {
            if atStartOfLine && byte == .dot {
                out.writeBytes(bytes[segmentStart...index]) // flush the run up to and including the dot
                out.writeInteger(UInt8.dot)                 // then the extra stuffing dot, giving `..`
                segmentStart = bytes.index(after: index)
            }
            atStartOfLine = byte == .lineFeed && previousByte == .carriageReturn
            previousByte = byte
        }
        out.writeBytes(bytes[segmentStart...])
    }

    func encode(data: OutboundIn, out: inout ByteBuffer) throws {
        switch data {
        case .sayHello(let serverName, let useEHello):
            out.writeString("\(useEHello ? "EHLO" : "HELO") \(serverName)")
        case .startTLS:
            out.writeString("STARTTLS")
        case .beginAuthentication:
            out.writeString("AUTH LOGIN")
        case .authUser(let user): // TODO: This should move away from Foundation.Data and use ByteBuffer instead.
            out.writeBytes(Data(user.utf8).base64EncodedData(options: base64EncodingOptions))
        case .authPassword(let password): // TODO: This should move away from Foundation.Data and use ByteBuffer instead.
            out.writeBytes(Data(password.utf8).base64EncodedData(options: base64EncodingOptions))
        case .mailFrom(let from):
            out.writeString("MAIL FROM:<\(from)>")
        case .recipient(let rcpt):
            out.writeString("RCPT TO:<\(rcpt)>")
        case .data:
            out.writeString("DATA")
        case .transferPayload(.newlyComposed(let email, let date)):
            email.mimeEncode(into: &out, date: date,
                             base64EncodeAllMessages: base64EncodeAllMessages,
                             base64EncodingOptions: base64EncodingOptions)
            out.writeBytes(.crlf + CollectionOfOne(.dot)) // second \r\n is added at the very end of the function
        case .transferPayload(.precomposed(let messageData)):
            let view = messageData.readableBytesView
            writeDotStuffed(view, to: &out)
            // Use `elementsEqual` instead of `==` since the latter would incur overhead due to the array conversion.
            if !view.suffix(2).elementsEqual(.crlf) {
                out.writeBytes(.crlf)
            }
            out.writeInteger(UInt8.dot) // final \r\n is added at the very end of the function
        case .quit:
            out.writeString("QUIT")
        }
        out.writeBytes(.crlf)
    }
}
