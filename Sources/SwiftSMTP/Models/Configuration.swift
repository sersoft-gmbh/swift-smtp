public import struct NIO.TimeAmount

/// Represents a configuration for sending emails.
public struct Configuration: Sendable, Hashable {
    /// The server to connect to.
    public var server: Server
    /// The connection time out for connections to the server.
    public var connectionTimeOut: TimeAmount
    /// The credentials to use for connecting. `nil` if no authentication should be used.
    public var credentials: Credentials?
    /// The feature flags of this configuration.
    public var featureFlags: FeatureFlags

    /// Creates a new configuration with the given parameters.
    /// - Parameters:
    ///   - server: The server to connect to.
    ///   - connectionTimeOut: The time out to use for connections to the server.
    ///   - credentials: The credentials to use for connecting. `nil` if no authentication should be used.
    ///   - featureFlags: The feature flags to  use. Defaults to an empty list.
    public init(server: Server,
                connectionTimeOut: TimeAmount = .seconds(60),
                credentials: Credentials? = nil,
                featureFlags: FeatureFlags = []) {
        self.server = server
        self.connectionTimeOut = connectionTimeOut
        self.credentials = credentials
        self.featureFlags = featureFlags
    }
}

extension Configuration {
    /// Represents a server configuration.
    public struct Server: Sendable, Hashable {
        /// The hostname of the server. Can be a DNS name or an IP.
        public var hostname: String
        /// The port to use for connecting.
        public var port: Int
        /// The encryption setting to use for the connection.
        public var encryption: Encryption

        /// Creates a new server configuration with the given parameters.
        /// - Parameters:
        ///   - hostname: The hostname of the server. Can be a DNS name or an IP.
        ///   - port: The port to use for connecting. Defaults to nil in which case the default port for `encryption` will be used.
        ///   - encryption: The encryption setting to use for the connection. Defaults to ``Configuration/Encryption/plain``.
        public init(hostname: String, port: Int? = nil, encryption: Encryption = .plain) {
            self.hostname = hostname
            self.port = port ?? encryption.defaultPort
            self.encryption = encryption
        }
    }

    /// Represents a set of credentials.
    public struct Credentials: Sendable, Hashable {
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

    /// Represents feature flags of the server.
    @frozen
    public struct FeatureFlags: OptionSet, Hashable, Sendable {
        public typealias RawValue = UInt

        public let rawValue: RawValue

        @inlinable
        public init(rawValue: RawValue) {
            self.rawValue = rawValue
        }
    }
}

extension Configuration.Server {
    /// Represents an encryption setting.
    public enum Encryption: Sendable, Hashable {
        /// No encryption is used.
        case plain
        /// Normal SSL (TLS) encryption is used.
        case ssl
        /// A TLS encryption is opened after first connecting with a plain connection.
        /// Depending on the ``StartTLSMode``, the connection might continue without encryption.
        case startTLS(StartTLSMode)

        /// The default port for this encryption:
        /// - ``plain``: `25`
        /// - ``ssl``: `465`
        /// - ``startTLS(_:)``: `587`
        public var defaultPort: Int {
            switch self {
            case .plain: return 25
            case .ssl: return 465
            case .startTLS(_): return 587
            }
        }
    }
}

extension Configuration.Server.Encryption {
    /// Represents a StartTLS mode.
    public enum StartTLSMode: Sendable, Hashable {
        /// After sending the StartTLS command, a TLS encryption *has to* be opened. The connection will fail if the server does not support it.
        case always
        /// The connection will continue without encryption after the StartTLS command if the server does not support encryption.
        case ifAvailable
    }
}

extension Configuration.FeatureFlags {
    /// Whether ESMTP should be used (e.g. send `EHLO` instead of `HELO`).
    public static let useESMTP = Configuration.FeatureFlags(rawValue: 1 << 0)

    /// Whether all messages sent to the server should be using base64 (transfer) encoding. Use further options to customize the line length.
    public static let base64EncodeAllMessages = Configuration.FeatureFlags(rawValue: 1 << 9)
    /// Whether the base64 line length should be limited to 64 characters.
    public static let maximumBase64LineLength64 = Configuration.FeatureFlags(rawValue: 1 << 10)
    /// Whether the base64 line length should be limited to 76 characters.
    public static let maximumBase64LineLength76 = Configuration.FeatureFlags(rawValue: 1 << 11)
}
