import Foundation
import NIO

fileprivate extension DateFormatter {
    static let smtp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}

struct SMTPRequestEncoder: MessageToByteEncoder {
    typealias OutboundIn = SMTPRequest

    let base64EncodingOptions: Data.Base64EncodingOptions

    private func createMultipartBoundary() -> String {
        String(UUID().uuidString.filter(\.isHexDigit))
    }

    private func encode(attachments: [Email.Attachment], with boundary: String) -> String {
        assert(!attachments.isEmpty)
        return attachments.lazy.map {
            """
            Content-Type: \($0.contentType)\r\n\
            Content-Transfer-Encoding: base64\r\n\
            Content-Disposition: attachment; filename="\($0.name)"\r\n\r\n\
            \($0.data.base64EncodedString(options: base64EncodingOptions))\r\n
            """
        }.joined(separator: "\r\n--\(boundary)\r\n")
    }

    func encode(data: OutboundIn, out: inout ByteBuffer) throws {
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
            out.writeString("From: \(email.sender.asMIME)\r\n")
            out.writeString("To: \(email.recipients.lazy.map(\.asMIME).joined(separator: ", "))\r\n")
            if let replyTo = email.replyTo {
                out.writeString("Reply-to: \(replyTo.asMIME)\r\n")
            }
            if !email.cc.isEmpty {
                out.writeString("Cc: \(email.cc.lazy.map(\.asMIME).joined(separator: ", "))\r\n")
            }
            out.writeString("Date: \(DateFormatter.smtp.string(from: date))\r\n")
            out.writeString("Message-ID: <\(date.timeIntervalSince1970)\(email.sender.emailAddress.drop { $0 != "@" })>\r\n")
            out.writeString("Subject: \(email.subject)\r\n")

            let contentType: String
            let bodyAndAttachments: String
            switch (email.body, email.attachments.isEmpty) {
            case (.plain(let plain), true):
                contentType = #"text/plain; charset="UTF-8""#
                bodyAndAttachments = plain + "\r\n"
            case (.plain(let plain), false):
                let boundary = createMultipartBoundary()
                contentType = #"multipart/mixed; boundary=\#(boundary)"#
                bodyAndAttachments = """
                --\(boundary)\r\n\
                Content-Type: text/plain; charset="UTF-8"\r\n\r\n\
                \(plain)\r\n\r\n\
                --\(boundary)\r\n\
                \(encode(attachments: email.attachments, with: boundary))\r\n\
                --\(boundary)--\r\n
                """
            case (.html(let html), true):
                contentType = #"text/html; charset="UTF-8""#
                bodyAndAttachments = html + "\r\n"
            case (.html(let html), false):
                let boundary = createMultipartBoundary()
                contentType = #"multipart/mixed; boundary=\#(boundary)"#
                bodyAndAttachments = """
                --\(boundary)\r\n\
                Content-Type: text/html; charset="UTF-8"\r\n\r\n\
                \(html)\r\n\r\n\
                --\(boundary)\r\n\
                \(encode(attachments: email.attachments, with: boundary))\r\n\
                --\(boundary)--\r\n
                """
            case (.universal(let plain, let html), true):
                let boundary = createMultipartBoundary()
                contentType = #"multipart/alternative; boundary=\#(boundary)"#
                bodyAndAttachments = """
                --\(boundary)\r\n\
                Content-Type: text/plain; charset="UTF-8"\r\n\r\n\
                \(plain)\r\n\r\n\
                --\(boundary)\r\n\
                Content-Type: text/html; charset="UTF-8"\r\n\r\n\
                \(html)\r\n\r\n\
                --\(boundary)--\r\n
                """
            case (.universal(let plain, let html), false):
                let mainBoundary = createMultipartBoundary()
                let attachmentsBoundary = createMultipartBoundary()
                contentType = #"multipart/alternative; boundary=\#(mainBoundary)"#
                bodyAndAttachments = """
                --\(mainBoundary)\r\n\
                Content-Type: text/plain; charset="UTF-8"\r\n\r\n\
                \(plain)\r\n\r\n\
                --\(mainBoundary)\r\n\
                Content-Type: multipart/mixed; boundary=\(attachmentsBoundary)\r\n\r\n\
                --\(attachmentsBoundary)\r\n\
                Content-Type: text/html; charset="UTF-8"\r\n\r\n\
                \(html)\r\n\r\n\
                --\(attachmentsBoundary)\r\n\
                \(encode(attachments: email.attachments, with: attachmentsBoundary))\r\n\
                --\(attachmentsBoundary)--\r\n\r\n\
                --\(mainBoundary)--\r\n
                """
            }
            out.writeString("Content-type: \(contentType)\r\n")
            out.writeString("MIME-Version: 1.0\r\n\r\n")
            out.writeString(bodyAndAttachments)
            out.writeString("\r\n.")
        case .quit:
            out.writeString("QUIT")
        }
        out.writeString("\r\n")
    }
}
