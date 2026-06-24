/// Thrown when the message received from the server was not a well-formed SMTP message.
@DebugDescription
public struct MalformedSMTPMessageError: Error, CustomStringConvertible {
    public var description: String { "The message from the server was malformed!" }
}

/// Thrown when the server returns an error message.
@DebugDescription
public struct ServerError: Error, CustomStringConvertible {
    /// The message returned by the server.
    public let serverMessage: String

    public var description: String { "Received an error from the server: \(serverMessage)" }
}

/// Thrown when an email fails validation.
public enum EmailValidationError: Error, CustomStringConvertible {
    case missingRecipients
    case invalidEmailAddress(String)

    public var description: String {
        switch self {
        case .missingRecipients: "At least one recipient is required to send a message."
        case .invalidEmailAddress(let emailAddress):
            // Render the address escaped so the embedded CR/LF cannot forge extra log lines.
            "Email address contains invalid characters: \(String(reflecting: emailAddress))"
        }
    }
}
