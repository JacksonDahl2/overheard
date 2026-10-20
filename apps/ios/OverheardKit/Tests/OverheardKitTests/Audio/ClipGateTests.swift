import XCTest

@testable import OverheardKit

final class LevelMeterTests: XCTestCase {
    func sine(_ hz: Double, amplitude: Float = 0.5, seconds: Double = 0.5) -> [Float] {
        let n = Int(seconds * BirdClassifier.sampleRate)
        return (0..<n).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / BirdClassifier.sampleRate)) }
    }

    func testPassesBirdBandAndCutsRumble() {
        let rms = Float(0.5) / 2.0.squareRoot().asFloat
        XCTAssertEqual(LevelMeter.highPassRMS(sine(4000)), rms, accuracy: 0.02)  // a song: kept
        XCTAssertLessThan(LevelMeter.highPassRMS(sine(100)), rms * 0.02)  // traffic rumble: ~-40 dB
    }

    func testSilenceIsZero() {
        XCTAssertEqual(LevelMeter.highPassRMS([Float](repeating: 0, count: 1000)), 0)
        XCTAssertEqual(LevelMeter.highPassRMS([]), 0)
    }
}

extension Double {
    fileprivate var asFloat: Float { Float(self) }
}

final class AdaptiveGateTests: XCTestCase {
    func testAnalyzesWhileLearningTheBackground() {
        var gate = AdaptiveGate()
        for _ in 0..<4 { XCTAssertTrue(gate.shouldAnalyze(level: 0.01)) }
        XCTAssertNil(gate.noiseFloor)
    }

    func testSkipsSteadyBackgroundButNotABirdOverIt() {
        var gate = AdaptiveGate()
        for _ in 0..<10 { _ = gate.shouldAnalyze(level: 0.01) }  // steady city hum
        XCTAssertEqual(gate.noiseFloor, 0.01)
        XCTAssertFalse(gate.shouldAnalyze(level: 0.012))  // still just background
        XCTAssertTrue(gate.shouldAnalyze(level: 0.03))  // a song 3x above it
    }

    func testNeverSkipsMoreThanTheLimitInARow() {
        var gate = AdaptiveGate(config: .init(maxSkippedInARow: 3))
        for _ in 0..<10 { _ = gate.shouldAnalyze(level: 0.01) }
        XCTAssertTrue(gate.shouldAnalyze(level: 0.1))  // a song resets the run of skips
        let decisions = (0..<8).map { _ in gate.shouldAnalyze(level: 0.01) }
        XCTAssertEqual(decisions, [false, false, false, true, false, false, false, true])
    }

    func testSilenceIsAlwaysSkipped() {
        var gate = AdaptiveGate()
        XCTAssertFalse(gate.shouldAnalyze(level: 0))  // even before learning
        for _ in 0..<10 { _ = gate.shouldAnalyze(level: 0.00001) }
        XCTAssertFalse(gate.shouldAnalyze(level: 0.00001))
    }

    func testFloorFollowsTheBackgroundDown() {
        var gate = AdaptiveGate(config: .init(floorWindow: 10))
        for _ in 0..<10 { _ = gate.shouldAnalyze(level: 0.05) }  // next to traffic
        for _ in 0..<10 { _ = gate.shouldAnalyze(level: 0.005) }  // into the quiet woods
        XCTAssertEqual(gate.noiseFloor, 0.005)
        XCTAssertTrue(gate.shouldAnalyze(level: 0.012))  // a quiet song now counts
    }
}
