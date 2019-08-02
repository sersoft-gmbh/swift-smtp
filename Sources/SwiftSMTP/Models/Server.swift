public struct Configuration: Hashable {
    public var server: Server
    public var credentials: Credentials

    public init(server: Server, credentials: Credentials) {
        self.server = server
        self.credentials = credentials
    }
}

extension Configuration {
    public struct Server: Hashable {
        public var hostname: String
        public var port: Int
        public var encryption: Encryption

        public init(hostname: String, port: Int, encryption: Encryption = .plain) {
            self.hostname = hostname
            self.port = port
            self.encryption = encryption
        }
    }

    public struct Credentials: Hashable {
        public var username: String
        public var password: String

        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }
}

extension Configuration.Server {
    public enum Encryption: Hashable {
        case plain, ssl
        case startTLS(StartTLSMode)
    }
}

extension Configuration.Server.Encryption {
    public enum StartTLSMode: Hashable {
        case always, ifAvailable
    }
}
