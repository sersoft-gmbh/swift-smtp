import Foundation
fileprivate import struct NIO.TimeAmount

// ProcessInfo.processInfo.environment copies all environment variables each time it is called (at least in swift-foundation)
// We thus do it as little as possible by storing the copy in this struct and passing it along.
fileprivate struct EnvironmentVariables: Sendable {
    public static var current: Self {
        .init(vars: ProcessInfo.processInfo.environment)
    }

    private let vars: Dictionary<String, String>

    func value(forKey key: String) -> String? {
        if let filePath = vars[key + "_FILE"] {
            do {
                return try String(contentsOfFile: filePath, encoding: .utf8)
            } catch {
    #if DEBUG
                print("[SWIFT SMTP]: Could not read file at \(filePath) (via environment variable '\(key)_FILE'): \(error)")
    #endif
            }
        }
        return vars[key]
    }
}

extension Configuration.Server.Encryption {
    fileprivate static func fromEnvironment(_ env: EnvironmentVariables) -> Configuration.Server.Encryption? {
        switch env.value(forKey: "SMTP_ENCRYPTION")?.lowercased() {
        case "plain": .plain
        case "ssl": .ssl
        case "starttls": .startTLS(.ifAvailable)
        case "starttls_always": .startTLS(.always)
        default: nil
        }
    }

    /// Attempts to create an encryption from the environment variable `SMTP_ENCRYPTION` (or the file pointed to via `SMPT_ENCRYPTION_FILE`).
    /// Possible values (case insensitive):
    /// - "plain": ``Configuration/Server/Encryption/plain``
    /// - "ssl": ``Configuration/Server/Encryption/ssl``
    /// - "starttls": ``Configuration/Server/Encryption/startTLS(_:)`` with ``Configuration/Server/Encryption/StartTLSMode/ifAvailable``
    /// - "starttls_always": ``Configuration/Server/Encryption/startTLS(_:)`` with ``Configuration/Server/Encryption/StartTLSMode/always``
    /// If the environment variable is not set or is an unsupported value, `nil` is returned.
    public static func fromEnvironment() -> Configuration.Server.Encryption? {
        fromEnvironment(.current)
    }
}

extension Configuration.Server {
    fileprivate static func fromEnvironment(_ env: EnvironmentVariables) -> Configuration.Server {
        let hostname = env.value(forKey: "SMTP_HOST") ?? "127.0.0.1"
        let port = env.value(forKey: "SMTP_PORT").flatMap(Int.init)
        if let encryption = Encryption.fromEnvironment(env) {
            return self.init(hostname: hostname, port: port, encryption: encryption)
        } else {
            return self.init(hostname: hostname, port: port)
        }
    }

    /// Creates a server from environment variables (or defaults).
    /// The following environment variables are read:
    /// - `SMTP_HOST`: The hostname to use or `127.0.0.1` if none is set.
    /// - `SMTP_PORT`: The port to use. The encryption's default will be used if not set or not a valid integer.
    /// Both variables can also be specified via a file pointed to by using the variable above with the `_FILE` suffix.
    /// The encryption will also be read from the environment. If none is set, the default defined in ``Configuration/Server/init(hostname:port:encryption:)`` will be used.
    /// - SeeAlso: ``Encryption/fromEnvironment()``
    /// - SeeAlso: ``Configuration/Server/init(hostname:port:encryption:)``
    public static func fromEnvironment() -> Configuration.Server {
        fromEnvironment(.current)
    }
}

extension Configuration.Credentials {
    fileprivate static func fromEnvironment(_ env: EnvironmentVariables) -> Configuration.Credentials? {
        guard let username = env.value(forKey: "SMTP_USERNAME"),
              let password = env.value(forKey: "SMTP_PASSWORD")
        else { return nil }
        return self.init(username: username, password: password)
    }

    /// Creates a credentials config from environment variables (if set).
    /// The following environment variables are read:
    /// - `SMTP_USERNAME`: The username to use.
    /// - `SMTP_PASSWORD`: The password to use.
    /// Both must be set or `nil` will be returned.
    /// Both variables can also be specified via a file pointed to by using the variable above with the `_FILE` suffix.
    public static func fromEnvironment() -> Configuration.Credentials? {
        fromEnvironment(.current)
    }
}

extension Configuration.FeatureFlags {
    fileprivate static func fromEnvironment(_ env: EnvironmentVariables) -> Configuration.FeatureFlags {
        var flags: Configuration.FeatureFlags = []
        if env.value(forKey: "SMTP_USE_ESMTP") == "1" {
            flags.insert(.useESMTP)
        }
        if env.value(forKey: "SMTP_ALL_BASE64") == "1" {
            flags.insert(.base64EncodeAllMessages)
        }
        if env.value(forKey: "SMTP_MAX_BASE64_LINE_64") == "1" {
            flags.insert(.maximumBase64LineLength64)
        }
        if env.value(forKey: "SMTP_MAX_BASE64_LINE_76") == "1" {
            flags.insert(.maximumBase64LineLength76)
        }
        return flags
    }

    /// Creates the feature flags from environment variables.
    /// The following environment variables are used to set the corresponding feature flags (env var = 1 will set the flag):
    /// - `SMTP_USE_ESMTP`: Controls the ``Configuration/FeatureFlags/useESMTP`` flag.
    /// - `SMTP_ALL_BASE64`: Controls the ``Configuration/FeatureFlags/base64EncodeAllMessages`` flag.
    /// - `SMTP_MAX_BASE64_LINE_64`: Controls the ``Configuration/FeatureFlags/maximumBase64LineLength64`` flag.
    /// - `SMTP_MAX_BASE64_LINE_76`: Controls the ``Configuration/FeatureFlags/maximumBase64LineLength76`` flag.
    /// All variables can also be specified via a file pointed to by using the variable above with the `_FILE` suffix.
    public static func fromEnvironment() -> Configuration.FeatureFlags {
        fromEnvironment(.current)
    }
}

extension Configuration {
    fileprivate static func fromEnvironment(_ env: EnvironmentVariables) -> Configuration {
        if let timeOutSeconds = env.value(forKey: "SMTP_TIMEOUT").flatMap(Int64.init) {
            return self.init(server: .fromEnvironment(env),
                             connectionTimeOut: .seconds(timeOutSeconds),
                             credentials: .fromEnvironment(env),
                             featureFlags: .fromEnvironment(env))
        } else {
            return self.init(server: .fromEnvironment(env),
                             credentials: .fromEnvironment(env),
                             featureFlags: .fromEnvironment(env))
        }
    }

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
    /// All variables can also be specified via a file pointed to by using the variable above with the `_FILE` suffix.
    /// - SeeAlso: ``Configuration/Server/fromEnvironment()``
    /// - SeeAlso: ``Configuration/Credentials/fromEnvironment()``
    /// - SeeAlso: ``Configuration/FeatureFlags/fromEnvironment()``
    /// - SeeAlso: ``Configuration/init(server:connectionTimeOut:credentials:featureFlags:)``
    public static func fromEnvironment() -> Configuration {
        fromEnvironment(.current)
    }
}
