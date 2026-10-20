import SwiftUI

/// The four faces from docs/design.md, bundled in Resources/Fonts (all OFL).
/// Every size scales with Dynamic Type, relative to the closest system style.
extension Font {
    /// IM Fell English: screen and walk titles.
    static func display(_ size: CGFloat, relativeTo style: TextStyle = .title) -> Font {
        .custom("IM_FELL_English_Roman", size: size, relativeTo: style)
    }

    /// IM Fell English SC: small-caps labels like "Listening". Pair with `.tracking`.
    static func smallCaps(_ size: CGFloat, relativeTo style: TextStyle = .footnote) -> Font {
        .custom("IM_FELL_English_SC", size: size, relativeTo: style)
    }

    /// EB Garamond: UI text, lists and buttons.
    static func body(_ size: CGFloat, weight: BodyWeight = .regular, relativeTo style: TextStyle = .body) -> Font {
        .custom(weight.fontName, size: size, relativeTo: style)
    }

    /// EB Garamond Italic: species names in running text.
    static func bodyItalic(_ size: CGFloat, relativeTo style: TextStyle = .body) -> Font {
        .custom("EBGaramondItalic-Italic", size: size, relativeTo: style)
    }

    /// Caveat: handwriting on the page (bird labels, dates, notes, flourishes).
    static func hand(_ size: CGFloat, bold: Bool = false, relativeTo style: TextStyle = .body) -> Font {
        .custom(bold ? "Caveat-SemiBold" : "Caveat-Medium", size: size, relativeTo: style)
    }

    enum BodyWeight {
        case regular, medium, semibold

        var fontName: String {
            switch self {
            case .regular: "EBGaramond-Regular"
            case .medium: "EBGaramond-Medium"
            case .semibold: "EBGaramond-SemiBold"
            }
        }
    }
}

extension View {
    /// A small-caps label: IM Fell English SC with the letter-spacing from docs/design.md.
    func smallCapsLabel(_ size: CGFloat = 15) -> some View {
        font(.smallCaps(size)).tracking(size * 0.12)
    }
}
