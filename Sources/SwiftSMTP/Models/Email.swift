public import struct Foundation.Data
public import struct NIO.ByteBuffer

/// Represents an email.
public struct Email: Sendable, Equatable {
    /// The sender of the email.
    public var sender: Contact
    /// An optional reply-to address.
    public var replyTo: Contact?

    /// The recipients of the email.
    /// - Precondition: Must not be empty.
    public var recipients: Array<Contact> {
        didSet {
            assert(!recipients.isEmpty, "Recipients must not be empty!")
        }
    }
    /// The (carbon-)copy recipients of the email.
    public var cc: Array<Contact>
    /// The blind (carbon-)copy recipients of the email.
    public var bcc: Array<Contact>

    /// The subject of the email.
    public var subject: String
    /// The body of the email.
    public var body: Body

    /// The attachments to attach to the email.
    public var attachments: Array<Attachment>

    @inlinable
    internal var allRecipients: Array<Contact> { recipients + cc + bcc }

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
                recipients: Array<Contact>,
                cc: Array<Contact> = [],
                bcc: Array<Contact> = [],
                subject: String,
                body: Body,
                attachments: Array<Attachment> = []) {
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
    public struct Contact: Sendable, Hashable {
        /// The (full) name of the contact. Can be `nil`.
        public var name: String?
        /// The email address of the contact.
        /// - Precondition: Must not be empty!
        public var emailAddress: String {
            didSet {
                assert(!emailAddress.isEmpty)
            }
        }

        internal var asMIME: String {
            guard let name else { return emailAddress }
            let quotedName = #""\#(name.replacingOccurrences(of: #"""#, with: #"\"#))""#
            return "\(quotedName) <\(emailAddress)>"
        }

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

    // TODO: The whole "body" & "attachments" part should be refactored to allow some kind of dynamic composition.
    //       This would also make multipart handling easier (alternative, mixed, related)...

    /// Represents the body of an email.
    public enum Body: Sendable, Hashable {
        /// A plain text body with no formatting.
        case plain(String)
        /// An HTML formatted body.
        case html(String)
        /// A body containing both, plain text and HTML. The recipient's client will determine what to show.
        case universal(plain: String, html: String)
    }

    /// Represents an email attachment.
    public struct Attachment: Sendable, Equatable {
        /// Defines the attachment kind. Relates to how email clients show it.
        /// This controls the `Content-Disposition` header of the attachment's MIME-part.
        /// The content id be used for referencing the attachment in the email body.
        /// Note that the content id must be unique. The recommended format is to use `<some-generated-value>@domain.example.com`.
        public enum Kind: Sendable, Hashable {
            /// A default attachment, that is shown by email clients as such. The content ID is optional.
            /// - Parameter contentID: The content ID of the attachment.
            case attachment(contentID: String?)
            /// An inline attachment, that can be referenced in HTML emails. A content ID is required.
            /// - Parameter contentID: The content ID of the attachment for later referencing.
            case inline(contentID: String)

            @usableFromInline
            internal var contentID: String? {
                switch self {
                case .attachment(let contentID), .inline(let contentID as String?): contentID
                }
            }
        }

        /// The kind of the attachment.
        public var kind: Kind
        /// The (file) name of the attachment.
        public var name: String
        /// The content type of the attachment.
        public var contentType: String
        /// The data of the attachment.
        public var data: Data

        internal var isInline: Bool {
            switch kind {
            case .attachment(_): false
            case .inline(_): true
            }
        }

        /// The content id of this attachment. Defined via ``kind-swift.property``.
        /// - SeeAlso:``Kind-swift.enum``
        @inlinable
        public var contentID: String? { kind.contentID }

        /// Creates a new email attachment with the given parameters.
        /// - Parameters:
        ///   - kind: The kind of this attachment.
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - data: The data of the attachment.
        public init(kind: Kind, name: String, contentType: String, data: Data) {
            self.kind = kind
            self.name = name
            self.contentType = contentType
            self.data = data
        }

        /// Creates a new email attachment with the given parameters. The resulting attachment is of kind `.attachment(contentID: nil)`.
        /// - Parameters:
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - data: The data of the attachment.
        public init(name: String, contentType: String, data: Data) {
            self.init(kind: .attachment(contentID: nil), name: name, contentType: contentType, data: data)
        }

        /// Creates a new email attachment with the given parameters.
        /// - Parameters:
        ///   - kind: The kind of this attachment.
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - contents: The contents of the attachment.
        public init(kind: Kind, name: String, contentType: String, contents: ByteBuffer) {
            self.init(kind: kind, name: name, contentType: contentType, data: Data(contents.readableBytesView))
        }

        /// Creates a new email attachment with the given parameters. The resulting attachment is of kind `.attachment(contentID: nil)`.
        /// - Parameters:
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - contents: The contents of the attachment.
        public init(name: String, contentType: String, contents: ByteBuffer) {
            self.init(kind: .attachment(contentID: nil), name: name, contentType: contentType, contents: contents)
        }
    }
}
