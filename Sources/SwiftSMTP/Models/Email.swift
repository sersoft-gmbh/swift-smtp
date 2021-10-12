import struct Foundation.Data
import struct NIO.ByteBuffer

/// Represents an email.
public struct Email {
    /// The sender of the email.
    public var sender: Contact
    /// An optional reply-to address.
    public var replyTo: Contact?

    /// The recipients of the email.
    /// - Precondition: Must not be empty.
    public var recipients: [Contact] {
        didSet {
            assert(!recipients.isEmpty, "Recipients must not be empty!")
        }
    }
    /// The (carbon-)copy recipients of the email.
    public var cc: [Contact]
    /// The blind (carbon-)copy recipients of the email.
    public var bcc: [Contact]

    /// The subject of the email.
    public var subject: String
    /// The body of the email.
    public var body: Body

    /// The attachments to attach to the email.
    public var attachments: [Attachment]

    @inlinable
    var allRecipients: [Contact] { recipients + cc + bcc }

    var isMultipart: Bool {
        guard attachments.isEmpty else { return true }
        switch body {
        case .plain(_), .html(_): return false
        case .universal(_, _): return true
        }
    }

    /// Creates a new email with the given parameters.
    /// - Parameters:
    ///   - sender: The sender of the email.
    ///   - replyTo: The optional reply-to address. Defaults to nil.
    ///   - recipients: The list of recipients of the email. Must not be empty!
    ///   - cc: The list of (carbon-)copy recipients. Defaults to an empty array.
    ///   - bcc: The list of blind (carbon-)copy recipients. Defaults to an empty array.
    ///   - subject: The subject of the email.
    ///   - body: The body of the email.
    ///   - attachments: The list of attachments of the email. Defaults to an empty array.
    public init(sender: Contact,
                replyTo: Contact? = nil,
                recipients: [Contact],
                cc: [Contact] = [],
                bcc: [Contact] = [],
                subject: String,
                body: Body,
                attachments: [Attachment] = []) {
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
    /// Represents an email contact.
    public struct Contact: Hashable {
        /// The (full) name of the contact. Can be `nil`.
        public var name: String?
        /// The email address of the contact.
        /// - Precondition: Must not be empty!
        public var emailAddress: String {
            didSet {
                assert(!emailAddress.isEmpty)
            }
        }

        var asMIME: String { name.map { "\($0) <\(emailAddress)>" } ?? emailAddress }

        /// Creates a new email contact with the given parameters.
        /// - Parameters:
        ///   - name: The (full) name of the contact. Defaults to `nil`.
        ///   - emailAddress: The email address of the contact. Must not be empty.
        public init(name: String? = nil, emailAddress: String) {
            assert(!emailAddress.isEmpty)
            self.name = name
            self.emailAddress = emailAddress
        }
    }

    /// Represents the body of an email.
    /// - plain: A plain text body with no formatting.
    /// - html: An HTML formatted body.
    /// - universal: A body containing both, plain text and HTML. The recipient's client will determine what to show.
    public enum Body: Hashable {
        case plain(String)
        case html(String)
        case universal(plain: String, html: String)
    }

    /// Represents an email attachment.
    public struct Attachment {
        /// The (file) name of the attachment.
        public var name: String
        /// The content type of the attachment.
        public var contentType: String
        /// The data of the attachment.
        public var data: Data

        /// Creates a new email attachment with the given parameters.
        /// - Parameters:
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - data: The data of the attachment.
        public init(name: String, contentType: String, data: Data) {
            self.name = name
            self.contentType = contentType
            self.data = data
        }

        /// Creates a new email attachment with the given parameters.
        /// - Parameters:
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - contents: The contents of the attachment.
        public init(name: String, contentType: String, contents: ByteBuffer) {
            self.init(name: name, contentType: contentType, data: Data(contents.readableBytesView))
        }
    }
}
