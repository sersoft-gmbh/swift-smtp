#if canImport(Darwin) || swift(>=6.0)
public import struct Foundation.Data
#else
@preconcurrency public import Foundation
#endif
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
    var allRecipients: Array<Contact> { recipients + cc + bcc }

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

        var asMIME: String {
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

    /// Represents the body of an email.
    /// - plain: A plain text body with no formatting.
    /// - html: An HTML formatted body.
    /// - universal: A body containing both, plain text and HTML. The recipient's client will determine what to show.
    public enum Body: Sendable, Hashable {
        case plain(String)
        case html(String)
        case universal(plain: String, html: String)
    }

    /// Represents an email attachment.
    public struct Attachment: Sendable, Equatable {
        /// The (file) name of the attachment.
        public var name: String
        /// The content type of the attachment.
        public var contentType: String
        /// The data of the attachment.
        public var data: Data
        /// The content id of the attachment.
        /// This can be used for referencing the attachment in the email body.
        /// Note that the content id must be unique.
        /// The recommended format is to use `<some-generated-value>@domain.example.com`.
        public var contentID: String?

        /// Creates a new email attachment with the given parameters.
        /// - Parameters:
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - data: The data of the attachment.
        ///   - contentID: The content id of the attachment.
        public init(name: String, contentType: String, data: Data, contentID: String?) {
            self.name = name
            self.contentType = contentType
            self.data = data
            self.contentID = contentID
        }

        /// Creates a new email attachment with the given parameters.
        /// - Parameters:
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - data: The data of the attachment.
        public init(name: String, contentType: String, data: Data) {
            self.init(name: name, contentType: contentType, data: data, contentID: nil)
        }

        /// Creates a new email attachment with the given parameters.
        /// - Parameters:
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - contents: The contents of the attachment.
        ///   - contentID: The content id of the attachment.
        public init(name: String, contentType: String, contents: ByteBuffer, contentID: String?) {
            self.init(name: name, contentType: contentType, data: Data(contents.readableBytesView), contentID: contentID)
        }

        /// Creates a new email attachment with the given parameters.
        /// - Parameters:
        ///   - name: The (file) name of the attachment.
        ///   - contentType: The content type of the attachment.
        ///   - contents: The contents of the attachment.
        public init(name: String, contentType: String, contents: ByteBuffer) {
            self.init(name: name, contentType: contentType, contents: contents, contentID: nil)
        }
    }
}
