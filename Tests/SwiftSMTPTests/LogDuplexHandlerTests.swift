#if swift(>=6.0)
import Testing
import Foundation
import NIO
import NIOConcurrencyHelpers
@testable import SwiftSMTP

@Suite
struct LogDuplexHandlerTests {
    private final class TestLogger: SMTPLogger {
        private let messages = NIOLockedValueBox(Array<String>())

        var currentMessages: Array<String> { messages.withLockedValue(\.self) }

        func logSMTPMessage(_ message: @autoclosure () -> String) {
            messages.withLockedValue { $0.append(message()) }
        }
    }


    @Test
    func inbound() async throws {
        let handler = LogDuplexHandler(logger: TestLogger())
        let channel = EmbeddedChannel()
        try await channel.pipeline.addHandler(handler)
        try channel.writeInbound(ByteBuffer(string: "Inbound Message"))
        channel.flush()
        try await channel.close()

        #expect(handler.logger.currentMessages == ["☁️ Inbound Message"])
    }

    @Test
    func outbound() async throws {
        let handler = LogDuplexHandler(logger: TestLogger())
        let channel = EmbeddedChannel()
        try await channel.pipeline.addHandler(handler)
        try channel.writeOutbound(ByteBuffer(string: "Outbound Message"))
        channel.flush()
        try await channel.close()

        #expect(handler.logger.currentMessages == ["💻 Outbound Message"])
    }

    @Test
    func bidirectional() async throws {
        let handler = LogDuplexHandler(logger: TestLogger())
        let channel = EmbeddedChannel()
        try await channel.pipeline.addHandler(handler)
        try channel.writeInbound(ByteBuffer(string: "Inbound Message"))
        try channel.writeOutbound(ByteBuffer(string: "Outbound Message"))
        channel.flush()
        try await channel.close()

        #expect(handler.logger.currentMessages == [
            "☁️ Inbound Message",
            "💻 Outbound Message",
        ])
    }
}
#endif
