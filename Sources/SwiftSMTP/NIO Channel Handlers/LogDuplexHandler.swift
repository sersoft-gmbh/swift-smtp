#if swift(>=6.0)
import NIO
#else
public import NIO
#endif

/// Describes a logger that logs SMTP messages.
@preconcurrency
public protocol SMTPLogger: Sendable {
    /// Called whenever an SMTP message should be logged.
    /// - Parameter message: The message to log as an @autoclosure.
    ///                      If the logger does not log the message, the closure should not be executed for performance reasons.
    func logSMTPMessage(_ message: @autoclosure () -> String)
}

/// A simple SMTP logger that logs messages using `Swift.print`.
@frozen
public struct PrintSMTPLogger: SMTPLogger {
    /// Creates a new PrintSMTPLogger.
    @inlinable
    public init() {}

    @inlinable
    public func logSMTPMessage(_ message: @autoclosure () -> String) {
        Swift.print(message())
    }
}

final class LogDuplexHandler: Sendable, ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    let logger: any SMTPLogger

    init(logger: any SMTPLogger) {
        self.logger = logger
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        logger.logSMTPMessage("☁️ \(String(decoding: unwrapInboundIn(data).readableBytesView, as: UTF8.self))")
        context.fireChannelRead(data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        logger.logSMTPMessage("💻 \(String(decoding: unwrapOutboundIn(data).readableBytesView, as: UTF8.self))")
        context.write(data, promise: promise)
    }
}
