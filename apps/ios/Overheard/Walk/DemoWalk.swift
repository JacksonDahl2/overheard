#if DEBUG
    import Foundation
    import OverheardKit

    /// A sample walk for screenshots and design work: launch with `-demo` (Debug builds only).
    /// It mirrors the Listen mockup: a few common birds, one rare one, one still being sketched.
    struct DemoWalk {
        let walk: Walk
        let birds: [HeardBird]
        /// A bird heard a few seconds after the sample walk opens, to show a new arrival.
        let arrival: HeardBird?
        let pending: [PendingBird]
        let justHeard: BirdScore?
        let levels: [(level: Float, heardBird: Bool)]

        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

        init(catalog: SpeciesCatalog) {
            let start = Date.now.addingTimeInterval(-42 * 60)
            walk = Walk(startedAt: start)
            walk.placeName = "The Ramble, Central Park"

            func heard(_ code: String, calls: Int, minute: Double, _ commonness: Commonness = .common) -> HeardBird? {
                guard let species = catalog.species(code: code) else { return nil }
                let time = start.addingTimeInterval(minute * 60)
                return HeardBird(
                    species: species, calls: calls, bestConfidence: 0.86, firstHeard: time, lastHeard: time,
                    commonness: commonness)
            }

            birds = [
                heard("whtspa", calls: 4, minute: 2),
                heard("blujay", calls: 3, minute: 5),
                heard("norcar", calls: 2, minute: 9),
                heard("rethaw", calls: 1, minute: 20),
                heard("scatan", calls: 1, minute: 31, .unusual),
            ].compactMap { $0 }

            arrival = heard("amerob", calls: 1, minute: 42)

            let warbler = catalog.species(code: "btbwar")
            pending =
                warbler.map {
                    [PendingBird(species: $0, clips: 1, peakConfidence: 0.62, since: .now, commonness: .common)]
                } ?? []
            justHeard = warbler.map {
                BirdScore(index: 0, species: $0, confidence: 0.94, requiredConfidence: 0.5, commonness: .common)
            }

            // Quiet background, then a song in the last few seconds.
            levels = (0..<LevelHistory.capacity).map { i in
                let singing = i >= LevelHistory.capacity - 12
                let level: Float =
                    singing ? 0.05 + 0.04 * Float((i * 7) % 5) / 4 : 0.008 + 0.006 * Float((i * 5) % 4) / 3
                return (level, singing)
            }
        }
    }
#endif
