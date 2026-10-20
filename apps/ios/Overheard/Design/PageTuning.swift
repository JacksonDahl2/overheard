#if DEBUG
    import Foundation
    import Observation
    import OverheardKit

    /// The page style being tried out on the Page tuning screen (Debug builds only). It applies to
    /// every journal page in the app while you tune, survives relaunches, and can be copied as
    /// code to paste into `PageStyle.standard`.
    @MainActor
    @Observable
    final class PageTuning {
        var style: PageStyle { didSet { save() } }

        private static let storageKey = "pageTuning.style"

        init() {
            style =
                UserDefaults.standard.data(forKey: Self.storageKey)
                .flatMap { try? JSONDecoder().decode(PageStyle.self, from: $0) } ?? .standard
        }

        var isStandard: Bool { style == .standard }

        func reset() {
            style = .standard
        }

        /// `PageStyle.standard` written out with the current values, ready to paste over the one
        /// in OverheardKit/Page/PageStyle.swift.
        var asCode: String {
            let fields = Mirror(reflecting: style).children.compactMap { child -> String? in
                guard let name = child.label else { return nil }
                return "        \(name): \(Self.literal(child.value))"
            }
            return "    public static let standard = PageStyle(\n" + fields.joined(separator: ",\n") + ")"
        }

        private func save() {
            guard let data = try? JSONEncoder().encode(style) else { return }
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }

        /// A value as Swift source: whole numbers without a trailing ".0", others to 3 places.
        private static func literal(_ value: Any) -> String {
            switch value {
            case let number as Double:
                number.rounded() == number ? String(Int(number)) : String(format: "%.3g", number)
            default:
                String(describing: value)
            }
        }
    }
#endif
