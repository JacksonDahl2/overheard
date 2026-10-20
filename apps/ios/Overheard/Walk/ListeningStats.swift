import Foundation
import OverheardKit

/// Numbers for field testing (Me → Field-test tools). The walk screens don't show these.
struct ListeningStats {
    /// Every bird above threshold in the latest clip, most confident first.
    var lastClip: [BirdScore] = []
    var level: Float = 0
    var noiseFloor: Float?
    var inferenceMs: Double = 0
    var clipsSeen = 0
    var clipsAnalyzed = 0

    mutating func update(from update: PipelineUpdate) {
        lastClip = update.lastClip
        level = update.level
        noiseFloor = update.noiseFloor
        clipsSeen = update.clipsSeen
        clipsAnalyzed = update.clipsAnalyzed
        if let ms = update.inferenceMs { inferenceMs = ms }
    }
}
