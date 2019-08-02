import Foundation
import NIO

fileprivate extension DateFormatter {
    static let smtp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}

final class SMTPRequestEncoder: MessageToByteEncoder {
    typealias OutboundIn = SMTPRequest

    private func createMultipartBoundary() -> String {
        return String(UUID().uuidString.filter { $0.isHexDigit })
    }

    private func encode(attachments: [Email.Attachment], with boundary: String) -> String {
        assert(!attachments.isEmpty)
        return attachments.lazy.map {
            """
            Content-Type: \($0.contentType)\r\n\
            Content-Transfer-Encoding: base64\r\n\
            Content-Disposition: attachment; filename="\($0.name)"\r\n\r\n\
            \($0.data.base64EncodedString())\r\n
            """
        }.joined(separator: "\r\n--\(boundary)\r\n")
    }

    func encode(ctx: ChannelHandlerContext, data: SMTPRequest, out: inout ByteBuffer) throws {
        switch data {
        case .sayHello(serverName: let server):
            out.write(string: "HELO \(server)")
        case .startTLS:
            out.write(string: "STARTTLS")
        case .beginAuthentication:
            out.write(string: "AUTH LOGIN")
        case .authUser(let user):
            out.write(bytes: Data(user.utf8).base64EncodedData())
        case .authPassword(let password):
            out.write(bytes: Data(password.utf8).base64EncodedData())
        case .mailFrom(let from):
            out.write(string: "MAIL FROM:<\(from)>")
        case .recipient(let rcpt):
            out.write(string: "RCPT TO:<\(rcpt)>")
        case .data:
            out.write(string: "DATA")
        case .transferData(let email):
            let date = Date()
            out.write(string: "From: \(email.sender.asMIME)\r\n")
            out.write(string: "To: \(email.recipients.map { $0.asMIME }.joined(separator: ", "))\r\n")
            if let replyTo = email.replyTo {
                out.write(string: "Reply-to: \(replyTo.asMIME)\r\n")
            }
            if !email.cc.isEmpty {
                out.write(string: "Cc: \(email.cc.map { $0.asMIME }.joined(separator: ", "))\r\n")
            }
            out.write(string: "Date: \(DateFormatter.smtp.string(from: date))\r\n")
            out.write(string: "Message-ID: <\(date.timeIntervalSince1970)\(email.sender.emailAddress.drop { $0 != "@" })>\r\n")
            out.write(string: "Subject: \(email.subject)\r\n")

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
            out.write(string: "Content-type: \(contentType)\r\n")
            out.write(string: "MIME-Version: 1.0\r\n\r\n")
            out.write(string: bodyAndAttachments)
            out.write(string: "\r\n.")
        case .quit:
            out.write(string: "QUIT")
        }
        out.write(string: "\r\n")
    }
}
