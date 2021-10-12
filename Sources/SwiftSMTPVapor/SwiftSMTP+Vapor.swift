import NIO
import Vapor
@_exported import SwiftSMTP

/// Represents the source for the event loop group used by the Mailer.
public enum SwiftSMTPEventLoopGroupSource {
    /// Use the application's ELG.
    case application
    /// Provide a custom ELG per Mailer.
    case custom(() -> EventLoopGroup)

    /// Uses a custom source by creating a new `MultiThreadedEventLoopGroup` with the given number of threads.
    /// - Parameter numberOfThreads: The number of threads for the new ELG. Defaults to half the number of system cores.
    public static func createNew(numberOfThreads: Int = max(System.coreCount / 2, 1)) -> SwiftSMTPEventLoopGroupSource {
        .custom { MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads) }
    }
}

/// Represents the maximum connections configuration per Mailer.
public enum SwiftSMTPMaxConnectionsConfiguration: ExpressibleByIntegerLiteral, ExpressibleByNilLiteral {
    /// Uses the default specified by `Mailer`.
    case useDefault
    /// Explicitly sets the default to the given value.
    case custom(maxConnections: Int?)

    /// inherited
    public init(integerLiteral value: IntegerLiteralType) {
        self = .custom(maxConnections: value)
    }

    /// inherited
    public init(nilLiteral: ()) {
        self = .custom(maxConnections: nil)
    }
}

@usableFromInline
struct SwiftSMTPVaporConfig {
    @usableFromInline
    let eventLoopGroupSource: SwiftSMTPEventLoopGroupSource
    @usableFromInline
    let configuration: Configuration
    @usableFromInline
    let maxConnectionsConfig: SwiftSMTPMaxConnectionsConfiguration
    @usableFromInline
    let logTransmissions: Bool

    @usableFromInline
    func createNewMailer(with application: Application) -> Mailer {
        let eventLoopGroup: EventLoopGroup
        switch eventLoopGroupSource {
        case .application: eventLoopGroup = application.eventLoopGroup
        case .custom(let creator): eventLoopGroup = creator()
        }
        let logger = logTransmissions ? Logger(label: "de.sersoft.swiftsmtp") : nil
        if case .custom(let maxConnections) = maxConnectionsConfig {
            return Mailer(group: eventLoopGroup,
                          configuration: configuration,
                          maxConnections: maxConnections,
                          transmissionLogger: logger)
        } else {
            return Mailer(group: eventLoopGroup,
                          configuration: configuration,
                          transmissionLogger: logger)
        }
    }

    init(eventLoopGroupSource: SwiftSMTPEventLoopGroupSource,
         configuration: Configuration,
         maxConnectionsConfig: SwiftSMTPMaxConnectionsConfiguration,
         logTransmissions: Bool) {
        self.eventLoopGroupSource = eventLoopGroupSource
        self.configuration = configuration
        self.maxConnectionsConfig = maxConnectionsConfig
        self.logTransmissions = logTransmissions
    }
}

/// Initializes the SwiftSMTP configuration on the application on boot.
/// You can add it to your application in `configure` by using `app.lifecycle.use(SMTPInitializer(...))`.
public struct SMTPInitializer: LifecycleHandler {
    @usableFromInline
    let config: SwiftSMTPVaporConfig

    /// The source for the event loop group for the Mailer.
    @inlinable
    public var eventLoopGroupSource: SwiftSMTPEventLoopGroupSource { config.eventLoopGroupSource }

    /// The configuration this initializer configures the application with.
    @inlinable
    public var configuration: Configuration { config.configuration }

    /// The maximum connections configuration per mailer.
    @inlinable
    public var maxConnectionsConfiguration: SwiftSMTPMaxConnectionsConfiguration { config.maxConnectionsConfig }

    /// Wether or not to log transissions.
    @inlinable
    public var logTransmissions: Bool { config.logTransmissions }


    /// Creates a new initializer for a given configuration.
    /// - Parameter configuration: The configuration to use for the application's mailers.
    /// - Parameter eventLoopGroupSource: The source for the event loop group.
    /// - Parameter maxConnectionsConfiguration: The maximum connections configuration per mailer. Defaults to `.useDefault`.
    /// - Parameter logTransmissions: Whether or not to log transmissions with a `Logger`. Defaults to `false`.
    public init(configuration: Configuration,
                eventLoopGroupSource: SwiftSMTPEventLoopGroupSource = .application,
                maxConnectionsConfiguration: SwiftSMTPMaxConnectionsConfiguration = .useDefault,
                logTransmissions: Bool = false) {
        config = .init(eventLoopGroupSource: eventLoopGroupSource,
                       configuration: configuration,
                       maxConnectionsConfig: maxConnectionsConfiguration,
                       logTransmissions: logTransmissions)
    }

    /// inherited
    public func willBoot(_ application: Application) throws {
        application.swiftSMTP.initialize(with: config, registerShutdownHandler: false)
    }

    /// inherited
    public func shutdown(_ application: Application) {
        guard case .custom(_) = eventLoopGroupSource else { return }
        SharedMailerGroupShutdownHandler.shutdownSharedMailerGroup(of: application)
    }
}

struct SharedMailerGroupShutdownHandler: LifecycleHandler {
    static func shutdownSharedMailerGroup(of application: Application) {
        guard let sharedMailer = application.storage[Application.SwiftSMTP.SharedMailerKeys.Storage.self] else { return }
        do {
            try sharedMailer.group.syncShutdownGracefully()
        } catch {
            application.logger.error("[swift-smtp]: Failed to shutdown custom event loop group of shared mailer!")
            application.logger.report(error: error)
        }
    }

    func shutdown(_ application: Application) {
        Self.shutdownSharedMailerGroup(of: application)
    }
}

extension Logger: SMTPLogger {
    /// inherited
    public func logSMTPMessage(_ message: @autoclosure () -> String) {
        log(level: .info, "\(message())")
    }
}

extension Application {
    /// Represents the application's SwiftSMTP configuration.
    public struct SwiftSMTP {
        enum ConfigKey: StorageKey { typealias Value = SwiftSMTPVaporConfig }
        enum SharedMailerKeys {
            enum Storage: StorageKey { typealias Value = Mailer }
            enum Lock: LockKey {}
        }

        @usableFromInline
        let application: Application

        init(application: Application) { self.application = application }

        @usableFromInline
        var config: SwiftSMTPVaporConfig {
            guard let config = application.storage[ConfigKey.self] else {
                fatalError("SwiftSMTP not initialized! Use `SMTPInitializer` or manually initialize with `application.swiftSMTP.initialize(...)`.")
            }
            return config
        }

        /// The SwiftSMTP configuration this application uses.
        @inlinable
        public var configuration: Configuration { config.configuration }

        /// The shared Mailer for this application.
        public var mailer: Mailer {
            application.locks.lock(for: SharedMailerKeys.Lock.self).withLock {
                if let existing = application.storage[SharedMailerKeys.Storage.self] {
                    return existing
                }
                let newMailer = config.createNewMailer(with: application)
                application.storage[SharedMailerKeys.Storage.self] = newMailer
                return newMailer
            }
        }

        func initialize(with config: SwiftSMTPVaporConfig, registerShutdownHandler: Bool) {
            application.storage[ConfigKey.self] = config
            if registerShutdownHandler, case .custom(_) = config.eventLoopGroupSource {
                application.lifecycle.use(SharedMailerGroupShutdownHandler())
            }
        }

        /// Initializes the SwiftSMTP setup of the application with the given configuration.
        /// - Parameter configuration: The configuration to use for the application's mailers.
        /// - Parameter eventLoopGroupSource: The source for the event loop group to use. Defaults to `.application`.
        /// - Parameter maxConnectionsConfiguration: The maximum connections configuration per mailer. Defaults to `.useDefault`.
        /// - Parameter logTransmissions: Whether to log transmissions with a SwiftLogger. Defaults to `false`.
        public func initialize(with configuration: Configuration,
                               eventLoopGroupSource: SwiftSMTPEventLoopGroupSource = .application,
                               maxConnectionsConfiguration: SwiftSMTPMaxConnectionsConfiguration = .useDefault,
                               logTransmissions: Bool = false) {
            initialize(with: .init(eventLoopGroupSource: eventLoopGroupSource,
                                   configuration: configuration,
                                   maxConnectionsConfig: maxConnectionsConfiguration,
                                   logTransmissions: logTransmissions),
                       registerShutdownHandler: true)
        }

        /// Creates a new Mailer.
        /// The caller is responsible for keeping the mailer alive until and cleaning up after all mails have been sent.
        /// - Returns: A new Mailer instance.
        @inlinable
        public func createNewMailer() -> Mailer {
            config.createNewMailer(with: application)
        }
    }

    /// Returns the SwiftSMTP configuration for this application.
    public var swiftSMTP: SwiftSMTP { .init(application: self) }
}

extension Request {
    /// Returns the SwiftSMTP configuration for this request's application.
    @inlinable
    public var swiftSMTP: Application.SwiftSMTP { application.swiftSMTP }
}
