import Testing
import Foundation
import NIO
@testable import SwiftSMTP

@Suite
struct SMTPRequestEncoderRawDataTests {
    private func encodeRawData(_ messageData: Data) throws -> String {
        let encoder = SMTPRequestEncoder(base64EncodeAllMessages: false, base64EncodingOptions: [])
        var byteBuffer = ByteBufferAllocator().buffer(capacity: 1024)
        try encoder.encode(data: .transferRawData(messageData), out: &byteBuffer)
        return byteBuffer.readString(length: byteBuffer.readableBytes) ?? ""
    }

    @Test
    func dotStuffingAtFirstLine() async throws {
        let payload = Data(".start\r\n".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "..start\r\n.\r\n")
    }

    @Test
    func dotStuffingMidPayload() async throws {
        let payload = Data("\r\nfoo\r\n.test\r\n".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "\r\nfoo\r\n..test\r\n.\r\n")
    }

    @Test
    func multipleDotLinesAreAllStuffed() async throws {
        let payload = Data(".one\r\n.two\r\n.three\r\n".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "..one\r\n..two\r\n..three\r\n.\r\n")
    }

    @Test
    func nonLeadingDotsAreUntouched() async throws {
        let payload = Data("a.b.c\r\nx.y.z\r\n".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "a.b.c\r\nx.y.z\r\n.\r\n")
    }

    @Test
    func trailingCRLFAddedWhenMissing() async throws {
        let payload = Data("body without terminator".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "body without terminator\r\n.\r\n")
    }

    @Test
    func trailingCRLFNotDoubledWhenPresent() async throws {
        let payload = Data("body with terminator\r\n".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "body with terminator\r\n.\r\n")
    }

    @Test
    func bareLFPassesThroughUnchanged() async throws {
        // Caller may have crafted exact bytes (DKIM, IMAP APPEND parity) — encoder must not canonicalise.
        let payload = Data("line1\nline2\n".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "line1\nline2\n\r\n.\r\n")
    }

    @Test
    func dotAfterBareLFIsNotStuffed() async throws {
        // A '.' is only at "start of line" after a CRLF. Following a bare LF it is mid-line as far as a
        // CRLF-framing receiver is concerned, so doubling it would corrupt the payload (the receiver would
        // not un-stuff it). Stuffing only the true CRLF-led dot is what keeps DKIM-signed bodies intact.
        let payload = Data("foo\n.bar\r\n".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "foo\n.bar\r\n.\r\n")
    }

    @Test
    func dotAfterCRLFIsStuffedEvenAdjacentToBareLF() async throws {
        // Contrast with the bare-LF case: a dot that does follow a CRLF must still be stuffed.
        let payload = Data("foo\n\r\n.bar\r\n".utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == "foo\n\r\n..bar\r\n.\r\n")
    }

    @Test
    func emptyPayloadProducesEmptyMessage() async throws {
        // Empty data → just the dot terminator on its own line; servers are expected to reject but the encoder should not crash.
        let encoded = try encodeRawData(Data())
        #expect(encoded == "\r\n.\r\n")
    }

    @Test
    func rfc2822LikeMessageRoundTrips() async throws {
        // Realistic shape: headers + blank line + body + trailing CRLF. Should pass through bit-identical
        // (no header/body separator munging, no body line rewriting).
        let payload = Data("""
            From: sender@example.com\r\n\
            To: receiver@example.com\r\n\
            Subject: Hello\r\n\
            \r\n\
            Body line 1\r\n\
            Body line 2\r\n
            """.utf8)
        let encoded = try encodeRawData(payload)
        #expect(encoded == String(data: payload, encoding: .utf8)! + ".\r\n")
    }
}
