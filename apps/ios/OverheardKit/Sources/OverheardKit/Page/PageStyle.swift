import Foundation

/// Every setting that shapes a journal page, in one place. `PageLayout`, `BirdSize` and the
/// app's page views read from this; nothing about the look is hard-coded elsewhere.
///
/// To change the look: edit `standard` below, or try values live in the app (Debug builds:
/// Me → Field-test tools → Page tuning) and paste the code that screen copies.
public struct PageStyle: Sendable, Equatable, Codable {

    // MARK: Size (how big a bird is drawn)

    /// A bird heard once, as a fraction of full size.
    public var smallestBirdFraction: Double
    /// Calls at which a bird reaches full size; more calls don't make it bigger.
    public var fullSizeAtCalls: Int
    /// Full size, in points…
    public var largestBird: Double
    /// …or this fraction of the page width, whichever is smaller.
    public var largestBirdPageFraction: Double
    /// No drawing is smaller than this, in points.
    public var smallestBird: Double
    /// How much a handful of birds may grow beyond full size to fill an empty page.
    public var fillScale: Double

    // MARK: Spacing and character

    /// How far drawings may tuck into each other's empty margins, in points.
    public var nestle: Double
    /// The largest tilt either way, in degrees.
    public var maxTilt: Double

    // MARK: Spread (where birds aim to sit)

    /// The first bird's spot, as fractions of the page (0…1).
    public var firstSpotX: Double
    public var firstSpotY: Double
    /// The band the other birds spread over, as fractions of the page width and height.
    public var spreadLeft: Double
    public var spreadRight: Double
    public var spreadTop: Double
    public var spreadBottom: Double
    /// How far each bird's spot is nudged at random, as a fraction of the page.
    public var nudge: Double

    // MARK: Names (shown on tap)

    /// Handwriting size for a bird's name when it's shown.
    public var nameFontSize: Double
    /// How long a name stays before it fades, in seconds.
    public var nameShowsFor: Double
    /// On the live Listen page, show each new bird's name for a moment when it's first drawn.
    public var introducesNewBirds: Bool

    // MARK: Search (how hard the layout works; rarely needs changing)

    /// How finely free spots are searched for, in points.
    public var searchStep: Double
    /// Arrangements tried at each size before everything shrinks.
    public var arrangementsPerSize: Int
    /// Each step of shrinking when birds don't fit, and the smallest scale it goes to.
    public var shrinkStep: Double
    public var smallestScale: Double

    /// The look the app ships with.
    public static let standard = PageStyle(
        smallestBirdFraction: 0.3,
        fullSizeAtCalls: 10,
        largestBird: 280,
        largestBirdPageFraction: 0.7,
        smallestBird: 96,
        fillScale: 1.7,
        nestle: 14,
        maxTilt: 5,
        firstSpotX: 0.5,
        firstSpotY: 0.14,
        spreadLeft: 0.2,
        spreadRight: 0.8,
        spreadTop: 0.08,
        spreadBottom: 0.86,
        nudge: 0.12,
        nameFontSize: 19,
        nameShowsFor: 4,
        introducesNewBirds: true,
        searchStep: 8,
        arrangementsPerSize: 4,
        shrinkStep: 0.9,
        smallestScale: 0.3)
}
