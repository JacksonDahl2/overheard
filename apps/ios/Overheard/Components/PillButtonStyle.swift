import SwiftUI

/// The app's buttons (docs/design.md): pill-shaped and 48 pt tall.
/// Primary is filled with the accent; secondary is an outline in chrome ink.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    let kind: Kind
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body(17, weight: kind == .primary ? .medium : .regular))
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .foregroundStyle(kind == .primary ? theme.accentInk : theme.chromeInk)
            .background {
                switch kind {
                case .primary: Capsule().fill(theme.accent)
                case .secondary: Capsule().strokeBorder(theme.chromeInk, lineWidth: 1.5)
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var primaryPill: PillButtonStyle { PillButtonStyle(kind: .primary) }
    static var secondaryPill: PillButtonStyle { PillButtonStyle(kind: .secondary) }
}
