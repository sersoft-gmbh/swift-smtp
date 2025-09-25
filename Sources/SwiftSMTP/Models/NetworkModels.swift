internal import struct Foundation.Date

enum SMTPRequest: Sendable {
    case sayHello(serverName: String, useEHello: Bool)
    case startTLS
    case beginAuthentication
    case authUser(String)
    case authPassword(String)
    case mailFrom(String)
    case recipient(String)
    case data
    case transferData(date: Date, email: Email)
    case quit
}

typealias SMTPResponse = Result<(Int, String), ServerError>
