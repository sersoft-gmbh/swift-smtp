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
            out.write(string: "\r\n")

            let boundary = String(UUID().uuidString.filter { $0.isHexDigit })
            let contentType: String
            let body: String
            switch email.body {
            case .plain(let plain):
                contentType = email.attachments.isEmpty ? #"text/plain; charset="UTF-8""# : #"multipart/alternative; boundary="\#(boundary)""#
                body = plain
            case .html(let html):
                contentType = email.attachments.isEmpty ? #"text/html; charset="UTF-8""# : #"multipart/alternative; boundary="\#(boundary)""#
                body = html
            case .universal(let plain, let html):
                contentType = #"multipart/alternative; boundary="\#(boundary)""#
                body = """
                --\(boundary)\r\n\
                Content-type: text/html; charset="UTF-8"\r\n\r\n\
                \(html)\r\n\
                --\(boundary)\r\n\
                Content-type: text/plain; charset="UTF-8"\r\n\r\n\
                \(plain)\r\n\
                --\(boundary)\r\n
                """
            }
            out.write(string: "Content-type: \(contentType)\r\n")
            out.write(string: "Mime-Version: 1.0\r\n\r\n")
            out.write(string: body)
            for attachment in email.attachments {
                out.write(string: "Content-Type: \(attachment.contentType)\r\n")
                out.write(string: "Content-Transfer-Encoding: base64\r\n")
                out.write(string: #"Content-Disposition: attachment; filename="\#(attachment.name)"\r\n\r\n"#)
                out.write(string: "\(attachment.data.base64EncodedString())\r\n")
                out.write(string: "--\(boundary)\r\n")
            }
            out.write(string: "\r\n.")
        case .quit:
            out.write(string: "QUIT")
        }
        out.write(string: "\r\n")
    }
}
