import SwiftUI

/// The app's two looks (docs/design.md): Parchment (light) and By Candlelight (dark).
/// Views read the current one with `@Environment(\.theme)`.
struct Theme {
    // Chrome: the screen around the journal page.
    let chromeBackground: Color
    let chromeInk: Color
    let chromeSoft: Color
    let tabBackground: Color
    let tabSoft: Color
    let rule: Color
    /// Grouped rows in settings-style lists (Me), so they don't fall back to system gray.
    let card: Color

    // Accent: the active tab, primary button and "Listening".
    let accent: Color
    let accentInk: Color
    let accentHalo: Color

    // The journal page. Its ink is dark in both themes; the page stays paper-colored.
    let pageStops: [Gradient.Stop]
    let pageInk: Color
    let pageSoft: Color
    let accentOnPage: Color
    let pageShadow: Color
    let pageShadowRadius: CGFloat

    /// Status bar and system controls follow the theme, not the phone's setting.
    let colorScheme: ColorScheme

    /// The page fill: an elliptical gradient that reads as paper.
    var page: EllipticalGradient {
        EllipticalGradient(stops: pageStops, center: UnitPoint(x: 0.5, y: 0.32), endRadiusFraction: 0.78)
    }
}

extension Theme {
    static let parchment = Theme(
        chromeBackground: Color(hex: 0xF3EDE0),
        chromeInk: Color(hex: 0x2A1F15),
        chromeSoft: Color(hex: 0x665441),
        tabBackground: Color(hex: 0xECE4D2),
        tabSoft: Color(hex: 0x6E5B46),
        rule: Color(hex: 0x5A4226, opacity: 0.25),
        card: Color(hex: 0xFBF7EE),
        accent: Color(hex: 0x8B2F1C),
        accentInk: Color(hex: 0xF7EFDC),
        accentHalo: Color(hex: 0x8B2F1C, opacity: 0.18),
        pageStops: [
            .init(color: Color(hex: 0xFDFAF3), location: 0),
            .init(color: Color(hex: 0xF8F2E5), location: 0.6),
            .init(color: Color(hex: 0xEDE3CD), location: 1),
        ],
        pageInk: Color(hex: 0x2A1F15),
        pageSoft: Color(hex: 0x6A5741),
        accentOnPage: Color(hex: 0x8B2F1C),
        pageShadow: Color(hex: 0x5A4226, opacity: 0.16),
        pageShadowRadius: 10,
        colorScheme: .light)

    static let candlelight = Theme(
        chromeBackground: Color(hex: 0x17100A),
        chromeInk: Color(hex: 0xF2E2C0),
        chromeSoft: Color(hex: 0xC4A77B),
        tabBackground: Color(hex: 0x120C07),
        tabSoft: Color(hex: 0xA98F68),
        rule: Color(hex: 0xF2E2C0, opacity: 0.14),
        card: Color(hex: 0x22180E),
        accent: Color(hex: 0xE9A24F),
        accentInk: Color(hex: 0x1B130C),
        accentHalo: Color(hex: 0xE9A24F, opacity: 0.22),
        pageStops: [
            .init(color: Color(hex: 0xECD3A4), location: 0),
            .init(color: Color(hex: 0xD8B986), location: 0.5),
            .init(color: Color(hex: 0xB8935E), location: 0.85),
            .init(color: Color(hex: 0x8F6D42), location: 1),
        ],
        pageInk: Color(hex: 0x2A1F15),
        pageSoft: Color(hex: 0x4E3A22),
        accentOnPage: Color(hex: 0x7A2812),
        pageShadow: Color(hex: 0xE9A24F, opacity: 0.2),
        pageShadowRadius: 24,
        colorScheme: .dark)
}

// MARK: - Choosing a theme

/// The user's choice in Me → Appearance. "System" follows the phone's light/dark setting.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case system, parchment, candlelight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Match the phone"
        case .parchment: "Parchment"
        case .candlelight: "By Candlelight"
        }
    }

    func theme(for systemScheme: ColorScheme) -> Theme {
        switch self {
        case .parchment: .parchment
        case .candlelight: .candlelight
        case .system: systemScheme == .dark ? .candlelight : .parchment
        }
    }
}

extension EnvironmentValues {
    @Entry var theme: Theme = .parchment
}

// MARK: - Hex colors

extension Color {
    /// A color from a 0xRRGGBB literal, as written in docs/design.md.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}
