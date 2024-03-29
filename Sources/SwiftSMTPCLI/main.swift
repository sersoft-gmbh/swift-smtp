import Foundation
import NIO
import SwiftSMTP

let config = Configuration(server: .init(hostname: "mail.server.com", 
                                         port: 587,
                                         encryption: .startTLS(.ifAvailable)),
                           connectionTimeOut: .seconds(5),
                           credentials: .init(username: "user",
                                              password: "password"),
                           featureFlags: [.base64EncodeAllMessages, .maximumBase64LineLength64])

let plainText = """
Hi there,

this is a test mail from SwiftSMTP CLI.

Have a nice day!
"""
let htmlText = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no" />
</head>
<body>
<p>Hi there,</p>
<p>this is a test mail from SwiftSMTP CLI.</p>
<p>Have a nice day!</p>
</body>
</html>
"""
let email = Email(sender: .init(name: "SwiftSMTP CLI", emailAddress: "swiftsmtp@server.com"),
                  replyTo: nil,
                  recipients: [
                    .init(name: "Test Recipient", emailAddress: "tester@server.com"),
                  ],
                  cc: [],
                  bcc: [],
                  subject: "Testing SwiftSMTP from CLI",
                  body: .universal(plain: plainText, html: htmlText),
                  attachments: [
                    .init(name: "Test.txt",
                          contentType: #"text/plain; charset="UTF-8""#,
                          data: Data("This is simple text file\nwith two lines...".utf8))
                  ])

let evg = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
let mailer = Mailer(group: evg, configuration: config, transmissionLogger: PrintSMTPLogger())

func _send(_ email: Email) async throws {
    try await mailer.send(email)
}

do {
    print("Sending mail...")
    try await _send(email)
    print("Successfully sent mail!")
} catch {
    print("Failed sending: \(error)")
}
do {
    try await evg.shutdownGracefully()
} catch {
    print("Failed shutdown: \(error)")
}
