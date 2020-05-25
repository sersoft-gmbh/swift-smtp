import NIO
import Vapor
@_exported import SwiftSMTP

/// Represents the source for the event loop group used by the Mailer.
public enum SwiftSMTPEventLoopGroupSource {
    case application
    case custom(() -> EventLoopGroup)

    public static func createNew(numberOfThreads: Int = max(System.coreCount / 2, 1)) -> SwiftSMTPEventLoopGroupSource {
        .custom { MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads) }
    }
}

@usableFromInline
struct SwiftSMTPVaporConfig {
    @usableFromInline
    let eventLoopGroupSource: SwiftSMTPEventLoopGroupSource
    @usableFromInline
    let configuration: Configuration
    @usableFromInline
    let logTransmissions: Bool

    @usableFromInline
    func createNewMailer(with application: Application) -> Mailer {
        let eventLoopGroup: EventLoopGroup
        switch eventLoopGroupSource {
        case .application: eventLoopGroup = application.eventLoopGroup
        case .custom(let creator): eventLoopGroup = creator()
        }
        return Mailer(group: eventLoopGroup,
                      configuration: configuration,
                      transmissionLogger: logTransmissions ? Logger(label: "de.sersoft.swiftsmtp") : nil)
    }

    init(eventLoopGroupSource: SwiftSMTPEventLoopGroupSource, configuration: Configuration, logTransmissions: Bool) {
        self.eventLoopGroupSource = eventLoopGroupSource
        self.configuration = configuration
        self.logTransmissions = logTransmissions
    }
}

/// Initializes the SwiftSMTP configuration on the application on boot.
public struct SMTPInitializer: LifecycleHandler {
    @usableFromInline
    let config: SwiftSMTPVaporConfig

    /// The source for the event loop group for the Mailer.
    @inlinable
    public var eventLoopGroupSource: SwiftSMTPEventLoopGroupSource { config.eventLoopGroupSource }

    /// The configuration this initializer configures the application with.
    @inlinable
    public var configuration: Configuration { config.configuration }

    /// Wether or not to log transissions.
    @inlinable
    public var logTransmissions: Bool { config.logTransmissions }

    /// Creates a new initializer for a given configuration.
    /// - Parameter configuration: The configuration to use for the application's mailers.
    /// - Parameter eventLoopGroupSource: The source for the event loop group.
    /// - Parameter logTransmission: Whether or not to log transmissions with a SwiftLogger. Defaults to `false`.
    public init(configuration: Configuration,
                eventLoopGroupSource: SwiftSMTPEventLoopGroupSource = .application,
                logTransmissions: Bool = false) {
        self.config = .init(eventLoopGroupSource: eventLoopGroupSource,
                            configuration: configuration,
                            logTransmissions: logTransmissions)
    }

    public func willBoot(_ application: Application) throws {
        application.swiftSMTP.initialize(with: config, registerShutdownHandler: false)
    }

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
            application.logger.error("[SWIFTSMTP]: Failed to shutdown custom event loop group of shared mailer!")
            application.logger.report(error: error)
        }
    }

    func shutdown(_ application: Application) {
        Self.shutdownSharedMailerGroup(of: application)
    }
}

extension Logger: SMTPLogger {
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

        func initialize(with config: SwiftSMTPVaporConfig, registerShutdownHandler: Bool = true) {
            application.storage[ConfigKey.self] = config
            if registerShutdownHandler, case .custom(_) = config.eventLoopGroupSource {
                application.lifecycle.use(SharedMailerGroupShutdownHandler())
            }
        }

        /// Initializes the SwiftSMTP setup of the application with the given configuration.
        /// - Parameter configuration: The configuration to use for the application's mailers.
        /// - Parameter eventLoopGroupSource: The source for the event loop group to use. Defaults to `.application`.
        /// - Parameter logTransmissions: Whether to log transmissions with a SwiftLogger. Defaults to `false`.
        public func initialize(with configuration: Configuration,
                               eventLoopGroupSource: SwiftSMTPEventLoopGroupSource = .application,
                               logTransmissions: Bool = false) {
            initialize(with: .init(eventLoopGroupSource: eventLoopGroupSource,
                                   configuration: configuration,
                                   logTransmissions: logTransmissions))
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
