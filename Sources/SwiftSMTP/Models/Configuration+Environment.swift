#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin.C
#elseif os(Windows)
import ucrt
#else
#error("Unsupported platform (getenv)! If you want to add support for this platform, please support a PR which adds the neccessary import for getenv for this platform!")
#endif
fileprivate import struct NIO.TimeAmount

fileprivate func getEnvValue(forKey key: String) -> String? {
#if compiler(>=6.2)
    unsafe getenv(key).map { unsafe String(cString: $0) }
#else
    getenv(key).map { String(cString: $0) }
#endif
}

extension Configuration.Server.Encryption {
    /// Attempts to create an encryption from the environment variable `SMTP_ENCRYPTION`.
    /// Possible values (case insensitive):
    /// - "plain": ``Configuration/Server/Encryption/plain``
    /// - "ssl": ``Configuration/Server/Encryption/ssl``
    /// - "starttls": ``Configuration/Server/Encryption/startTLS(_:)`` with ``Configuration/Server/Encryption/StartTLSMode/ifAvailable``
    /// - "starttls_always": ``Configuration/Server/Encryption/startTLS(_:)`` with ``Configuration/Server/Encryption/StartTLSMode/always``
    /// If the environment variable is not set or is an unsupported value, `nil` is returned.
    public static func fromEnvironment() -> Configuration.Server.Encryption? {
        switch getEnvValue(forKey: "SMTP_ENCRYPTION")?.lowercased() {
        case "plain": .plain
        case "ssl": .ssl
        case "starttls": .startTLS(.ifAvailable)
        case "starttls_always": .startTLS(.always)
        default: nil
        }
    }
}

extension Configuration.Server {
    /// Creates a server from environment variables (or defaults).
    /// The following environment variables are read:
    /// - `SMTP_HOST`: The hostname to use or `127.0.0.1` if none is set.
    /// - `SMTP_PORT`: The port to use. The encryption's default will be used if not set or not a valid integer.
    /// The encryption will also be read from the environment. If none is set, the default defined in ``Configuration/Server/init(hostname:port:encryption:)`` will be used.
    /// - SeeAlso: ``Encryption/fromEnvironment()``
    /// - SeeAlso: ``Configuration/Server/init(hostname:port:encryption:)``
    public static func fromEnvironment() -> Configuration.Server {
        let hostname = getEnvValue(forKey: "SMTP_HOST") ?? "127.0.0.1"
        let port = getEnvValue(forKey: "SMTP_PORT").flatMap(Int.init)
        if let encryption = Encryption.fromEnvironment() {
            return self.init(hostname: hostname, port: port, encryption: encryption)
        } else {
            return self.init(hostname: hostname, port: port)
        }
    }
}

extension Configuration.Credentials {
    /// Creates a credentials config from environment variables (if set).
    /// The following environment variables are read:
    /// - `SMTP_USERNAME`: The username to use.
    /// - `SMTP_PASSWORD`: The password to use.
    /// Both must be set or `nil` will be returned.
    public static func fromEnvironment() -> Configuration.Credentials? {
        guard let username = getEnvValue(forKey: "SMTP_USERNAME"),
              let password = getEnvValue(forKey: "SMTP_PASSWORD")
        else { return nil }
        return self.init(username: username, password: password)
    }
}

extension Configuration.FeatureFlags {
    /// Creates the feature flags from environment variables.
    /// The following environment variables are used to set the corresponding feature flags (env var = 1 will set the flag):
    /// - `SMTP_USE_ESMTP`: Controls the ``Configuration/FeatureFlags/useESMTP`` flag.
    /// - `SMTP_ALL_BASE64`: Controls the ``Configuration/FeatureFlags/base64EncodeAllMessages`` flag.
    /// - `SMTP_MAX_BASE64_LINE_64`: Controls the ``Configuration/FeatureFlags/maximumBase64LineLength64`` flag.
    /// - `SMTP_MAX_BASE64_LINE_76`: Controls the ``Configuration/FeatureFlags/maximumBase64LineLength76`` flag.
    public static func fromEnvironment() -> Configuration.FeatureFlags {
        var flags: Configuration.FeatureFlags = []
        if getEnvValue(forKey: "SMTP_USE_ESMTP") == "1" {
            flags.insert(.useESMTP)
        }
        if getEnvValue(forKey: "SMTP_ALL_BASE64") == "1" {
            flags.insert(.base64EncodeAllMessages)
        }
        if getEnvValue(forKey: "SMTP_MAX_BASE64_LINE_64") == "1" {
            flags.insert(.maximumBase64LineLength64)
        }
        if getEnvValue(forKey: "SMTP_MAX_BASE64_LINE_76") == "1" {
            flags.insert(.maximumBase64LineLength76)
        }
        return flags
    }
}

extension Configuration {
    /// Creates a configuration from environment variables (or defaults).
    /// The following environment variables are read:
    /// - `SMTP_HOST`: The hostname to use or `127.0.0.1` if none is set.
    /// - `SMTP_PORT`: The port to use. The encryption's default will be used if not set or not a valid integer.
    /// - `SMTP_ENCRYPTION`: The encyrption to use.
    /// - `SMTP_TIMEOUT`: The connection time out in seconds. If not set or not a valid 64-bit integer, the default defined in ``Configuration/init(server:connectionTimeOut:credentials:)`` will be used.
    /// - `SMTP_USERNAME`: The username to use.
    /// - `SMTP_PASSWORD`: The password to use.
    /// - `SMTP_USE_ESMTP`: If set to 1, this will add ``Configuration/FeatureFlags/useESMTP`` to ``Configuration/featureFlags``.
    /// - `SMTP_ALL_BASE64`: If set to 1, this will add ``Configuration/FeatureFlags/base64EncodeAllMessages`` to ``Configuration/featureFlags``.
    /// - `SMTP_MAX_BASE64_LINE_64`: If set to 1, this will add ``Configuration/FeatureFlags/maximumBase64LineLength64`` to ``Configuration/featureFlags``.
    /// - `SMTP_MAX_BASE64_LINE_76`: If set to 1, this will add ``Configuration/FeatureFlags/maximumBase64LineLength76`` to ``Configuration/featureFlags``.
    ///
    /// - SeeAlso: ``Configuration/Server/fromEnvironment()``
    /// - SeeAlso: ``Configuration/Credentials/fromEnvironment()``
    /// - SeeAlso: ``Configuration/FeatureFlags/fromEnvironment()``
    /// - SeeAlso: ``Configuration/init(server:connectionTimeOut:credentials:featureFlags:)``
    public static func fromEnvironment() -> Configuration {
        if let timeOutSeconds = getEnvValue(forKey: "SMTP_TIMEOUT").flatMap(Int64.init) {
            return self.init(server: .fromEnvironment(),
                             connectionTimeOut: .seconds(timeOutSeconds),
                             credentials: .fromEnvironment(),
                             featureFlags: .fromEnvironment())
        } else {
            return self.init(server: .fromEnvironment(),
                             credentials: .fromEnvironment(),
                             featureFlags: .fromEnvironment())
        }
    }
}
