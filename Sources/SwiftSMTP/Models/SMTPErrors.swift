/// Thrown when the message received from the server was not a well-formed SMTP message.
public struct MalformedSMTPMessageError: Error, CustomStringConvertible {
    public var description: String { "The message from the server was malformed!" }
}

/// Thrown when the server returns an error message.
public struct ServerError: Error, CustomStringConvertible {
    /// The message returned by the server.
    public let serverMessage: String

    public var description: String { "Received an error from the server: \(serverMessage)" }
}
