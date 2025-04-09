#if swift(>=6.0)
import Foundation
import Algorithms
import NIO
#else
public import Foundation
public import Algorithms
public import NIO
#endif

extension Date {
    private static let smtpLocale = Locale(identifier: "en_US_POSIX")
    private static let smtpFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = smtpLocale
        formatter.timeZone = .current
        formatter.calendar = .current
        return formatter
    }()

    /* fileprivate but @testable*/
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

    private func encodeAttachments(_ attachments: some Collection<Email.Attachment>,
                                   separatedWith boundary: String) -> String {
        assert(!attachments.isEmpty)
        return attachments.lazy.map {
            """
            \(contentTypeHeaders($0.contentType, usesBase64: true))\r\n\
            Content-Disposition: \($0.isInline ? "inline" : "attachment"); filename="\($0.name)"\r\n\
            \($0.contentID.map { "Content-ID: <\($0)>\r\n" } ?? "")\r\n\
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
        case .transferData(let date, let email):
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
            writeLine("MIME-Version: 1.0")

            func writeHeaders(contentType: String, usesBase64: Bool) {
                writeLine(contentTypeHeaders(contentType, usesBase64: usesBase64), lineEndings: 2)
            }

            func writeBoundary(_ boundary: String, isEnd: Bool = false) {
                writeLine(isEnd ? ("--" + boundary + "--") : ("--" + boundary))
            }

            let attachments = {
                var attachments = email.attachments
                let splitIndex = attachments.stablePartition(by: \.isInline)
                return (inline: attachments[splitIndex...], regular: attachments[..<splitIndex])
            }()

            func withRegularAttachmentsPart(_ content: () -> ()) {
                if (attachments.regular.isEmpty) {
                    content()
                } else {
                    let mixedBoundary = createMultipartBoundary()
                    writeHeaders(contentType: #"multipart/mixed; boundary=\#(mixedBoundary)"#, usesBase64: false)
                    writeBoundary(mixedBoundary)
                    content()
                    writeBoundary(mixedBoundary)
                    writeLine(encodeAttachments(attachments.regular, separatedWith: mixedBoundary))
                    writeBoundary(mixedBoundary, isEnd: true)
                }
            }

            func withInlineAttachmentsPart(_ content: () -> ()) {
                if (attachments.inline.isEmpty) {
                    content()
                } else {
                    let relatedBoundary = createMultipartBoundary()
                    writeHeaders(contentType: #"multipart/related; boundary=\#(relatedBoundary)"#, usesBase64: false)
                    writeBoundary(relatedBoundary)
                    content()
                    writeBoundary(relatedBoundary)
                    writeLine(encodeAttachments(attachments.inline, separatedWith: relatedBoundary))
                    writeBoundary(relatedBoundary, isEnd: true)
                }
            }

            withRegularAttachmentsPart {
                withInlineAttachmentsPart {
                    switch (email.body) {
                    case .plain(let plain):
                        writeHeaders(contentType: #"text/plain; charset="UTF-8""#, usesBase64: base64EncodeAllMessages)
                        writeLine(base64EncodedIfNeeded(plain))
                    case .html(let html):
                        writeHeaders(contentType: #"text/html; charset="UTF-8""#, usesBase64: base64EncodeAllMessages)
                        writeLine(base64EncodedIfNeeded(html))
                    case .universal(let plain, let html):
                        let alternativeBoundary = createMultipartBoundary()
                        writeHeaders(contentType: #"multipart/alternative; boundary=\#(alternativeBoundary)"#, usesBase64: false)
                        writeBoundary(alternativeBoundary)
                        writeHeaders(contentType: #"text/plain; charset="UTF-8""#, usesBase64: base64EncodeAllMessages)
                        writeLine(base64EncodedIfNeeded(plain), lineEndings: 2)
                        writeBoundary(alternativeBoundary)
                        writeHeaders(contentType: #"text/html; charset="UTF-8""#, usesBase64: base64EncodeAllMessages)
                        writeLine(base64EncodedIfNeeded(html), lineEndings: 2)
                        writeBoundary(alternativeBoundary, isEnd: true)
                    }
                }
            }

            out.writeString("\r\n.") // second \r\n is added at the very end of the function
        case .quit:
            out.writeString("QUIT")
        }
        out.writeString("\r\n")
    }
}
