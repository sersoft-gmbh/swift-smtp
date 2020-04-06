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

    @inline(__always)
    func validate() throws {
        if case .error(let message) = self {
            throw ServerError(serverMessage: message)
        }
    }
}
