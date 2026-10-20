import Foundation

/// How the app writes distances, durations and dates, in one place so every screen agrees.
enum Formatting {
    /// "1.6 mi" or "2.4 km", following the phone's region.
    static func distance(_ meters: Double) -> String {
        let style = Measurement<UnitLength>.FormatStyle(
            width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1)))
        return Measurement(value: meters, unit: UnitLength.meters).formatted(style)
    }

    /// "1 hr, 12 min" or "42 min".
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// The handwritten date at the top of a journal page: "Sat 18 Oct · 7:12am".
    static func pageDate(_ date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let time = date.formatted(date: .omitted, time: .shortened)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        return "\(day) · \(time)"
    }

    static func count(_ n: Int, _ singular: String, _ plural: String) -> String {
        n == 1 ? "1 \(singular)" : "\(n) \(plural)"
    }
}
