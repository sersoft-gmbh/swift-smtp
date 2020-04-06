import NIO
import Foundation

/// Describes a logger that logs SMTP messages.
public protocol SMTPLogger {
    /// Called whenever an SMTP message should be logged.
    /// - Parameter message: The message to log as an @autoclosure.
    ///                      If the logger does not log the message, the closure should not be executed for performance reasons.
    func logSMTPMessage(_ message: @autoclosure () -> String)
}

/// A simple SMTP logger that logs messages using `print`.
@frozen
public struct PrintSMTPLogger: SMTPLogger {
    /// Creates a new PrintSMTPLogger.
    @inlinable
    public init() {}

    @inlinable
    public func logSMTPMessage(_ message: @autoclosure () -> String) {
        print(message())
    }
}

final class LogDuplexHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    let logger: SMTPLogger

    init(logger: SMTPLogger) {
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
