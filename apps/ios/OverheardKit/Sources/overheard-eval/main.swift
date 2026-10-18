// Runs the app's BirdNET pipeline over labeled recordings and reports detection quality.
//
// From the repo root:
//   swift run -c release --package-path apps/ios/OverheardKit overheard-eval [--verbose] [--json out.json]
//
// Inputs (defaults relative to the current directory):
//   --manifest ml/eval/manifest.json            (from ml/eval/fetch.py)
//   --model    ml/models/coreml/BirdNETAudio.mlpackage
//   --labels   ml/models/coreml/labels.txt
//   --species  ml/models/coreml/species-central-park.json

import CoreML
import Foundation
import OverheardKit

// MARK: - Arguments

func argument(_ name: String, default value: String) -> String {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count { return args[i + 1] }
    return value
}
let verbose = CommandLine.arguments.contains("--verbose")
let jsonOut = CommandLine.arguments.contains("--json") ? argument("json", default: "") : nil
let manifestURL = URL(fileURLWithPath: argument("manifest", default: "ml/eval/manifest.json"))
let modelPath = argument("model", default: "ml/models/coreml/BirdNETAudio.mlpackage")
let labelsURL = URL(fileURLWithPath: argument("labels", default: "ml/models/coreml/labels.txt"))
let speciesURL = URL(fileURLWithPath: argument("species", default: "ml/models/coreml/species-central-park.json"))

// MARK: - Manifest

struct Recording: Decodable {
    let file: String
    let kind: Kind  // a focal bird recording, or a no-bird noise clip
    let species: String?  // scientific name of the target bird
    let also: [String]?  // background species the recordist listed
    let date: String?  // yyyy-MM-dd, picks the location-filter week
    let category: String?  // noise category, e.g. "siren"

    enum Kind: String, Decodable { case bird, noise }
}
struct Manifest: Decodable { let recordings: [Recording] }

// MARK: - Run the model

let modelURL: URL
if modelPath.hasSuffix(".mlpackage") || modelPath.hasSuffix(".mlmodel") {
    modelURL = try MLModel.compileModel(at: URL(fileURLWithPath: modelPath))
} else {
    modelURL = URL(fileURLWithPath: modelPath)
}
let classifier = try BirdClassifier(modelURL: modelURL, labelsURL: labelsURL, speciesURL: speciesURL)
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
let baseDir = manifestURL.deletingLastPathComponent()

let indexByScientific = Dictionary(
    classifier.labels.enumerated().map { ($1.scientific, $0) }, uniquingKeysWith: { first, _ in first })
// BirdNET's non-bird classes repeat the same text on both sides of the "_" (e.g. "Engine_Engine").
let nonBird = Set(classifier.labels.enumerated().filter { $1.scientific == $1.common }.map(\.offset))

let dateParser = DateFormatter()
dateParser.dateFormat = "yyyy-MM-dd"
dateParser.timeZone = TimeZone(identifier: "America/New_York")
let defaultDate = dateParser.date(from: "2026-10-18")!

struct Scored {
    let recording: Recording
    let name: String
    let condition: String  // "clean", or the city-noise mix level, e.g. "+10 dB"
    let target: Int?
    let background: Set<Int>
    let expected: Set<Int>
    let maxConfidence: [Float]  // per label, max over clips
    let clips: Int
}

var scored: [Scored] = []
var skipped: [String] = []
let started = Date()
var clipsTotal = 0

// Bird-to-noise levels (SNR) for mixing city noise into each bird recording.
// +10 dB: bird clearly louder · 0 dB: equally loud · -5 dB: noise louder.
let mixLevels: [Float] = CommandLine.arguments.contains("--no-mix") ? [] : [10, 0, -5]

func maxConfidences(_ samples: [Float]) throws -> (scores: [Float], clips: Int) {
    let clips = AudioDecoding.clips(samples)
    var best = [Float](repeating: 0, count: classifier.labels.count)
    for clip in clips {
        for (i, c) in try classifier.confidences(for: clip).enumerated() where c > best[i] { best[i] = c }
    }
    clipsTotal += clips.count
    return (best, clips.count)
}

func rms(_ x: [Float]) -> Float {
    guard !x.isEmpty else { return 0 }
    var sum: Float = 0
    for s in x { sum += s * s }
    return (sum / Float(x.count)).squareRoot()
}

/// A continuous city-noise bed: noise clips back to back, starting at a different clip per recording.
func noiseBed(length: Int, startingAt offset: Int, from clips: [[Float]]) -> [Float] {
    var bed: [Float] = []
    bed.reserveCapacity(length)
    var i = offset
    while bed.count < length {
        bed.append(contentsOf: clips[i % clips.count].prefix(length - bed.count))
        i += 1
    }
    return bed
}

/// Mixes `noise` under `bird` so the bird is `snr` dB louder (RMS), then prevents clipping.
func mix(_ bird: [Float], _ noise: [Float], snr: Float) -> [Float] {
    let gain = rms(bird) / (max(rms(noise), 1e-9) * pow(10, snr / 20))
    var out = zip(bird, noise).map { $0 + gain * $1 }
    let peak = out.map(abs).max() ?? 0
    if peak > 1 { out = out.map { $0 / peak } }
    return out
}

// Decode everything first: noise clips double as the beds for mixing.
var decoded: [(Recording, [Float])] = []
for recording in manifest.recordings {
    let url = baseDir.appendingPathComponent(recording.file)
    guard FileManager.default.fileExists(atPath: url.path) else {
        skipped.append("\(recording.file) (missing; run ml/eval/fetch.py)")
        continue
    }
    if recording.kind == .bird, recording.species.flatMap({ indexByScientific[$0] }) == nil {
        skipped.append("\(recording.file) (\(recording.species ?? "no species") isn't a BirdNET label)")
        continue
    }
    do {
        decoded.append((recording, try AudioDecoding.load48kMono(url)))
    } catch {
        skipped.append("\(recording.file) (\(error.localizedDescription))")
    }
}
let noiseClips = decoded.filter { $0.0.kind == .noise }.map(\.1).filter { rms($0) > 0 }

for (n, (recording, samples)) in decoded.enumerated() {
    let date = recording.date.flatMap(dateParser.date(from:)) ?? defaultDate
    func record(_ condition: String, _ audio: [Float]) throws {
        let (best, clips) = try maxConfidences(audio)
        scored.append(
            Scored(
                recording: recording,
                name: (recording.file as NSString).lastPathComponent,
                condition: condition,
                target: recording.species.flatMap { indexByScientific[$0] },
                background: Set((recording.also ?? []).compactMap { indexByScientific[$0] }),
                expected: classifier.expectedSpecies(on: date) ?? [],
                maxConfidence: best,
                clips: clips))
    }
    try record("clean", samples)
    guard recording.kind == .bird, !noiseClips.isEmpty else { continue }
    let bed = noiseBed(length: samples.count, startingAt: n, from: noiseClips)
    for snr in mixLevels {
        try record(String(format: "%+.0f dB", snr), mix(samples, bed, snr: snr))
    }
}

// MARK: - Metrics

struct Row: Encodable {
    let condition: String
    let threshold: Float
    let filtered: Bool
    let recall: Double  // bird files whose target was detected
    let precision: Double  // correct species / all species reported, over every file
    let falsePerBirdFile: Double
    let noiseFilesWithBirds: Double  // share of noise clips where any species was reported
    let nonBirdHits: Int  // reports of non-bird labels (Engine, Dog, …)
}

func detected(_ s: Scored, threshold: Float, filtered: Bool) -> Set<Int> {
    var out = Set<Int>()
    for (i, c) in s.maxConfidence.enumerated() where c >= threshold {
        if filtered, !s.expected.contains(i) { continue }
        out.insert(i)
    }
    return out
}

let allBirds = scored.filter { $0.recording.kind == .bird }
let birds = allBirds.filter { $0.condition == "clean" }
let noise = scored.filter { $0.recording.kind == .noise }
let conditions = ["clean"] + mixLevels.map { String(format: "%+.0f dB", $0) }
let thresholds: [Float] = [0.25, 0.35, 0.5, 0.65, 0.8]

/// Metrics over one set of bird recordings, plus the noise clips (clean only).
func metrics(_ condition: String, _ birdSet: [Scored], threshold t: Float, filtered: Bool) -> Row {
    var hits = 0
    var falseSpecies = 0
    var falseInBirdFiles = 0
    var noisy = 0
    var nonBirdHits = 0
    for s in birdSet {
        let d = detected(s, threshold: t, filtered: filtered)
        if let target = s.target, d.contains(target) { hits += 1 }
        let wrong = d.subtracting(s.background).subtracting(s.target.map { [$0] } ?? [])
        falseSpecies += wrong.count
        falseInBirdFiles += wrong.count
        nonBirdHits += d.intersection(nonBird).count
    }
    for s in noise {
        let d = detected(s, threshold: t, filtered: filtered)
        falseSpecies += d.count
        if !d.subtracting(nonBird).isEmpty { noisy += 1 }
        nonBirdHits += d.intersection(nonBird).count
    }
    return Row(
        condition: condition, threshold: t, filtered: filtered,
        recall: birdSet.isEmpty ? 0 : Double(hits) / Double(birdSet.count),
        precision: hits + falseSpecies == 0 ? 0 : Double(hits) / Double(hits + falseSpecies),
        falsePerBirdFile: birdSet.isEmpty ? 0 : Double(falseInBirdFiles) / Double(birdSet.count),
        noiseFilesWithBirds: noise.isEmpty ? 0 : Double(noisy) / Double(noise.count),
        nonBirdHits: nonBirdHits)
}

var rows: [Row] = []
for filtered in [false, true] {
    for t in thresholds { rows.append(metrics("clean", birds, threshold: t, filtered: filtered)) }
}
var mixedRows: [Row] = []
for condition in conditions.dropFirst() {
    let set = allBirds.filter { $0.condition == condition }
    for t in thresholds { mixedRows.append(metrics(condition, set, threshold: t, filtered: true)) }
}

// MARK: - Report

func pct(_ x: Double) -> String { String(format: "%5.1f%%", x * 100) }
let elapsed = Date().timeIntervalSince(started)

print(
    "Overheard eval · \(birds.count) bird recordings, \(noise.count) noise clips, \(clipsTotal) clips"
        + String(
            format: " in %.1f s (%.1f ms/clip incl. decoding)\n", elapsed, elapsed * 1000 / Double(max(clipsTotal, 1))))
print("filter  thresh  recall  precision  false/bird-file  noise→bird  non-bird hits")
for r in rows {
    print(
        String(
            format: "%-6@  %5.2f  %@  %@     %6.2f        %@        %d",
            r.filtered ? "on" : "off", r.threshold, pct(r.recall), pct(r.precision), r.falsePerBirdFile,
            pct(r.noiseFilesWithBirds), r.nonBirdHits))
}
print("\nrecall = target bird found · precision = right species / all species reported (bird + noise files)")
print("Non-bird labels (Engine, Dog, …) currently count as false positives, matching the app today.")

if !mixedRows.isEmpty {
    print("\nWith city noise mixed in (filter on; +10 dB = bird louder, -5 dB = noise louder):")
    print("noise    thresh  recall  precision  false/bird-file")
    let cleanOn = rows.filter(\.filtered)
    for r in cleanOn + mixedRows {
        print(
            String(
                format: "%-7@  %5.2f  %@  %@     %6.2f", r.condition, r.threshold, pct(r.recall), pct(r.precision),
                r.falsePerBirdFile))
    }
}

// Per-species recall at 0.5, filter on.
var perSpecies: [String: (hits: Int, total: Int)] = [:]
for s in birds {
    guard let target = s.target else { continue }
    let name = classifier.labels[target].common
    let hit = detected(s, threshold: 0.5, filtered: true).contains(target)
    perSpecies[name, default: (0, 0)].total += 1
    if hit { perSpecies[name, default: (0, 0)].hits += 1 }
}
if !perSpecies.isEmpty {
    print("\nPer species (threshold 0.50, filter on):")
    for (name, v) in perSpecies.sorted(by: { $0.key < $1.key }) {
        print("  \(name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(v.hits)/\(v.total)")
    }
}

if verbose {
    print("\nPer recording (threshold 0.50, filter off; ✓ = target found):")
    for s in scored where s.condition == "clean" {
        let d = detected(s, threshold: 0.5, filtered: false)
        let label: String
        if let target = s.target {
            let mark = d.contains(target) ? "✓" : "✗"
            label = "\(mark) \(classifier.labels[target].common) \(Int(s.maxConfidence[target] * 100))%"
        } else {
            label = "noise: \(s.recording.category ?? "?")"
        }
        let wrong = d.subtracting(s.background).subtracting(s.target.map { [$0] } ?? [])
            .sorted { s.maxConfidence[$0] > s.maxConfidence[$1] }
            .prefix(4)
            .map { "\(classifier.labels[$0].common) \(Int(s.maxConfidence[$0] * 100))%" }
        let extra = wrong.isEmpty ? "" : "  · also reported: " + wrong.joined(separator: ", ")
        print("  \(s.name.padding(toLength: 28, withPad: " ", startingAt: 0)) \(label)\(extra)")
    }
}

if !skipped.isEmpty {
    print("\nSkipped \(skipped.count):")
    for s in skipped { print("  \(s)") }
}

if let jsonOut, !jsonOut.isEmpty {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(rows + mixedRows).write(to: URL(fileURLWithPath: jsonOut))
    print("\nWrote \(jsonOut)")
}
