import struct Foundation.UUID
import struct Foundation.Data
import struct Foundation.Date
import struct NIO.ByteBuffer
fileprivate import Algorithms

#if compiler(<6.4)
#if compiler(>=6.2)
@safe
private struct MutableRef<T: ~Copyable>: ~Copyable {
    private var _ptr: UnsafeMutablePointer<T>

    var value: T {
        _read { yield unsafe _ptr.pointee }
        nonmutating _modify { yield unsafe &_ptr.pointee }
    }

    init(_ target: inout T) {
        // This prevents stack protections to be triggered.
        // Uses `Builtin.unprotectedAddressOf` internally, which is what MutableRef uses in Swift 6.4 as well.
        unsafe _ptr = _withUnprotectedUnsafeMutablePointer(to: &target) { unsafe $0 }
    }
}
#else
private struct MutableRef<T: ~Copyable>: ~Copyable {
    private var _ptr: UnsafeMutablePointer<T>

    var value: T {
        _read { yield _ptr.pointee }
        nonmutating _modify { yield &_ptr.pointee }
    }

    init(_ target: inout T) {
        // This prevents stack protections to be triggered.
        // Uses `Builtin.unprotectedAddressOf` internally, which is what MutableRef uses in Swift 6.4 as well.
        _ptr = _withUnprotectedUnsafeMutablePointer(to: &target) { $0 }
    }
}
#endif

extension MutableRef: @unchecked Sendable where T: Sendable {}
#endif

// TODO: ~Escapable
private struct MIMEWriter: ~Copyable, Sendable {
    private let byteBuffer: MutableRef<ByteBuffer>

    init(byteBuffer: inout ByteBuffer) {
        self.byteBuffer = MutableRef(&byteBuffer)
    }

    private func writeBytesLine(_ bytes: some Sequence<UInt8>) {
        byteBuffer.value.writeBytes(bytes)
        endLine()
    }

    private func writeLine(_ line: String) {
        byteBuffer.value.writeString(line)
        endLine()
    }

    func endLine() {
        byteBuffer.value.writeBytes(.crlf)
    }

    func writeHeader(name: String, value: String) {
        writeLine("\(name): \(value)")
    }

    func writeContentTypeHeader(_ contentType: String) {
        writeHeader(name: "Content-Type", value: contentType)
    }

    func writeContentTransferEncodingHeader(_ contentTransferEncoding: String) {
        writeHeader(name: "Content-Transfer-Encoding", value: contentTransferEncoding)
    }

    func writeContentTransferEncodingBase64HeaderIfNeeded(_ isBase64: Bool) {
        guard isBase64 else { return }
        writeContentTransferEncodingHeader("base64")
    }

    func writeBody(_ body: String) {
        writeLine(body)
    }

    func writeBody(_ body: some Sequence<UInt8>) {
        writeBytesLine(body)
    }

    func withMultipartWriter(of subtype: String, do work: (((borrowing MIMEWriter) -> ()) -> ()) -> ()) {
        let boundary = UUID().uuidString.filter(\.isHexDigit)
        writeContentTypeHeader("multipart/\(subtype); boundary=\(boundary)")
        endLine()
        work {
            writeLine("--\(boundary)")
            $0(self)
        }
        writeLine("--\(boundary)--")
    }

    func withMultipartWriterIfNeeded(_ needed: Bool,
                                     of subtype: @autoclosure () -> String,
                                     do work: (((borrowing MIMEWriter) -> ()) -> ()) -> ()) {
        guard needed else { return work({ $0(self) }) }
        withMultipartWriter(of: subtype(), do: work)
    }
}

fileprivate extension Email.Attachment {
    func mimeEncode(into writer: borrowing MIMEWriter, base64EncodingOptions: Data.Base64EncodingOptions) {
        writer.writeContentTypeHeader(contentType)
        writer.writeContentTransferEncodingHeader("base64")
        // TODO: filename*
        writer.writeHeader(name: "Content-Disposition", value: #"\#(isInline ? "inline" : "attachment"); filename="\#(name)""#)
        if let contentID {
            writer.writeHeader(name: "Content-ID", value: "<\(contentID)>")
        }
        writer.endLine()
        writer.writeBody(data.base64EncodedData(options: base64EncodingOptions))
    }
}

fileprivate extension Email.Body {
    func mimeEncode(into writer: borrowing MIMEWriter,
                    base64EncodeAllMessages: Bool,
                    base64EncodingOptions: Data.Base64EncodingOptions) {
        func base64EncodedIfNeeded(_ text: String) -> String {
            guard base64EncodeAllMessages else { return text }
            return Data(text.utf8).base64EncodedString(options: base64EncodingOptions)
        }

        func writePlain(_ plain: String, to writer: borrowing MIMEWriter) {
            writer.writeContentTypeHeader(#"text/plain; charset="UTF-8""#)
            writer.writeContentTransferEncodingBase64HeaderIfNeeded(base64EncodeAllMessages)
            writer.endLine()
            writer.writeBody(base64EncodedIfNeeded(plain))
        }

        func writeHTML(_ html: String, to writer: borrowing MIMEWriter) {
            writer.writeContentTypeHeader(#"text/html; charset="UTF-8""#)
            writer.writeContentTransferEncodingBase64HeaderIfNeeded(base64EncodeAllMessages)
            writer.endLine()
            writer.writeBody(base64EncodedIfNeeded(html))
        }

        switch self {
        case .plain(let plain): writePlain(plain, to: writer)
        case .html(let html): writeHTML(html, to: writer)
        case .universal(let plain, let html):
            writer.withMultipartWriter(of: "alternative") { addPart in
                addPart {
                    writePlain(plain, to: $0)
                    $0.endLine()
                }
                addPart {
                    writeHTML(html, to: $0)
                    $0.endLine()
                }
            }
        }
    }
}

extension Email {
    func mimeEncode(into byteBuffer: inout ByteBuffer,
                    date: Date,
                    base64EncodeAllMessages: Bool,
                    base64EncodingOptions: Data.Base64EncodingOptions) {
        let mimeWriter = MIMEWriter(byteBuffer: &byteBuffer)
        mimeWriter.writeHeader(name: "From", value: sender.asMIME)
        mimeWriter.writeHeader(name: "To", value: recipients.lazy.map(\.asMIME).joined(separator: ", "))
        if let replyTo {
            mimeWriter.writeHeader(name: "Reply-To", value: replyTo.asMIME)
        }
        if !cc.isEmpty {
            mimeWriter.writeHeader(name: "Cc", value: cc.lazy.map(\.asMIME).joined(separator: ", "))
        }
        mimeWriter.writeHeader(name: "Date", value: date.formattedForSMTP)
        mimeWriter.writeHeader(name: "Message-ID", value: "<\(date.timeIntervalSince1970)\(sender.emailAddress.drop { $0 != "@" })>")
        mimeWriter.writeHeader(name: "Subject", value: subject)
        mimeWriter.writeHeader(name: "MIME-Version", value: "1.0")

        if attachments.isEmpty {
            body.mimeEncode(into: mimeWriter,
                            base64EncodeAllMessages: base64EncodeAllMessages,
                            base64EncodingOptions: base64EncodingOptions)
        } else {
            let (inlineAttachments, regularAttachments) = {
                var attachments = attachments
                let splitIndex = attachments.stablePartition(by: \.isInline)
                return (inline: attachments[splitIndex...], regular: attachments[..<splitIndex])
            }()
            mimeWriter.withMultipartWriterIfNeeded(!regularAttachments.isEmpty, of: "mixed") { addPart in
                addPart {
                    $0.withMultipartWriterIfNeeded(!inlineAttachments.isEmpty, of: "related") { addPart in
                        addPart {
                            body.mimeEncode(into: $0,
                                            base64EncodeAllMessages: base64EncodeAllMessages,
                                            base64EncodingOptions: base64EncodingOptions)
                        }
                        for attachment in inlineAttachments {
                            addPart {
                                attachment.mimeEncode(into: $0, base64EncodingOptions: base64EncodingOptions)
                            }
                        }
                    }
                }
                for attachment in regularAttachments {
                    addPart {
                        attachment.mimeEncode(into: $0, base64EncodingOptions: base64EncodingOptions)
                    }
                }
            }
        }
    }
}
