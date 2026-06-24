internal import struct Foundation.Date
internal import struct NIO.ByteBuffer

enum MessagePayload: Sendable {
    case precomposed(ByteBuffer)
    case newlyComposed(Email, date: Date)
}

enum SMTPRequest: Sendable {
    case sayHello(serverName: String, useEHello: Bool)
    case startTLS
    case beginAuthentication
    case authUser(String)
    case authPassword(String)
    case mailFrom(String)
    case recipient(String)
    case data
    case transferPayload(MessagePayload)
    case quit
}

typealias SMTPResponse = Result<(Int, String), ServerError>
