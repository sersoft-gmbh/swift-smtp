import Foundation

public struct Email {
    public var sender: Contact
    public var replyTo: Contact?
    public var recipients: [Contact]

    public var cc: [Contact]
    public var bcc: [Contact]

    public var subject: String
    public var body: Body

    public var attachments: [Attachment]

    var allRecipients: [Contact] { return recipients + cc + bcc }

    var isMultipart: Bool {
        guard attachments.isEmpty else { return true }
        switch body {
        case .plain(_), .html(_): return false
        case .universal(_, _): return true
        }
    }

    public init(sender: Contact, replyTo: Contact? = nil, recipients: [Contact], cc: [Contact] = [], bcc: [Contact] = [], subject: String, body: Body, attachments: [Attachment] = []) {
        assert(!recipients.isEmpty, "Recipients must not be empty!")
        self.sender = sender
        self.replyTo = replyTo
        self.recipients = recipients
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
        self.attachments = attachments
    }
}

extension Email {
    public struct Contact: Hashable {
        public var name: String?
        public var emailAddress: String

        var asMIME: String {
            return name.map { "\($0) <\(emailAddress)>" } ?? emailAddress
        }

        public init(name: String? = nil, emailAddress: String) {
            self.name = name
            self.emailAddress = emailAddress
        }
    }

    public enum Body: Hashable {
        case plain(String)
        case html(String)
        case universal(plain: String, html: String)
    }

    public struct Attachment {
        public var name: String
        public var contentType: String
        public var data: Data

        public init(name: String, contentType: String, data: Data) {
            self.name = name
            self.contentType = contentType
            self.data = data
        }
    }
}
