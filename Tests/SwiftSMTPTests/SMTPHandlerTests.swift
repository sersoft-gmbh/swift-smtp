import Testing
import Foundation
import NIO
@testable import SwiftSMTP

@Suite
struct SMTPHandlerTests {
    private static func describe(_ request: SMTPRequest) -> String {
        switch request {
        case .sayHello: "HELLO"
        case .startTLS: "STARTTLS"
        case .beginAuthentication: "AUTH"
        case .authUser: "AUTH_USER"
        case .authPassword: "AUTH_PASSWORD"
        case .mailFrom(let from): "MAIL_FROM:\(from)"
        case .recipient(let rcpt): "RCPT_TO:\(rcpt)"
        case .data: "DATA"
        case .transferPayload(.newlyComposed(_, _)): "TRANSFER_PAYLOAD_REGULAR"
        case .transferPayload(.precomposed(_)): "TRANSFER_PAYLOAD_PRECOMPOSED"
        case .quit: "QUIT"
        }
    }

    @Test(arguments: [
        (
            AnyEmail.regular(Email(sender: .init(emailAddress: "sender@example.com"),
                                recipients: [.init(emailAddress: "to@example.com")],
                                cc: [.init(emailAddress: "cc@example.com")],
                                bcc: [.init(emailAddress: "bcc@example.com")],
                                subject: "Subject",
                                body: .plain("Body"))),
         [
             "HELLO",
             "MAIL_FROM:sender@example.com",
             "RCPT_TO:to@example.com",
             "RCPT_TO:cc@example.com",
             "RCPT_TO:bcc@example.com",
             "DATA",
             "TRANSFER_PAYLOAD_REGULAR",
             "QUIT",
         ]
        ),
        (
            AnyEmail.precomposed(PrecomposedEmail(senderAddress: "envelope@example.com",
                                               recipientAddresses: ["one@example.com", "two@example.com"],
                                               messageData: Data("From: x\r\n\r\nBody\r\n".utf8))),
            [
                "HELLO",
                "MAIL_FROM:envelope@example.com",
                "RCPT_TO:one@example.com",
                "RCPT_TO:two@example.com",
                "DATA",
                "TRANSFER_PAYLOAD_PRECOMPOSED",
                "QUIT",
            ]
        )
    ])
    func generatedCommands(email: AnyEmail, expectedCommands: Array<String>) throws {
        /// Feeds the handler successful server responses, one channel read at a time, and
        /// collects the command it emits in reaction to each. Plain server, no credentials, so the flow is
        /// HELLO → MAIL FROM → RCPT TO* → DATA → transfer → QUIT.
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: Void.self)
        let handler = SMTPHandler(configuration: .init(server: .init(hostname: "smtp.example.invalid")),
                                  email: email,
                                  allDonePromise: promise)
        try channel.pipeline.syncOperations.addHandler(handler)

        var emitted = Array<String>()
        for _ in expectedCommands {
            try channel.writeInbound(SMTPResponse.success((250, "OK")))
            while let command = try channel.readOutbound(as: SMTPRequest.self) {
                emitted.append(Self.describe(command))
            }
        }
        promise.succeed(())
        _ = try channel.finish()
        #expect(emitted == expectedCommands)
    }
}
