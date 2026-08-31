import struct Foundation.UUID
import struct Foundation.Data
import struct Foundation.Date
import struct NIO.ByteBuffer
fileprivate import Algorithms

#if compiler(>=6.3)
@safe
private struct LegacyMutableRef<Value: ~Copyable>: ~Copyable, ~Escapable {
    private let _ptr: UnsafeMutablePointer<Value>

#if compiler(>=6.4)
    var value: Value {
        @_unsafeSelfDependentResult
        borrow { unsafe _ptr.pointee }
        @_unsafeSelfDependentResult
        mutate { unsafe &_ptr.pointee }
    }
#else
    var value: Value {
        _read { yield unsafe _ptr.pointee }
        _modify { yield unsafe &_ptr.pointee }
    }
#endif

    @_lifetime(&target)
    init(_ target: inout Value) {
        // This prevents stack protections to be triggered.
        // Uses `Builtin.unprotectedAddressOf` internally, which is what MutableRef uses in Swift 6.4 as well.
        unsafe _ptr = _withUnprotectedUnsafeMutablePointer(to: &target) { unsafe $0 }
    }
}
#elseif compiler(>=6.2)
@safe
private struct LegacyMutableRef<Value: ~Copyable>: ~Copyable {
    private let _ptr: UnsafeMutablePointer<Value>

    var value: Value {
        _read { yield unsafe _ptr.pointee }
        _modify { yield unsafe &_ptr.pointee }
    }

    init(_ target: inout Value) {
        // This prevents stack protections to be triggered.
        // Uses `Builtin.unprotectedAddressOf` internally, which is what MutableRef uses in Swift 6.4 as well.
        unsafe _ptr = _withUnprotectedUnsafeMutablePointer(to: &target) { unsafe $0 }
    }
}
#else
private struct LegacyMutableRef<Value: ~Copyable>: ~Copyable {
    private let _ptr: UnsafeMutablePointer<Value>

    var value: Value {
        _read { yield _ptr.pointee }
        _modify { yield &_ptr.pointee }
    }

    init(_ target: inout Value) {
        // This prevents stack protections to be triggered.
        // Uses `Builtin.unprotectedAddressOf` internally, which is what MutableRef uses in Swift 6.4 as well.
        _ptr = _withUnprotectedUnsafeMutablePointer(to: &target) { $0 }
    }
}
#endif
extension LegacyMutableRef: @unchecked Sendable where Value: Sendable & ~Copyable {}

#if compiler(>=6.3)
fileprivate protocol MIMEWriter: Sendable, ~Copyable, ~Escapable {
#if compiler(>=6.4)
    var byteBuffer: ByteBuffer { borrow mutate }
#else
    var byteBuffer: ByteBuffer { get set }
#endif
}
#else
fileprivate protocol MIMEWriter: Sendable, ~Copyable {
    var byteBuffer: ByteBuffer { get set }
}
#endif

#if compiler(>=6.4)
@available(anyAppleOS 27, *)
fileprivate struct ModernMIMEWriter: MIMEWriter, ~Copyable, ~Escapable {
    private var byteBufferRef: MutableRef<ByteBuffer>

    fileprivate var byteBuffer: ByteBuffer {
        borrow { byteBufferRef.value }
        mutate { &byteBufferRef.value }
    }


    @_lifetime(&byteBuffer)
    init(byteBuffer: inout ByteBuffer) {
        self.byteBufferRef = MutableRef(&byteBuffer)
    }
}
#endif

#if compiler(>=6.3)
fileprivate struct LegacyMIMEWriter: MIMEWriter, ~Copyable, ~Escapable {
    private var byteBufferRef: LegacyMutableRef<ByteBuffer>

#if compiler(>=6.4)
    fileprivate var byteBuffer: ByteBuffer {
        borrow { byteBufferRef.value }
        mutate { &byteBufferRef.value }
    }
#else
    fileprivate var byteBuffer: ByteBuffer {
        _read { yield byteBufferRef.value }
        _modify { yield &byteBufferRef.value }
    }
#endif

    @_lifetime(&byteBuffer)
    init(byteBuffer: inout ByteBuffer) {
        self.byteBufferRef = LegacyMutableRef(&byteBuffer)
    }
}
#else
fileprivate struct LegacyMIMEWriter: MIMEWriter, ~Copyable {
    private var byteBufferRef: LegacyMutableRef<ByteBuffer>

    fileprivate var byteBuffer: ByteBuffer {
        _read { yield byteBufferRef.value }
        _modify { yield &byteBufferRef.value }
    }

    init(byteBuffer: inout ByteBuffer) {
        self.byteBufferRef = LegacyMutableRef(&byteBuffer)
    }
}
#endif

#if swift(>=6.3)
fileprivate typealias NonEscapable = ~Escapable
#else
fileprivate typealias NonEscapable = Any
#endif

fileprivate extension MIMEWriter where Self: ~Copyable, Self: NonEscapable {
    private mutating func writeBytesLine(_ bytes: some Sequence<UInt8>) {
        byteBuffer.writeBytes(bytes)
        endLine()
    }

    private mutating func writeLine(_ line: String) {
        byteBuffer.writeString(line)
        endLine()
    }

    mutating func endLine() {
        byteBuffer.writeBytes(.crlf)
    }

    mutating func writeHeader(name: String, value: String) {
        writeLine("\(name): \(value)")
    }

    mutating func writeContentTypeHeader(_ contentType: String) {
        writeHeader(name: "Content-Type", value: contentType)
    }

    mutating func writeContentTransferEncodingHeader(_ contentTransferEncoding: String) {
        writeHeader(name: "Content-Transfer-Encoding", value: contentTransferEncoding)
    }

    mutating func writeContentTransferEncodingBase64HeaderIfNeeded(_ isBase64: Bool) {
        guard isBase64 else { return }
        writeContentTransferEncodingHeader("base64")
    }

    mutating func writeBody(_ body: String) {
        writeLine(body)
    }

    mutating func writeBody(_ body: some Sequence<UInt8>) {
        writeBytesLine(body)
    }

    mutating func withMultipartWriter(of subtype: String, do work: (((inout Self) -> ()) -> ()) -> ()) {
        let boundary = UUID().uuidString.filter(\.isHexDigit)
        writeContentTypeHeader("multipart/\(subtype); boundary=\(boundary)")
        endLine()
        work {
            writeLine("--\(boundary)")
            $0(&self)
        }
        writeLine("--\(boundary)--")
    }

    mutating func withMultipartWriterIfNeeded(_ needed: Bool,
                                              of subtype: @autoclosure () -> String,
                                              do work: (((inout Self) -> ()) -> ()) -> ()) {
        guard needed else { return work({ $0(&self) }) }
        withMultipartWriter(of: subtype(), do: work)
    }
}

fileprivate extension Email.Attachment {
    func mimeEncode(into writer: inout some MIMEWriter & ~Copyable & NonEscapable,
                    base64EncodingOptions: Data.Base64EncodingOptions) {
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
    func mimeEncode(into writer: inout some MIMEWriter & ~Copyable & NonEscapable,
                    base64EncodeAllMessages: Bool,
                    base64EncodingOptions: Data.Base64EncodingOptions) {
        func base64EncodedIfNeeded(_ text: String) -> String {
            guard base64EncodeAllMessages else { return text }
            return Data(text.utf8).base64EncodedString(options: base64EncodingOptions)
        }

        func writePlain(_ plain: String, to writer: inout some MIMEWriter & ~Copyable & NonEscapable) {
            writer.writeContentTypeHeader(#"text/plain; charset="UTF-8""#)
            writer.writeContentTransferEncodingBase64HeaderIfNeeded(base64EncodeAllMessages)
            writer.endLine()
            writer.writeBody(base64EncodedIfNeeded(plain))
        }

        func writeHTML(_ html: String, to writer: inout some MIMEWriter & ~Copyable & NonEscapable) {
            writer.writeContentTypeHeader(#"text/html; charset="UTF-8""#)
            writer.writeContentTransferEncodingBase64HeaderIfNeeded(base64EncodeAllMessages)
            writer.endLine()
            writer.writeBody(base64EncodedIfNeeded(html))
        }



        switch self {
        case .plain(let plain): writePlain(plain, to: &writer)
        case .html(let html): writeHTML(html, to: &writer)
        case .universal(let plain, let html):
#if swift(<6.1)
            func addAlternativePart<T: MIMEWriter & ~Copyable & NonEscapable>(_ addPart: ((inout T) -> ()) -> ()) {
                addPart {
                    writePlain(plain, to: &$0)
                    $0.endLine()
                }
                addPart {
                    writeHTML(html, to: &$0)
                    $0.endLine()
                }
            }
            writer.withMultipartWriter(of: "alternative", do: addAlternativePart)
#else
            writer.withMultipartWriter(of: "alternative") { addPart in
                addPart {
                    writePlain(plain, to: &$0)
                    $0.endLine()
                }
                addPart {
                    writeHTML(html, to: &$0)
                    $0.endLine()
                }
            }
#endif
        }
    }
}

extension Email {
    private func _mimeEncode(into mimeWriter: inout some MIMEWriter & ~Copyable & NonEscapable,
                             date: Date,
                             base64EncodeAllMessages: Bool,
                             base64EncodingOptions: Data.Base64EncodingOptions) {
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
            body.mimeEncode(into: &mimeWriter,
                            base64EncodeAllMessages: base64EncodeAllMessages,
                            base64EncodingOptions: base64EncodingOptions)
        } else {
            let (inlineAttachments, regularAttachments) = {
                var attachments = attachments
                let splitIndex = attachments.stablePartition(by: \.isInline)
                return (inline: attachments[splitIndex...], regular: attachments[..<splitIndex])
            }()

#if compiler(<6.1)
            func addRelatedPart<T: MIMEWriter & ~Copyable & NonEscapable>(_ addPart: ((inout T) -> ()) -> ()) {
                addPart {
                    body.mimeEncode(into: &$0,
                                    base64EncodeAllMessages: base64EncodeAllMessages,
                                    base64EncodingOptions: base64EncodingOptions)
                }
                for attachment in inlineAttachments {
                    addPart {
                        attachment.mimeEncode(into: &$0, base64EncodingOptions: base64EncodingOptions)
                    }
                }
            }

            func addMixedPart<T: MIMEWriter & ~Copyable & NonEscapable>(_ addPart: ((inout T) -> ()) -> ()) {
                addPart {
                    $0.withMultipartWriterIfNeeded(!inlineAttachments.isEmpty, of: "related", do: addRelatedPart)
                }
                for attachment in regularAttachments {
                    addPart {
                        attachment.mimeEncode(into: &$0, base64EncodingOptions: base64EncodingOptions)
                    }
                }
            }

            mimeWriter.withMultipartWriterIfNeeded(!regularAttachments.isEmpty, of: "mixed", do: addMixedPart)
#else
            mimeWriter.withMultipartWriterIfNeeded(!regularAttachments.isEmpty, of: "mixed") { addPart in
                addPart {
                    $0.withMultipartWriterIfNeeded(!inlineAttachments.isEmpty, of: "related") { addPart in
                        addPart {
                            body.mimeEncode(into: &$0,
                                            base64EncodeAllMessages: base64EncodeAllMessages,
                                            base64EncodingOptions: base64EncodingOptions)
                        }
                        for attachment in inlineAttachments {
                            addPart {
                                attachment.mimeEncode(into: &$0, base64EncodingOptions: base64EncodingOptions)
                            }
                        }
                    }
                }
                for attachment in regularAttachments {
                    addPart {
                        attachment.mimeEncode(into: &$0, base64EncodingOptions: base64EncodingOptions)
                    }
                }
            }
#endif
        }
    }

    func mimeEncode(into byteBuffer: inout ByteBuffer,
                    date: Date,
                    base64EncodeAllMessages: Bool,
                    base64EncodingOptions: Data.Base64EncodingOptions) {
#if compiler(<6.4)
        var mimeWriter = LegacyMIMEWriter(byteBuffer: &byteBuffer)
        _mimeEncode(into: &mimeWriter,
                    date: date,
                    base64EncodeAllMessages: base64EncodeAllMessages,
                    base64EncodingOptions: base64EncodingOptions)
#else
        if #available(anyAppleOS 27, *) {
            var mimeWriter = ModernMIMEWriter(byteBuffer: &byteBuffer)
            _mimeEncode(into: &mimeWriter,
                        date: date,
                        base64EncodeAllMessages: base64EncodeAllMessages,
                        base64EncodingOptions: base64EncodingOptions)
        } else {
            var mimeWriter = LegacyMIMEWriter(byteBuffer: &byteBuffer)
            _mimeEncode(into: &mimeWriter,
                        date: date,
                        base64EncodeAllMessages: base64EncodeAllMessages,
                        base64EncodingOptions: base64EncodingOptions)
        }
#endif
    }
}
