private let _crlf = [UInt8.carriageReturn, UInt8.lineFeed]

extension Sequence where Self == Array<UInt8> {
    internal static var crlf: Self { _crlf }
}
