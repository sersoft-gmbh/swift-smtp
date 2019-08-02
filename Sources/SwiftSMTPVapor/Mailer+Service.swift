import SwiftSMTP
import Service

extension Mailer: ServiceType {
    public static func makeService(for container: Container) throws -> Mailer {
        return try Mailer(group: container.eventLoop, configuration: container.make())
    }
}
