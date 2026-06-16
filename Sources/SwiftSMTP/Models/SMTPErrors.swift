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

/// Thrown when a message is scheduled for sending without any recipients.
@DebugDescription
public struct MissingRecipientsError: Error, CustomStringConvertible {
    public var description: String { "At least one recipient is required to send a message." }
}

/// Thrown when an envelope address (used for `MAIL FROM` / `RCPT TO`) contains a carriage return or line
/// feed. Such characters would allow additional SMTP commands to be injected into the session, so they are
/// rejected before any connection is opened.
// Note: no `@DebugDescription` here. The description must escape the embedded CR/LF (otherwise it could forge
// extra log lines), and that macro only allows plain stored-property interpolation in the description.
public struct InvalidEnvelopeAddressError: Error, CustomStringConvertible {
    /// The offending address.
    public let address: String

    // Render the address escaped so the embedded CR/LF cannot forge extra log lines.
    public var description: String { "Envelope address must not contain CR or LF characters: \(String(reflecting: address))" }
}
