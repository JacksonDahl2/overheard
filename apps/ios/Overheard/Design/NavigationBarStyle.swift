import UIKit

/// Navigation titles ("Journal", "Me", a walk's name) in IM Fell English, like every other
/// title in the app. UIKit draws these bars, so the font is set once, app-wide, at launch.
@MainActor
enum NavigationBarStyle {
    static func apply() {
        let bar = UINavigationBar.appearance()

        if let large = UIFont(name: "IM_FELL_English_Roman", size: 34) {
            bar.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
        if let inline = UIFont(name: "IM_FELL_English_Roman", size: 20) {
            bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: inline)]
        }
    }
}
