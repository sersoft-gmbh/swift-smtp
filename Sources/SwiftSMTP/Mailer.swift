fileprivate import Dispatch
import Foundation
public import struct Foundation.Data
public import NIO
import NIOExtras
import NIOSSL
fileprivate import NIOConcurrencyHelpers

fileprivate extension StringProtocol {
    /// Whether the string contains a carriage return or line feed, either of which would allow SMTP command injection.
    var containsCRorLF: Bool {
        utf8.contains { $0 == 0x0D || $0 == 0x0A }
    }
}

fileprivate extension Configuration.Server {
    enum EncryptionHandler {
        case atBeginning(any ChannelHandler)
        case beforeSMTPHandler(any ChannelHandler)
    }

    // Errors are non-recoverable / non-retryable. Also, it's expensive to create these. So only do it once.
    private static let sslContext = try! NIOSSLContext(configuration: .makeClientConfiguration())

    func createEncryptionHandlers() throws -> EncryptionHandler? {
        switch encryption {
        case .plain: nil
        case .ssl: .atBeginning(try NIOSSLClientHandler(context: Self.sslContext, serverHostname: hostname))
        case .startTLS(let mode): .beforeSMTPHandler(StartTLSDuplexHandler(server: self, tlsMode: mode) { Self.sslContext })
        }
    }
}

/// A Mailer is responsible for opening server connections and dispatching emails.
public final class Mailer: Sendable {
    private struct ScheduledSend: Sendable {
        let sendJob: SendJob
        let promise: EventLoopPromise<Void>
    }

    /// The event loop group this mailer uses.
    public let group: any EventLoopGroup
    /// The configuration used by this mailer.
    public let configuration: Configuration
    /// The maximum number of connections this mailer should open. `nil` if no limit is set.
    public let maxConnections: Int?
    /// The logger to use for logging all transmissions. If `nil` no messages will be logged.
    public let transmissionLogger: (any SMTPLogger)?

    private let connectionsSemaphore: DispatchSemaphore?
    private let senderQueue = DispatchQueue(label: "SMTP Mailer Sender Queue")

    private let sendsStack = NIOLockedValueBox(Array<ScheduledSend>())

    /// Creates a new mailer with the given parameters.
    /// - Parameters:
    ///   - group: The event loop group the new mailer should use.
    ///   - configuration: The configuration to use for the new mailer.
    ///   - maxConnections: The maximum number of connections this mailer should open. `nil` if no limit should be set. Defaults to 2.
    ///   - transmissionLogger: The logger to use for logging all transmissions. If `nil` no messages will be logged.
    public init(group: any EventLoopGroup,
                configuration: Configuration,
                maxConnections: Int? = 2,
                transmissionLogger: (any SMTPLogger)? = nil) {
        self.group = group
        self.configuration = configuration
        self.maxConnections = maxConnections
        self.transmissionLogger = transmissionLogger

        if let maxConnections {
            assert(maxConnections > 0)
            connectionsSemaphore = DispatchSemaphore(value: maxConnections)
        } else {
            connectionsSemaphore = nil
        }
    }

    private func pushSend(_ scheduled: ScheduledSend) {
        sendsStack.withLockedValue { $0.append(scheduled) }
    }

    private func popSend() -> ScheduledSend? {
        sendsStack.withLockedValue { $0.isEmpty ? nil : $0.removeFirst() }
    }

    private func connectBootstrap(sending scheduled: ScheduledSend) {
        let bootstrap = ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .connectTimeout(configuration.connectionTimeOut)
            .channelInitializer { [configuration, transmissionLogger] channel in
                channel.eventLoop.makeCompletedFuture {
                    var base64Options: Data.Base64EncodingOptions = []
                    if configuration.featureFlags.contains(.maximumBase64LineLength64) {
                        base64Options.insert(.lineLength64Characters)
                    }
                    if configuration.featureFlags.contains(.maximumBase64LineLength76) {
                        base64Options.insert(.lineLength76Characters)
                    }
                    var handlers: Array<any ChannelHandler> = [
                        ByteToMessageHandler(LineBasedFrameDecoder()),
                        SMTPResponseDecoder(),
                        MessageToByteHandler(SMTPRequestEncoder(
                            base64EncodeAllMessages: configuration.featureFlags.contains(.base64EncodeAllMessages),
                            base64EncodingOptions: base64Options
                        )),
                        SMTPHandler(configuration: configuration, sendJob: scheduled.sendJob, allDonePromise: scheduled.promise),
                    ]
                    if let logger = transmissionLogger {
                        func makeLogHandler<Logger: SMTPLogger>(_ logger: Logger) -> LogDuplexHandler<Logger> {
                            LogDuplexHandler(logger: logger)
                        }
                        // TODO: Shouldn't this be handled by Swift nowadays?
                        let logHandler = _openExistential(logger, do: makeLogHandler)
                        handlers.insert(logHandler, at: handlers.startIndex)
                    }
                    switch try configuration.server.createEncryptionHandlers() {
                    case nil: break
                    case .atBeginning(let handler)?: handlers.insert(handler, at: handlers.startIndex)
                    case .beforeSMTPHandler(let handler)?: handlers.insert(handler, at: handlers.index(before: handlers.endIndex))
                    }
                    try channel.pipeline.syncOperations.addHandlers(handlers, position: .last)
                }
            }
        let connectionFuture = bootstrap.connect(host: configuration.server.hostname, port: configuration.server.port)
        connectionFuture.cascadeFailure(to: scheduled.promise)
        scheduled.promise.futureResult.whenComplete { [weak self] _ in
            connectionFuture.whenSuccess { $0.close(mode: .all, promise: nil) }
            guard let self else { return }
            self.connectionsSemaphore?.signal()
            self.scheduleMailDelivery()
        }
    }

    private func scheduleMailDelivery() {
        guard let next = popSend() else { return }
        senderQueue.async { [weak self] in
            self?.connectionsSemaphore?.wait()
            self?.connectBootstrap(sending: next)
        }
    }

    @usableFromInline
    func _sendFuture(for sendJob: SendJob) -> EventLoopFuture<Void> {
        // Guard every send path: a job with no recipients would make the handler send `DATA` with no
        // preceding `RCPT TO`, violating RFC 5321 §3.3. Fail the future rather than trapping, since the
        // public `send(_:)` email overload can reach here with an empty `Email` in release builds (the
        // `Email` recipients check is an `assert`, which is compiled out).
        guard !sendJob.recipients.isEmpty else {
            return group.next().makeFailedFuture(MissingRecipientsError())
        }
        let promise = group.next().makePromise(of: Void.self)
        pushSend(ScheduledSend(sendJob: sendJob, promise: promise))
        scheduleMailDelivery()
        return promise.futureResult
    }

    /// Schedules an email for delivery. Returns a future that will succeed once the email is sent, or fail with any error that occurrs during sending.
    /// - Parameter email: The email to send.
    /// - Returns: A future that will complete with the result of sending the email.
    @inlinable
    public func send(_ email: Email) -> EventLoopFuture<Void> {
        _sendFuture(for: SendJob(email: email))
    }

    /// Schedules an email for delivery. Returns when once the email is successfully sent, or throws any error that occurrs during sending.
    /// - Parameter email: The email to send.
    public func send(_ email: Email) async throws {
        try await send(email).get()
    }

    /// Schedules a pre-built RFC 2822 message payload for delivery, using the given SMTP envelope.
    ///
    /// Use this overload when the caller already owns the canonical RFC 2822 bytes for the message, e.g. when the same bytes
    /// must be delivered to SMTP `DATA` and stored verbatim via IMAP `APPEND`, when the message has been DKIM-signed and
    /// must not be re-serialised, or when forwarding a message retrieved from another mail store.
    ///
    /// The SMTP envelope (`from` / `to`) is independent of the RFC 2822 `From:` / `To:` headers. Pass the actual SMTP envelope
    /// here — typically including any BCC recipients that do not appear in the headers.
    ///
    /// The encoder applies dot-stuffing per RFC 5321 §4.5.2 and adds a trailing `<CRLF>` to the payload before the
    /// `<CRLF>.<CRLF>` terminator if the payload does not already end with one. Bare LFs in the payload pass through
    /// unchanged — strict servers may reject such payloads.
    ///
    /// The envelope addresses must not contain a carriage return or line feed; either would let arbitrary SMTP
    /// commands be injected into the session. Such addresses are rejected up front with `InvalidEnvelopeAddressError`.
    ///
    /// No maximum message size is enforced. The entire payload is buffered in memory while it is encoded, so the
    /// caller is responsible for keeping the message within a size their environment and server can handle.
    ///
    /// - Parameters:
    ///   - messageData: The full RFC 2822 message bytes (headers, blank line, body). Caller is responsible for content; this method does not validate or transform the headers.
    ///   - from: The envelope sender (used for `MAIL FROM`). Must not contain CR or LF.
    ///   - to: The envelope recipients (used for `RCPT TO`). Must be non-empty and must not contain CR or LF.
    /// - Returns: A future that will complete with the result of sending the message. Fails immediately with `MissingRecipientsError` if `to` is empty, or `InvalidEnvelopeAddressError` if any envelope address contains CR or LF.
    public func send(_ messageData: Data, from: String, to: Array<String>) -> EventLoopFuture<Void> {
        // Reject CR/LF before opening a connection; the empty-recipients case is caught by `_sendFuture`.
        for address in [from] + to where address.containsCRorLF {
            return group.next().makeFailedFuture(InvalidEnvelopeAddressError(address: address))
        }
        return _sendFuture(for: SendJob(sender: from, recipients: to, payload: .rawData(messageData)))
    }

    /// Schedules a pre-built RFC 2822 message payload for delivery, using the given SMTP envelope.
    ///
    /// See ``send(_:from:to:)-9z6kg`` for the design rationale and contract; this is the async-throwing variant.
    ///
    /// - Parameters:
    ///   - messageData: The full RFC 2822 message bytes (headers, blank line, body).
    ///   - from: The envelope sender (used for `MAIL FROM`). Must not contain CR or LF.
    ///   - to: The envelope recipients (used for `RCPT TO`). Must be non-empty and must not contain CR or LF.
    /// - Throws: `MissingRecipientsError` if `to` is empty, `InvalidEnvelopeAddressError` if any envelope address contains CR or LF; otherwise any error that occurs during sending.
    public func send(_ messageData: Data, from: String, to: Array<String>) async throws {
        try await send(messageData, from: from, to: to).get()
    }
}

extension Mailer {
    /// Schedules an email for delivery. Returns a future that will succeed once the email is sent, or fail with any error that occurrs during sending.
    /// - Parameter email: The email to send.
    /// - Returns: A future that will complete with the result of sending the email.
    @inlinable
    @available(*, deprecated, renamed: "send(_:)")
    public func send(email: Email) -> EventLoopFuture<Void> { send(email) }

    /// Schedules an email for delivery. Returns when once the email is successfully sent, or throws any error that occurrs during sending.
    /// - Parameter email: The email to send.
    @available(*, deprecated, renamed: "send(_:)")
    public func send(email: Email) async throws { try await send(email) }
}
