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
    modelURL = try await MLModel.compileModel(at: URL(fileURLWithPath: modelPath))
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
    let samples: [Float]
    do {
        samples = try AudioDecoding.load48kMono(url)
    } catch {
        skipped.append("\(recording.file) (\(error.localizedDescription))")
        continue
    }
    let clips = AudioDecoding.clips(samples)
    var maxConfidence = [Float](repeating: 0, count: classifier.labels.count)
    for clip in clips {
        for (i, c) in try classifier.confidences(for: clip).enumerated() where c > maxConfidence[i] {
            maxConfidence[i] = c
        }
    }
    clipsTotal += clips.count
    let date = recording.date.flatMap(dateParser.date(from:)) ?? defaultDate
    scored.append(
        Scored(
            recording: recording,
            name: (recording.file as NSString).lastPathComponent,
            target: recording.species.flatMap { indexByScientific[$0] },
            background: Set((recording.also ?? []).compactMap { indexByScientific[$0] }),
            expected: classifier.expectedSpecies(on: date) ?? [],
            maxConfidence: maxConfidence,
            clips: clips.count))
}

// MARK: - Metrics

struct Row: Encodable {
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

let birds = scored.filter { $0.recording.kind == .bird }
let noise = scored.filter { $0.recording.kind == .noise }
let thresholds: [Float] = [0.25, 0.35, 0.5, 0.65, 0.8]
var rows: [Row] = []

for filtered in [false, true] {
    for t in thresholds {
        var hits = 0
        var falseSpecies = 0
        var falseInBirdFiles = 0
        var noisy = 0
        var nonBirdHits = 0
        for s in birds {
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
        rows.append(
            Row(
                threshold: t, filtered: filtered,
                recall: birds.isEmpty ? 0 : Double(hits) / Double(birds.count),
                precision: hits + falseSpecies == 0 ? 0 : Double(hits) / Double(hits + falseSpecies),
                falsePerBirdFile: birds.isEmpty ? 0 : Double(falseInBirdFiles) / Double(birds.count),
                noiseFilesWithBirds: noise.isEmpty ? 0 : Double(noisy) / Double(noise.count),
                nonBirdHits: nonBirdHits))
    }
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
    for s in scored {
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
    try encoder.encode(rows).write(to: URL(fileURLWithPath: jsonOut))
    print("\nWrote \(jsonOut)")
}
