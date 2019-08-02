enum SMTPRequest {
    case sayHello(serverName: String)
    case startTLS
    case beginAuthentication
    case authUser(String)
    case authPassword(String)
    case mailFrom(String)
    case recipient(String)
    case data
    case transferData(Email)
    case quit
}

enum SMTPResponse {
    case ok(Int, String)
    case error(String)

    func validate() throws {
        switch self {
        case .ok(_, _): break
        case .error(let message): throw ServerError(serverMessage: message)
        }
    }
}
