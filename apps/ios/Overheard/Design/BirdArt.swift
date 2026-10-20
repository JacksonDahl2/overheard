import UIKit

/// The hand-drawn birds bundled with the app (art/birds/cutouts, one PNG per species code).
/// Birds without a drawing yet return nil; the page draws a placeholder for them.
@MainActor
enum BirdArt {
    private static var cache: [String: UIImage] = [:]
    private static var missing: Set<String> = []

    static func image(for code: String) -> UIImage? {
        if let image = cache[code] { return image }
        if missing.contains(code) { return nil }

        guard
            let url = Bundle.main.url(forResource: code, withExtension: "png", subdirectory: "cutouts"),
            let image = UIImage(contentsOfFile: url.path)
        else {
            missing.insert(code)
            return nil
        }

        cache[code] = image
        return image
    }
}
