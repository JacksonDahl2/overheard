import SwiftUI

/// The four tabs (docs/design.md): Listen, Journal, Flock, Me.
enum Tab: CaseIterable, Identifiable {
    case listen, journal, flock, me

    var id: Self { self }

    var title: String {
        switch self {
        case .listen: "Listen"
        case .journal: "Journal"
        case .flock: "Flock"
        case .me: "Me"
        }
    }
}

/// The tab bar from the mockups: thin-stroke line icons over a label, no emoji.
struct TabBar: View {
    @Binding var selection: Tab

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        TabIcon(tab: tab).frame(width: 24, height: 24)
                        Text(tab.title).font(.body(13, relativeTo: .caption))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selection == tab ? theme.accent : theme.tabSoft)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background {
            theme.tabBackground
                .overlay(alignment: .top) { theme.rule.frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Each tab's icon, drawn as a 24×24 line path to match the mockups.
private struct TabIcon: View {
    let tab: Tab

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 24
            let path = Self.path(for: tab).applying(CGAffineTransform(scaleX: scale, y: scale))
            context.stroke(
                path, with: .foreground,
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }

    static func path(for tab: Tab) -> Path {
        var p = Path()
        switch tab {
        case .listen:
            // A sound wave: five bars of different heights.
            for (x, top, bottom) in [(12.0, 4.0, 20.0), (8, 8, 16), (16, 8, 16), (4, 11, 13), (20, 11, 13)] {
                p.move(to: CGPoint(x: x, y: top))
                p.addLine(to: CGPoint(x: x, y: bottom))
            }
        case .journal:
            // An open book.
            p.move(to: CGPoint(x: 4, y: 5))
            p.addCurve(to: CGPoint(x: 12, y: 6), control1: CGPoint(x: 7, y: 4), control2: CGPoint(x: 10, y: 4))
            p.addCurve(to: CGPoint(x: 20, y: 5), control1: CGPoint(x: 14, y: 4), control2: CGPoint(x: 17, y: 4))
            p.addLine(to: CGPoint(x: 20, y: 19))
            p.addCurve(to: CGPoint(x: 12, y: 20), control1: CGPoint(x: 17, y: 18), control2: CGPoint(x: 14, y: 18))
            p.addCurve(to: CGPoint(x: 4, y: 19), control1: CGPoint(x: 10, y: 18), control2: CGPoint(x: 7, y: 18))
            p.closeSubpath()
            p.move(to: CGPoint(x: 12, y: 6))
            p.addLine(to: CGPoint(x: 12, y: 20))
        case .flock:
            // Birds in flight: three soft wing strokes.
            p.move(to: CGPoint(x: 3, y: 15))
            p.addCurve(to: CGPoint(x: 16, y: 13), control1: CGPoint(x: 6, y: 14), control2: CGPoint(x: 10, y: 10))
            p.move(to: CGPoint(x: 8, y: 19))
            p.addCurve(to: CGPoint(x: 21, y: 17), control1: CGPoint(x: 11, y: 18), control2: CGPoint(x: 15, y: 14))
            p.move(to: CGPoint(x: 5, y: 10))
            p.addQuadCurve(to: CGPoint(x: 10, y: 7), control: CGPoint(x: 8, y: 8))
        case .me:
            // A person: head and shoulders.
            p.addEllipse(in: CGRect(x: 8, y: 5, width: 8, height: 8))
            p.move(to: CGPoint(x: 4, y: 20))
            p.addCurve(to: CGPoint(x: 20, y: 20), control1: CGPoint(x: 5, y: 16), control2: CGPoint(x: 19, y: 16))
        }
        return p
    }
}
