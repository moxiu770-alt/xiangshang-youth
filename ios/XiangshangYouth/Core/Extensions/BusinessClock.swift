import Foundation

/// Canonical school-day clock shared by local records and growth calendars.
/// Device timezone must not move a check-in or follow-up across a school day.
enum BusinessClock {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = Locale(identifier: "en_US_POSIX")
        value.timeZone = timeZone
        return value
    }

    static func startOfDay(_ date: Date = .now) -> Date { calendar.startOfDay(for: date) }

    static func addingDays(_ days: Int, to date: Date = .now) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    static func string(_ date: Date = .now, format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter.string(from: date)
    }

    static func day(_ date: Date = .now) -> String { string(date, format: "yyyy-MM-dd") }
}
