@_exported import SwiftSMTP
import Service

public struct SMTPProvider: Provider {
    public init() {}
    
    public func register(_ services: inout Services) throws {
        services.register(Mailer.self)
    }

    public func didBoot(_ container: Container) throws -> Future<Void> {
        return .done(on: container)
    }
}
