import struct Foundation.Date
import struct Foundation.Locale
import class Foundation.DateFormatter

extension Date {
    private static let smtpLocale = Locale(identifier: "en_US_POSIX")

    @available(macOS, deprecated: 12)
    @available(iOS, deprecated: 15)
    @available(tvOS, deprecated: 15)
    @available(watchOS, deprecated: 6)
    private static let smtpFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = smtpLocale
        formatter.timeZone = .current
        formatter.calendar = .current
        return formatter
    }()

    var formattedForSMTP: String {
        if #available(macOS 12, iOS 15, tvOS 15, watchOS 6, *) {
            return formatted(VerbatimFormatStyle(
                format: "\(weekday: .abbreviated), \(day: .twoDigits) \(standaloneMonth: .abbreviated) \(year: .padded(4)) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) \(timeZone: .iso8601(.short))",
                locale: Self.smtpLocale, timeZone: .current, calendar: .current))
        } else {
            return Self.smtpFormatter.string(from: self)
        }
    }
}
