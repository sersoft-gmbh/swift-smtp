import RegexBuilder
import Testing
import Foundation
import NIO
@testable import SwiftSMTP

@Suite
struct SMTPRequestEncoderTests {
    private func encodeRequest(_ request: SMTPRequest,
                               base64EncodeAllMessages: Bool,
                               base64EncodingOptions: Data.Base64EncodingOptions) throws -> String {
        let encoder = SMTPRequestEncoder(base64EncodeAllMessages: base64EncodeAllMessages,
                                         base64EncodingOptions: base64EncodingOptions)
        var byteBuffer = ByteBufferAllocator().buffer(capacity: 1024)
        try encoder.encode(data: request, out: &byteBuffer)
        return byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func sayHello(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let server = "mail.server.tld"
        let ehello = try encodeRequest(.sayHello(serverName: server, useEHello: true),
                                       base64EncodeAllMessages: base64EncodeAllMessages,
                                       base64EncodingOptions: base64EncodingOptions)
        let normalHello = try encodeRequest(.sayHello(serverName: server, useEHello: false),
                                            base64EncodeAllMessages: base64EncodeAllMessages,
                                            base64EncodingOptions: base64EncodingOptions)
        #expect(ehello == "EHLO \(server)\r\n")
        #expect(normalHello == "HELO \(server)\r\n")
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func startTLS(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let encoded = try encodeRequest(.startTLS,
                                        base64EncodeAllMessages: base64EncodeAllMessages,
                                        base64EncodingOptions: base64EncodingOptions)
        #expect(encoded == "STARTTLS\r\n")
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func beginAuthentication(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let encoded = try encodeRequest(.beginAuthentication,
                                        base64EncodeAllMessages: base64EncodeAllMessages,
                                        base64EncodingOptions: base64EncodingOptions)
        #expect(encoded == "AUTH LOGIN\r\n")
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func authUser(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let encoded = try encodeRequest(.authUser("my.user@example.com"),
                                        base64EncodeAllMessages: base64EncodeAllMessages,
                                        base64EncodingOptions: base64EncodingOptions)
        #expect(encoded == "bXkudXNlckBleGFtcGxlLmNvbQ==\r\n")
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func authPassword(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let encoded = try encodeRequest(.authPassword("jB)7ie$sJ)Q8mXN@^ZR8RybVP!FDvwXG"),
                                        base64EncodeAllMessages: base64EncodeAllMessages,
                                        base64EncodingOptions: base64EncodingOptions)
        #expect(encoded == "akIpN2llJHNKKVE4bVhOQF5aUjhSeWJWUCFGRHZ3WEc=\r\n")
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func mailFrom(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let email = "some.sender@example.com"
        let encoded = try encodeRequest(.mailFrom(email),
                                        base64EncodeAllMessages: base64EncodeAllMessages,
                                        base64EncodingOptions: base64EncodingOptions)
        #expect(encoded == "MAIL FROM:<\(email)>\r\n")
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func mailTo(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let email = "some.receiver@example.com"
        let encoded = try encodeRequest(.recipient(email),
                                        base64EncodeAllMessages: base64EncodeAllMessages,
                                        base64EncodingOptions: base64EncodingOptions)
        #expect(encoded == "RCPT TO:<\(email)>\r\n")
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func data(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let encoded = try encodeRequest(.data,
                                        base64EncodeAllMessages: base64EncodeAllMessages,
                                        base64EncodingOptions: base64EncodingOptions)
        #expect(encoded == "DATA\r\n")
    }

    @Test(arguments: [true, false], [Data.Base64EncodingOptions.lineLength64Characters, .lineLength76Characters])
    func quit(base64EncodeAllMessages: Bool, base64EncodingOptions: Data.Base64EncodingOptions) async throws {
        let encoded = try encodeRequest(.quit,
                                        base64EncodeAllMessages: base64EncodeAllMessages,
                                        base64EncodingOptions: base64EncodingOptions)
        #expect(encoded == "QUIT\r\n")
    }

    @Test
    func transferPlainTextOnly() async throws {
        let senderServerName = "example.com"
        let sender = Email.Contact(name: "Sender Name", emailAddress: "some.sender@\(senderServerName)")
        let receiver = Email.Contact(name: "Receiver Name", emailAddress: "some.receiver@example.com")
        let subject = "Test Message"
        let plainTextBody = "The contents of this email\nare very simple and just for testing..."
        let date = Date(timeIntervalSince1970: 1744193604) // 2025-04-09T10:13:24Z
        let encoded = try encodeRequest(.transferData(date: date,
                                                      email: .init(sender: sender,
                                                                   recipients: [receiver],
                                                                   subject: subject,
                                                                   body: .plain(plainTextBody))),
                                        base64EncodeAllMessages: false,
                                        base64EncodingOptions: [])
        #expect(encoded == """
            From: "\(sender.name ?? "")" <\(sender.emailAddress)>\r\n\
            To: "\(receiver.name ?? "")" <\(receiver.emailAddress)>\r\n\
            Date: \(date.formattedForSMTP)\r\n\
            Message-ID: <\(date.timeIntervalSince1970)@\(senderServerName)>\r\n\
            Subject: \(subject)\r\n\
            MIME-Version: 1.0\r\n\
            Content-Type: text/plain; charset="UTF-8"\r\n\r\n\
            \(plainTextBody)\r\n\
            \r\n.\r\n
            """)
    }

    @Test
    func transferHTMLOnly() async throws {
        let senderServerName = "example.com"
        let sender = Email.Contact(name: "Sender Name", emailAddress: "some.sender@\(senderServerName)")
        let receiver = Email.Contact(name: "Receiver Name", emailAddress: "some.receiver@example.com")
        let subject = "Test Message"
        let htmlBody = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="utf-8" />
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
            </head>
            <body>
            <p>This is a test.</p>
            <p>Nothing more but a test.</p>
            </body>
            </html>
            """
        let date = Date(timeIntervalSince1970: 1744193604) // 2025-04-09T10:13:24Z
        let encoded = try encodeRequest(.transferData(date: date,
                                                      email: .init(sender: sender,
                                                                   recipients: [receiver],
                                                                   subject: subject,
                                                                   body: .html(htmlBody))),
                                        base64EncodeAllMessages: false,
                                        base64EncodingOptions: [])
        #expect(encoded == """
                From: "\(sender.name ?? "")" <\(sender.emailAddress)>\r\n\
                To: "\(receiver.name ?? "")" <\(receiver.emailAddress)>\r\n\
                Date: \(date.formattedForSMTP)\r\n\
                Message-ID: <\(date.timeIntervalSince1970)@\(senderServerName)>\r\n\
                Subject: \(subject)\r\n\
                MIME-Version: 1.0\r\n\
                Content-Type: text/html; charset="UTF-8"\r\n\r\n\
                \(htmlBody)\r\n\
                \r\n.\r\n
                """)
    }

    @Test
    func transferUniversal() async throws {
        let senderServerName = "example.com"
        let sender = Email.Contact(name: "Sender Name", emailAddress: "some.sender@\(senderServerName)")
        let receiver = Email.Contact(name: "Receiver Name", emailAddress: "some.receiver@example.com")
        let subject = "Test Message"
        let plainTextBody = "The contents of this email\nare very simple and just for testing..."
        let htmlBody = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="utf-8" />
            <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
            </head>
            <body>
            <p>This is a test.</p>
            <p>Nothing more but a test.</p>
            </body>
            </html>
            """
        let date = Date(timeIntervalSince1970: 1744193604) // 2025-04-09T10:13:24Z
        let encoded = try encodeRequest(.transferData(date: date,
                                                      email: .init(sender: sender,
                                                                   recipients: [receiver],
                                                                   subject: subject,
                                                                   body: .universal(plain: plainTextBody, html: htmlBody))),
                                        base64EncodeAllMessages: false,
                                        base64EncodingOptions: [])
        let regex = Regex {
            """
            From: "\(sender.name ?? "")" <\(sender.emailAddress)>\r\n\
            To: "\(receiver.name ?? "")" <\(receiver.emailAddress)>\r\n\
            Date: \(date.formattedForSMTP)\r\n\
            Message-ID: <\(date.timeIntervalSince1970)@\(senderServerName)>\r\n\
            Subject: \(subject)\r\n\
            MIME-Version: 1.0\r\n
            """
            #/Content-Type: multipart/alternative; boundary=([A-Za-z0-9]{32})\r\n/#
            "\r\n"
        }
        let match = try #require(try regex.prefixMatch(in: encoded))
        let boundary = String(match.output.1)

        #expect(encoded[match.range.upperBound...] == """
                --\(boundary)\r\n\
                Content-Type: text/plain; charset="UTF-8"\r\n\r\n\
                \(plainTextBody)\r\n\r\n\
                --\(boundary)\r\n\
                Content-Type: text/html; charset="UTF-8"\r\n\r\n\
                \(htmlBody)\r\n\r\n\
                --\(boundary)--\r\n\
                \r\n.\r\n
                """)
    }
}
