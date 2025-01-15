#if swift(>=6.0)
import Foundation
import NIO
#else
public import Foundation
public import NIO
#endif

fileprivate extension Date {
    private static let smtpLocale = Locale(identifier: "en_US_POSIX")
    private static let smtpFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = smtpLocale
        return formatter
    }()

    var formattedForSMTP: String {
#if swift(<6.0) && !canImport(Darwin)
        return Self.smtpFormatter.string(from: self)
#else
        if #available(macOS 12, iOS 15, tvOS 15, watchOS 6, *) {
            return formatted(VerbatimFormatStyle(
                format: "\(weekday: .abbreviated), \(day: .twoDigits) \(standaloneMonth: .abbreviated) \(year: .padded(4)) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) \(timeZone: .iso8601(.short))",
                locale: Self.smtpLocale, timeZone: .current, calendar: .current))
        } else {
            return Self.smtpFormatter.string(from: self)
        }
#endif
    }
}

struct SMTPRequestEncoder: MessageToByteEncoder {
    typealias OutboundIn = SMTPRequest

    let base64EncodeAllMessages: Bool
    let base64EncodingOptions: Data.Base64EncodingOptions

    private func createMultipartBoundary() -> String {
        String(UUID().uuidString.filter(\.isHexDigit))
    }

    private func contentTypeHeaders(_ contentType: String, usesBase64: Bool) -> String {
        var headers = "Content-Type: \(contentType)"
        if usesBase64 {
            headers += "\r\nContent-Transfer-Encoding: base64"
        }
        return headers
    }

    private func encodeAttachments(_ attachments: Array<Email.Attachment>,
                                   separatedWith boundary: String) -> String {
        assert(!attachments.isEmpty)
        return attachments.lazy.map {
            """
            \(contentTypeHeaders($0.contentType, usesBase64: true))\r\n\
            Content-Disposition: attachment; filename="\($0.name)"\r\n\r\n\
            \($0.data.base64EncodedString(options: base64EncodingOptions))\r\n
            """
        }.joined(separator: "\r\n--\(boundary)\r\n")
    }

    private func base64EncodedIfNeeded(_ text: String) -> String {
        guard base64EncodeAllMessages else { return text }
        return Data(text.utf8).base64EncodedString(options: base64EncodingOptions)
    }

    func encode(data: OutboundIn, out: inout ByteBuffer) throws {
        func writeLine(_ line: String, lineEndings: Int = 1) {
            out.writeString(line + String(repeating: "\r\n", count: lineEndings))
        }

        switch data {
        case .sayHello(let serverName, let useEHello):
            out.writeString("\(useEHello ? "EHLO" : "HELO") \(serverName)")
        case .startTLS:
            out.writeString("STARTTLS")
        case .beginAuthentication:
            out.writeString("AUTH LOGIN")
        case .authUser(let user):
            out.writeBytes(Data(user.utf8).base64EncodedData(options: base64EncodingOptions))
        case .authPassword(let password):
            out.writeBytes(Data(password.utf8).base64EncodedData(options: base64EncodingOptions))
        case .mailFrom(let from):
            out.writeString("MAIL FROM:<\(from)>")
        case .recipient(let rcpt):
            out.writeString("RCPT TO:<\(rcpt)>")
        case .data:
            out.writeString("DATA")
        case .transferData(let email):
            let date = Date()
            writeLine("From: \(email.sender.asMIME)")
            writeLine("To: \(email.recipients.lazy.map(\.asMIME).joined(separator: ", "))")
            if let replyTo = email.replyTo {
                writeLine("Reply-to: \(replyTo.asMIME)")
            }
            if !email.cc.isEmpty {
                writeLine("Cc: \(email.cc.lazy.map(\.asMIME).joined(separator: ", "))")
            }
            writeLine("Date: \(date.formattedForSMTP)")
            writeLine("Message-ID: <\(date.timeIntervalSince1970)\(email.sender.emailAddress.drop { $0 != "@" })>")
            writeLine("Subject: \(email.subject)")

            func writeHeaders(contentType: String, usesBase64: Bool) {
                writeLine(contentTypeHeaders(contentType, usesBase64: usesBase64))
                writeLine("MIME-Version: 1.0", lineEndings: 2)
            }

            func writeBoundary(_ boundary: String, isEnd: Bool = false) {
                writeLine(isEnd ? ("--" + boundary + "--") : ("--" + boundary))
            }

            switch (email.body, email.attachments.isEmpty) {
            case (.plain(let plain), true):
                writeHeaders(contentType: #"text/plain; charset="UTF-8""#,
                             usesBase64: base64EncodeAllMessages)
                writeLine(base64EncodedIfNeeded(plain))
            case (.plain(let plain), false):
                let boundary = createMultipartBoundary()
                writeHeaders(contentType: #"multipart/mixed; boundary=\#(boundary)"#,
                             usesBase64: false)
                writeBoundary(boundary)
                writeLine(contentTypeHeaders(#"text/plain; charset="UTF-8""#,
                                             usesBase64: base64EncodeAllMessages),
                          lineEndings: 2)
                writeLine(base64EncodedIfNeeded(plain), lineEndings: 2)
                writeBoundary(boundary)
                writeLine(encodeAttachments(email.attachments, separatedWith: boundary))
                writeBoundary(boundary, isEnd: true)
            case (.html(let html), true):
                writeHeaders(contentType: #"text/html; charset="UTF-8""#,
                             usesBase64: base64EncodeAllMessages)
                writeLine(base64EncodedIfNeeded(html))
            case (.html(let html), false):
                let boundary = createMultipartBoundary()
                writeHeaders(contentType: #"multipart/mixed; boundary=\#(boundary)"#, 
                             usesBase64: false)
                writeBoundary(boundary)
                writeLine(contentTypeHeaders(#"text/html; charset="UTF-8""#,
                                             usesBase64: base64EncodeAllMessages),
                          lineEndings: 2)
                writeLine(base64EncodedIfNeeded(html), lineEndings: 2)
                writeBoundary(boundary)
                writeLine(encodeAttachments(email.attachments, separatedWith: boundary))
                writeBoundary(boundary, isEnd: true)
            case (.universal(let plain, let html), true):
                let boundary = createMultipartBoundary()
                writeHeaders(contentType: #"multipart/alternative; boundary=\#(boundary)"#, 
                             usesBase64: false)
                writeBoundary(boundary)
                writeLine(contentTypeHeaders(#"text/plain; charset="UTF-8""#,
                                             usesBase64: base64EncodeAllMessages),
                          lineEndings: 2)
                writeLine(base64EncodedIfNeeded(plain), lineEndings: 2)
                writeBoundary(boundary)
                writeLine(contentTypeHeaders(#"text/html; charset="UTF-8""#,
                                             usesBase64: base64EncodeAllMessages),
                          lineEndings: 2)
                writeLine(base64EncodedIfNeeded(html), lineEndings: 2)
                writeBoundary(boundary, isEnd: true)
            case (.universal(let plain, let html), false):
                let mainBoundary = createMultipartBoundary()
                let attachmentsBoundary = createMultipartBoundary()

                writeHeaders(contentType: #"multipart/alternative; boundary=\#(mainBoundary)"#, 
                             usesBase64: false)
                writeBoundary(mainBoundary)
                writeLine(contentTypeHeaders(#"text/plain; charset="UTF-8""#,
                                             usesBase64: base64EncodeAllMessages),
                          lineEndings: 2)
                writeLine(base64EncodedIfNeeded(plain), lineEndings: 2)
                writeBoundary(mainBoundary)
                
                writeLine(contentTypeHeaders(#"multipart/mixed; boundary=\#(attachmentsBoundary)"#,
                                             usesBase64: false),
                          lineEndings: 2)
                writeBoundary(attachmentsBoundary)
                writeLine(contentTypeHeaders(#"text/html; charset="UTF-8""#,
                                             usesBase64: base64EncodeAllMessages),
                          lineEndings: 2)
                writeLine(base64EncodedIfNeeded(html), lineEndings: 2)
                writeBoundary(attachmentsBoundary)
                writeLine(encodeAttachments(email.attachments, separatedWith: attachmentsBoundary))
                writeBoundary(attachmentsBoundary, isEnd: true)
                writeBoundary(mainBoundary, isEnd: true)
            }
            out.writeString("\r\n.")
        case .quit:
            out.writeString("QUIT")
        }
        out.writeString("\r\n")
    }
}
