import OverheardKit
import UIKit
import UserNotifications

/// Lets you know a new species just joined the walk.
///
/// With the app open: a light tap, or a stronger "success" tap for a bird that's unusual here.
/// With the screen locked: a notification instead, since haptics don't play in the background.
/// Turned on and off in Me → New-bird alerts.
@MainActor
final class NewBirdAlert {
    /// The Me switch, stored in UserDefaults; on unless turned off.
    static let settingKey = "newBirdAlerts"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    private let tap = UIImpactFeedbackGenerator(style: .light)
    private let rareTap = UINotificationFeedbackGenerator()

    /// Asks for notification permission once, at the start of the first walk with alerts on.
    func prepare() {
        guard Self.isEnabled else { return }

        tap.prepare()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func announce(_ bird: HeardBird) {
        guard Self.isEnabled else { return }

        if UIApplication.shared.applicationState == .active {
            playTap(for: bird)
        } else {
            postNotification(for: bird)
        }
    }

    // MARK: - Ways to tell you

    private func playTap(for bird: HeardBird) {
        if bird.commonness == .unusual {
            rareTap.notificationOccurred(.success)
        } else {
            tap.impactOccurred()
        }
    }

    private func postNotification(for bird: HeardBird) {
        let content = UNMutableNotificationContent()
        content.title = bird.species.commonName
        content.body = bird.commonness == .unusual ? "Heard on your walk — unusual here" : "Heard on your walk"
        content.sound = .default  // vibrates instead when the phone is on silent

        // One notification per species: a later call replaces rather than stacks.
        let request = UNNotificationRequest(identifier: "new-bird-\(bird.species.code)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
