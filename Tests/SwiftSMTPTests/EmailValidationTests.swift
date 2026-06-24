import Testing
import Foundation
import NIO
import NIOPosix
@testable import SwiftSMTP

extension EmailValidationError: Equatable {
    static func ==(lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.missingRecipients, .missingRecipients): true
        case (.invalidEmailAddress(let lhsAddress), .invalidEmailAddress(let rhsAddress)): lhsAddress == rhsAddress
        case (.missingRecipients, .invalidEmailAddress(_)), (.invalidEmailAddress(_), .missingRecipients): false
        }
    }
}

@Suite
struct EmailValidationTests {
    @Test(arguments: [
        AnyEmail.regular(Email(sender: .init(emailAddress: "test@example.com"),
                               recipients: [],
                               subject: "Irrelevant",
                               body: .plain("Equally irrelevant"))),
        AnyEmail.precomposed(PrecomposedEmail(senderAddress: "test@example.com",
                                              recipientAddresses: [],
                                              message: ByteBuffer()))
    ])
    func emptyRecipients(email: AnyEmail) async throws {
        #expect(throws: EmailValidationError.missingRecipients) { try email.validate() }
    }

    @Test(arguments: [
        (AnyEmail.regular(Email(sender: .init(emailAddress: "test\r\ninvalid@example.com"),
                                recipients: [.init(emailAddress: "valid@example.com")],
                               subject: "Irrelevant",
                               body: .plain("Equally irrelevant"))), "test\r\ninvalid@example.com"),
        (AnyEmail.regular(Email(sender: .init(emailAddress: "valid@example.com"),
                                recipients: [.init(emailAddress: "test\r\ninvalid@example.com")],
                               subject: "Irrelevant",
                               body: .plain("Equally irrelevant"))), "test\r\ninvalid@example.com"),
        (AnyEmail.precomposed(PrecomposedEmail(senderAddress: "test\r\ninvalid@example.com",
                                              recipientAddresses: ["valid@example.com"],
                                              message: ByteBuffer())), "test\r\ninvalid@example.com"),
        (AnyEmail.precomposed(PrecomposedEmail(senderAddress: "valid@example.com",
                                              recipientAddresses: ["test\r\ninvalid@example.com"],
                                              message: ByteBuffer())), "test\r\ninvalid@example.com"),
    ])
    func invalidAddress(email: AnyEmail, expectedAddress: String) async throws {
        #expect(throws: EmailValidationError.invalidEmailAddress(expectedAddress)) { try email.validate() }
    }
}
