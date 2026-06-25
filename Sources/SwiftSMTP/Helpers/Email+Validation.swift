fileprivate import Foundation

// Regex taken from https://emailregex.com
private let emailRegexPattern = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"

private func validateEmailAddress(_ address: String) throws {
    let matches: Bool
    if #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) {
        let emailRegex = try Regex(emailRegexPattern)
        matches = try emailRegex.wholeMatch(in: address) != nil
    } else {
        let emailRegex = try NSRegularExpression(pattern: emailRegexPattern)
        matches = emailRegex.numberOfMatches(in: address, options: .anchored, range: NSRange(address.startIndex..., in: address)) == 1
    }
    if !matches {
        throw EmailValidationError.invalidEmailAddress(address)
    }
}

extension PrecomposedEmail {
    @usableFromInline
    func validate() throws {
        guard !recipientAddresses.isEmpty else { throw EmailValidationError.missingRecipients }
        try validateEmailAddress(senderAddress)
        for recipientAddress in recipientAddresses {
            try validateEmailAddress(recipientAddress)
        }
    }
}

extension Email {
    @usableFromInline
    func validate() throws {
        try validateEmailAddress(sender.emailAddress)
        var hasSeenAddress = false
        for recipientAddress in allRecipients.lazy.map(\.emailAddress) {
            try validateEmailAddress(recipientAddress)
            hasSeenAddress = true
        }
        guard hasSeenAddress else { throw EmailValidationError.missingRecipients }
    }
}
