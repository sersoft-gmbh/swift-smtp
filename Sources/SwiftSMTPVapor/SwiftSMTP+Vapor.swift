@_exported import SwiftSMTP
import Vapor

/// Initializes the SwiftSMTP configuration on the application on boot.
public struct SMTPInitializer: LifecycleHandler {
    /// The configuration this initializer configures the application with.
    public let configuration: Configuration

    /// Wether or not to log transissions.
    public let logTransmissions: Bool

    /// Creates a new initializer for a given configuration.
    /// - Parameter configuration: The configuration to use for the application's mailers.
    /// - Parameter logTransmission: Whether or not to log transmissions with a SwiftLogger. Defaults to `false`.
    @inlinable
    public init(configuration: Configuration, logTransmissions: Bool = false) {
        self.configuration = configuration
        self.logTransmissions = logTransmissions
    }

    @inlinable
    public func willBoot(_ application: Application) throws {
        application.swiftSMTP.initialize(with: configuration)
    }
}

extension Logger: SMTPLogger {
    @inlinable
    public func logSMTPMessage(_ message: @autoclosure () -> String) {
        log(level: .info, "\(message())")
    }
}

extension Application {
    /// Represents the application's SwiftSMTP configuration.
    public struct SwiftSMTP {
        @usableFromInline
        final class Storage {
            enum Key: StorageKey { typealias Value = Storage }

            @usableFromInline
            let configuration: Configuration
            @usableFromInline
            let mailers: [ObjectIdentifier: Mailer]

            init(elg: EventLoopGroup, configuration: Configuration, logger: SMTPLogger?) {
                self.configuration = configuration
                self.mailers = elg.makeIterator().reduce(into: [:]) {
                    $0[ObjectIdentifier($1)] = Mailer(group: $1, configuration: configuration, transmissonLogger: logger)
                }
            }
        }

        @usableFromInline
        let application: Application

        @inlinable
        init(application: Application) { self.application = application }

        @usableFromInline
        var storage: Storage {
            guard let storage = application.storage[Storage.Key.self] else {
                fatalError("SwiftSMTP not initialized! Initialize with `application.swiftSMTP.initialize(with:)`.")
            }
            return storage
        }

        /// The SwiftSMTP configuration this application uses.
        @inlinable
        public var configuration: Configuration { storage.configuration }

        /// Initializes the SwiftSMTP setup of the application with the given configuration.
        /// - Parameter configuration: The configuration to use for the application's mailers.
        /// - Parameter logTransmissions: Whether or not to log transmissions with a SwiftLogger. Defaults to `false`.
        public func initialize(with configuration: Configuration, logTransmissions: Bool = false) {
            application.storage[Storage.Key.self] = .init(elg: application.eventLoopGroup,
                                                          configuration: configuration,
                                                          logger: logTransmissions ? Logger(label: "de.sersoft.swiftsmtp") : nil)
        }

        @inlinable
        func mailer(for eventLoop: EventLoop) -> Mailer {
            storage.mailers[ObjectIdentifier(eventLoop)]!
        }
    }

    /// Returns the SwiftSMTP configuration for this application.
    @inlinable
    public var swiftSMTP: SwiftSMTP { .init(application: self) }
}

extension Request {
    /// Represents the requests's SwiftSMTP configuration.
    public struct SwiftSMTP {
        @usableFromInline
        let request: Request

        @inlinable
        init(request: Request) { self.request = request }

        /// Returns the configuration for this request.
        @inlinable
        public var configuration: Configuration {
            request.application.swiftSMTP.configuration
        }

        /// Returns the mailer for this request.
        @inlinable
        public var mailer: Mailer {
            request.application.swiftSMTP.mailer(for: request.eventLoop)
        }
    }

    /// Returns the SwiftSMTP configuration for this request (based on the configuration of this request's application).
    @inlinable
    public var swiftSMTP: SwiftSMTP { .init(request: self) }
}
