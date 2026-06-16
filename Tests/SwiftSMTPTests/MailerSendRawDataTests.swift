import Testing
import Foundation
import NIO
import NIOPosix
@testable import SwiftSMTP

@Suite
struct MailerSendRawDataTests {
    @Test
    func emptyRecipientsFutureFailsImmediately() async throws {
        // Empty `to` must fail with MissingRecipientsError without opening a connection.
        // The async overload delegates to this future via .get(), so this covers both surfaces.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let mailer = Mailer(
            group: group,
            configuration: .init(server: .init(hostname: "smtp.example.invalid"))
        )

        let future: EventLoopFuture<Void> = mailer.send(Data(), from: "sender@example.com", to: [])
        await #expect(throws: MissingRecipientsError.self) {
            try await future.get()
        }

        try await group.shutdownGracefully()
    }

    @Test(arguments: [
        // sender carrying an injected RCPT TO command
        ("a@b.com>\r\nRCPT TO:<victim@evil.com", ["c@d.com"]),
        // recipient carrying an injected command
        ("a@b.com", ["c@d.com>\r\nDATA\r\ninjected"]),
        // bare LF is enough to break the line as well
        ("a@b.com", ["c@d.com\nRCPT TO:<x@y.com"]),
    ] as [(String, [String])])
    func crOrLFInEnvelopeIsRejected(from: String, to: [String]) async throws {
        // A CR or LF in an envelope address would let the caller inject extra SMTP commands. These must be
        // rejected before any connection is opened.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let mailer = Mailer(
            group: group,
            configuration: .init(server: .init(hostname: "smtp.example.invalid"))
        )

        let future: EventLoopFuture<Void> = mailer.send(Data("body\r\n".utf8), from: from, to: to)
        await #expect(throws: InvalidEnvelopeAddressError.self) {
            try await future.get()
        }

        try await group.shutdownGracefully()
    }
}
