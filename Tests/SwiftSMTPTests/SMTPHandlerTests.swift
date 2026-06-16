import Testing
import Foundation
import NIO
@testable import SwiftSMTP

@Suite
struct SMTPHandlerTests {
    private func makeEmail(recipients: Array<String>,
                           cc: Array<String> = [],
                           bcc: Array<String> = []) -> Email {
        Email(sender: .init(emailAddress: "sender@example.com"),
              recipients: recipients.map { .init(emailAddress: $0) },
              cc: cc.map { .init(emailAddress: $0) },
              bcc: bcc.map { .init(emailAddress: $0) },
              subject: "Subject",
              body: .plain("Body"))
    }

    /// Feeds the handler `responseCount` successful server responses, one channel read at a time, and
    /// collects the command it emits in reaction to each. Plain server, no credentials, so the flow is
    /// HELLO → MAIL FROM → RCPT TO* → DATA → transfer → QUIT.
    private func commands(for sendJob: SendJob, responseCount: Int) throws -> Array<String> {
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: Void.self)
        let handler = SMTPHandler(configuration: .init(server: .init(hostname: "smtp.example.invalid")),
                                  sendJob: sendJob,
                                  allDonePromise: promise)
        try channel.pipeline.syncOperations.addHandler(handler)

        var emitted = Array<String>()
        for _ in 0..<responseCount {
            try channel.writeInbound(SMTPResponse.success((250, "OK")))
            while let command = try channel.readOutbound(as: SMTPRequest.self) {
                emitted.append(Self.describe(command))
            }
        }
        promise.succeed(())
        _ = try? channel.finish()
        return emitted
    }

    private static func describe(_ request: SMTPRequest) -> String {
        switch request {
        case .sayHello: "HELLO"
        case .startTLS: "STARTTLS"
        case .beginAuthentication: "AUTH"
        case .authUser: "AUTH_USER"
        case .authPassword: "AUTH_PASSWORD"
        case .mailFrom(let from): "MAIL FROM:\(from)"
        case .recipient(let rcpt): "RCPT TO:\(rcpt)"
        case .data: "DATA"
        case .transferData: "TRANSFER_DATA"
        case .transferRawData: "TRANSFER_RAW_DATA"
        case .quit: "QUIT"
        }
    }

    @Test
    func emailPathUsesSenderAndAllRecipientsForEnvelope() throws {
        // Guards the SendJob refactor: the envelope must come from the sender plus the full recipient set
        // (to + cc + bcc), and the data phase must use the email transfer branch.
        let email = makeEmail(recipients: ["to@example.com"],
                              cc: ["cc@example.com"],
                              bcc: ["bcc@example.com"])
        let emitted = try commands(for: SendJob(email: email), responseCount: 8)
        #expect(emitted == [
            "HELLO",
            "MAIL FROM:sender@example.com",
            "RCPT TO:to@example.com",
            "RCPT TO:cc@example.com",
            "RCPT TO:bcc@example.com",
            "DATA",
            "TRANSFER_DATA",
            "QUIT",
        ])
    }

    @Test
    func rawDataPathUsesGivenEnvelopeAndRawTransfer() throws {
        // The raw-bytes path must drive the same envelope sequence but take the transferRawData branch.
        let sendJob = SendJob(sender: "envelope@example.com",
                              recipients: ["one@example.com", "two@example.com"],
                              payload: .rawData(Data("From: x\r\n\r\nBody\r\n".utf8)))
        let emitted = try commands(for: sendJob, responseCount: 7)
        #expect(emitted == [
            "HELLO",
            "MAIL FROM:envelope@example.com",
            "RCPT TO:one@example.com",
            "RCPT TO:two@example.com",
            "DATA",
            "TRANSFER_RAW_DATA",
            "QUIT",
        ])
    }
}
