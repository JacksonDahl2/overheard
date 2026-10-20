import Foundation

/// A walk's name until the app knows where it is: "Morning walk", "Evening walk", …
/// Once a place name is found (e.g. "The Ramble, Central Park") it replaces this.
public enum WalkTitle {
    public static func `default`(for date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Morning walk"
        case 12..<17: "Afternoon walk"
        case 17..<21: "Evening walk"
        default: "Night walk"
        }
    }
}
