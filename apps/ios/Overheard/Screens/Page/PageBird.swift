import OverheardKit

/// One bird as the journal page draws it: confirmed (with its call count) or still being sketched.
struct PageBird: Identifiable, Equatable {
    let species: Species
    let calls: Int
    let commonness: Commonness?
    /// Heard but not confirmed yet: drawn faint, in a dashed red circle, labeled "sketching…".
    let isSketching: Bool

    var id: String { species.code }

    /// The rare-bird flourish: a red-ink note, for birds unusual here this time of year.
    var hasFlourish: Bool { !isSketching && commonness == .unusual }

    init(_ bird: HeardBird) {
        species = bird.species
        calls = bird.calls
        commonness = bird.commonness
        isSketching = false
    }

    /// A bird from a saved walk (which stores only its species code).
    init(_ bird: WalkBird, species: Species) {
        self.species = species
        calls = bird.calls
        commonness = bird.commonness
        isSketching = false
    }

    init(_ bird: PendingBird) {
        species = bird.species
        calls = 1
        commonness = bird.commonness
        isSketching = true
    }

    /// The page's birds in first-heard order, so a new bird never moves the ones already drawn.
    static func onPage(birds: [HeardBird], pending: [PendingBird]) -> [PageBird] {
        let confirmed = birds.sorted { $0.firstHeard < $1.firstHeard }.map(PageBird.init)
        let sketching = pending.sorted { $0.since < $1.since }.map(PageBird.init)
        return confirmed + sketching
    }
}
