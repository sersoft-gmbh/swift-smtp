/// Represents a configuration for sending emails.
public struct Configuration: Hashable {
    /// The server to connect to.
    public var server: Server
    /// The credentials to use for connecting. `nil` if no authentication should be used.
    public var credentials: Credentials?

    /// Creates a new configuration with the given parameters.
    /// - Parameters:
    ///   - server: The server to connect to.
    ///   - credentials: The credentials to use for connecting. `nil` if no authentication should be used.
    public init(server: Server, credentials: Credentials? = nil) {
        self.server = server
        self.credentials = credentials
    }
}

extension Configuration {
    /// Represents a server configuration.
    public struct Server: Hashable {
        /// The hostname of the server. Can be a DNS name or an IP.
        public var hostname: String
        /// The port to use for connecting.
        public var port: Int
        /// The encryption setting to use for the connection.
        public var encryption: Encryption

        /// Creates a new server configuration with the given parameters.
        /// - Parameters:
        ///   - hostname: The hostname of the server. Can be a DNS name or an IP.
        ///   - port: The port to use for connecting.
        ///   - encryption: The encryption setting to use for the connection. Defaults to `.plain`.
        public init(hostname: String, port: Int, encryption: Encryption = .plain) {
            self.hostname = hostname
            self.port = port
            self.encryption = encryption
        }
    }

    /// Represents a set of credentials.
    public struct Credentials: Hashable {
        /// The username to use for authentication.
        public var username: String
        /// The password to use for authentication.
        public var password: String

        /// Creates a new set of credentials.
        /// - Parameters:
        ///   - username: The username to use for authentication.
        ///   - password: The password to use for authentication.
        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }
}

extension Configuration.Server {
    /// Represents an encryption setting.
    /// - plain: No encryption is used.
    /// - ssl: Normal SSL (TLS) encryption is used.
    /// - startTLS: A TLS encryption is opened after first connecting with a plain connection.
    ///             Depending on the `StartTLSMode`, the connection might continue without encryption.
    public enum Encryption: Hashable {
        case plain, ssl
        case startTLS(StartTLSMode)
    }
}

extension Configuration.Server.Encryption {
    /// Represents a StartTLS mode.
    /// - always: After sending the StartTLS command, a TLS encryption *has to* be opened. The connection will fail if the server does not support it.
    /// - ifAvailable: The connection will continue without encryption after the StartTLS command if the server does not support encryption.
    public enum StartTLSMode: Hashable {
        case always, ifAvailable
    }
}
