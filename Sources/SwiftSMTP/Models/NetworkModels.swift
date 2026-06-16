internal import struct Foundation.Data
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
    case transferRawData(Data)
    case quit
}

typealias SMTPResponse = Result<(Int, String), ServerError>

@usableFromInline
struct SendJob: Sendable {
    enum Payload: Sendable {
        case email(Email)
        case rawData(Data)
    }

    let sender: String
    let recipients: Array<String>
    let payload: Payload
}

extension SendJob {
    @usableFromInline
    init(email: Email) {
        self.init(sender: email.sender.emailAddress,
                  recipients: email.allRecipients.map(\.emailAddress),
                  payload: .email(email))
    }
}
