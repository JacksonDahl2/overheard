// Runs the app's detection pipeline over labeled recordings and reports detection quality.
//
// From the repo root:
//   swift run -c release --package-path apps/ios/OverheardKit overheard-eval [--verbose] [--json out.json] [--no-mix]
//     [--hop 1]   seconds between clip starts (the app uses 1: a 3 s clip every second)
//
// Inputs (defaults relative to the current directory):
//   --manifest       ml/eval/manifest.json                     (from ml/eval/fetch.py)
//   --audio-model    ml/models/coreml/BirdNETAudio.mlpackage
//   --location-model ml/models/coreml/BirdNETMeta.mlpackage
//   --catalog        ml/models/coreml/species.json
//
// Each recording is scored with the location model at the place and week it was recorded,
// and its clips are played through DetectionSession, exactly like a live session.

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

func compiled(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    return path.hasSuffix(".mlmodelc") ? url : try MLModel.compileModel(at: url)
}
let catalog = try SpeciesCatalog(
    contentsOf: URL(fileURLWithPath: argument("catalog", default: "ml/models/coreml/species.json")))
let classifier = try BirdClassifier(
    modelURL: compiled(argument("audio-model", default: "ml/models/coreml/BirdNETAudio.mlpackage")),
    catalog: catalog)
let locationModel = try LocationModel(
    modelURL: compiled(argument("location-model", default: "ml/models/coreml/BirdNETMeta.mlpackage")))

// MARK: - Manifest

struct Recording: Decodable {
    let file: String
    let kind: Kind  // a focal bird recording, or a no-bird noise clip
    let species: String?  // scientific name of the target bird
    let also: [String]?  // background species the recordist listed
    let date: String?  // yyyy-MM-dd → location-model week
    let lat: Double?
    let lon: Double?
    let category: String?  // noise category, e.g. "siren"

    enum Kind: String, Decodable { case bird, noise }
}
struct Manifest: Decodable { let recordings: [Recording] }

let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
let baseDir = manifestURL.deletingLastPathComponent()

let dateParser = DateFormatter()
dateParser.dateFormat = "yyyy-MM-dd"
dateParser.timeZone = TimeZone(identifier: "America/New_York")
let defaultDate = dateParser.date(from: "2026-10-18")!
let centralPark = (lat: 40.7812, lon: -73.9665)  // for noise clips, which have no location

@MainActor func codes(forScientific names: [String]) -> Set<String> {
    Set(names.flatMap { catalog.indices(scientificName: $0) }.map { catalog[$0].code })
}
@MainActor func displayName(_ recording: Recording) -> String {
    (recording.file as NSString).lastPathComponent.padding(toLength: 28, withPad: " ", startingAt: 0)
}

// MARK: - Audio helpers

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

// MARK: - Scoring

// Bird-to-noise levels (SNR) for mixing city noise into each bird recording.
// +10 dB: bird clearly louder · 0 dB: equally loud · -5 dB: noise louder.
let mixLevels: [Float] = CommandLine.arguments.contains("--no-mix") ? [] : [10, 0, -5]
let hopSeconds = Double(argument("hop", default: "1")) ?? 1
let hopSamples = Int(hopSeconds * BirdClassifier.sampleRate)
// Back-to-back clips (and one missed clip) stay one call at any hop.
let callGap = max(DetectionSession.defaultCallGap, hopSeconds * 2.5)
let conditions = ["clean"] + mixLevels.map { String(format: "%+.0f dB", $0) }
let thresholds: [Float] = [0.25, 0.35, 0.5, 0.65, 0.8]

// Confirmation rules to compare. The main tables use the app's default.
let confirmationRules: [(name: String, rule: Confirmation)] = [
    ("none", .none),
    ("2 clips", Confirmation(minClips: 2, strongConfidence: 2)),
    ("2 clips or 0.90", Confirmation(minClips: 2, strongConfidence: 0.9)),
    ("2 clips or 0.80", Confirmation(minClips: 2, strongConfidence: 0.8)),
    ("2 clips or 0.70", Confirmation(minClips: 2, strongConfidence: 0.7)),
    ("3 clips or 0.80", Confirmation(minClips: 3, strongConfidence: 0.8)),
]
let defaultRule = confirmationRules.first { $0.rule == Confirmation() }!.name

struct Key: Hashable {
    let condition: String
    let filtered: Bool
    let threshold: Float
    var rule = defaultRule
}
struct Counts {
    var birdFiles = 0
    var hits = 0
    var falseInBirdFiles = 0
    var noiseFiles = 0
    var falseInNoise = 0
    var noiseFilesWithBirds = 0
    var nonBirdDropped = 0
}
var counts: [Key: Counts] = [:]
var perSpecies: [String: (hits: Int, total: Int)] = [:]  // clean, filter on, 0.50
var firstDetection: [String: [Double]] = [:]  // condition → seconds into the recording (filter on, 0.50)
var callCounts: [String: [Int]] = [:]  // condition → target's calls per recording where it was found
var details: [String] = []  // --verbose lines (clean, filter off, 0.50)
var skipped: [String] = []
var clipsTotal = 0
let started = Date()

/// Each clip's reportable birds under `rules` (computed once, then replayed per confirmation rule).
@MainActor func reportable(_ clipConfidences: [[Float]], local: LocalSpecies, rules: DetectionRules) -> [[BirdScore]] {
    clipConfidences.map { classifier.reportable($0, local: local, rules: rules) }
}

/// Plays per-clip scores through a fresh DetectionSession, as the app would live. Clip `i` ends
/// `3 + i × hop` seconds into the recording. Returns the confirmed birds.
@MainActor func heard(_ scoresPerClip: [[BirdScore]], confirmation: Confirmation) -> [String: HeardBird] {
    var session = DetectionSession(callGap: callGap, confirmation: confirmation)
    for (i, scores) in scoresPerClip.enumerated() {
        session.record(scores, at: defaultDate.addingTimeInterval(3 + Double(i) * hopSeconds))
    }
    return session.byCode
}

@MainActor func score(_ audio: [Float]) throws -> [[Float]] {
    let clips = AudioDecoding.clips(audio, hop: hopSamples)
    clipsTotal += clips.count
    return try clips.map { try classifier.confidences(for: $0) }
}

@MainActor func nonBirdsFired(_ clipConfidences: [[Float]], threshold: Float) -> Int {
    catalog.nonBird.filter { i in clipConfidences.contains { $0[i] >= threshold } }.count
}

@MainActor func decode(_ recording: Recording) -> [Float]? {
    let url = baseDir.appendingPathComponent(recording.file)
    guard FileManager.default.fileExists(atPath: url.path) else {
        skipped.append("\(recording.file) (missing; run ml/eval/fetch.py)")
        return nil
    }
    do {
        return try AudioDecoding.load48kMono(url)
    } catch {
        skipped.append("\(recording.file) (\(error.localizedDescription))")
        return nil
    }
}

// Noise clips first: they're short, and double as the beds for mixing.
var noiseAudio: [[Float]] = []
let noiseLocal = try locationModel.localSpecies(
    at: Place(latitude: centralPark.lat, longitude: centralPark.lon, date: defaultDate))
for recording in manifest.recordings where recording.kind == .noise {
    guard let audio = decode(recording) else { continue }
    if rms(audio) > 0 { noiseAudio.append(audio) }
    let clipConfidences = try score(audio)
    for filtered in [false, true] {
        for t in thresholds {
            let rules = DetectionRules(minConfidence: t, useLocationFilter: filtered)
            let scoresPerClip = reportable(clipConfidences, local: noiseLocal, rules: rules)
            let nonBirds = nonBirdsFired(clipConfidences, threshold: t)
            for (ruleName, rule) in confirmationRules {
                let found = heard(scoresPerClip, confirmation: rule)
                for condition in conditions {  // noise false positives count against every condition
                    let key = Key(condition: condition, filtered: filtered, threshold: t, rule: ruleName)
                    var c = counts[key] ?? Counts()
                    c.noiseFiles += 1
                    c.falseInNoise += found.count
                    c.noiseFilesWithBirds += found.isEmpty ? 0 : 1
                    c.nonBirdDropped += nonBirds
                    counts[key] = c
                }
                if verbose, !filtered, t == 0.5, ruleName == defaultRule {
                    let names = found.values.map(\.species.commonName)
                    let extra = names.isEmpty ? "" : "  · reported: " + names.joined(separator: ", ")
                    details.append("  \(displayName(recording)) noise: \(recording.category ?? "?")\(extra)")
                }
            }
        }
    }
}

// Bird recordings one at a time, so memory stays flat as the set grows.
for (n, recording) in manifest.recordings.enumerated() where recording.kind == .bird {
    let targetIndex = catalog.indices(scientificName: recording.species ?? "").first
    guard let targetIndex else {
        skipped.append("\(recording.file) (\(recording.species ?? "no species") isn't in the catalog)")
        continue
    }
    guard let audio = decode(recording) else { continue }
    let target = codes(forScientific: [recording.species!])
    let background = codes(forScientific: recording.also ?? [])
    let date = recording.date.flatMap(dateParser.date(from:)) ?? defaultDate
    let place = Place(
        latitude: recording.lat ?? centralPark.lat, longitude: recording.lon ?? centralPark.lon, date: date)
    let local = try locationModel.localSpecies(at: place)
    let bed = noiseAudio.isEmpty ? nil : noiseBed(length: audio.count, startingAt: n, from: noiseAudio)

    for (c, condition) in conditions.enumerated() {
        guard c == 0 || bed != nil else { continue }
        let clipConfidences = try score(c == 0 ? audio : mix(audio, bed!, snr: mixLevels[c - 1]))
        for filtered in [false, true] {
            for t in thresholds {
                let scoresPerClip = reportable(
                    clipConfidences, local: local, rules: DetectionRules(minConfidence: t, useLocationFilter: filtered))
                let nonBirds = nonBirdsFired(clipConfidences, threshold: t)
                for (ruleName, rule) in confirmationRules {
                    let found = heard(scoresPerClip, confirmation: rule)
                    let codesFound = Set(found.keys)
                    let hit = !codesFound.isDisjoint(with: target)
                    let key = Key(condition: condition, filtered: filtered, threshold: t, rule: ruleName)
                    var counted = counts[key] ?? Counts()
                    counted.birdFiles += 1
                    counted.hits += hit ? 1 : 0
                    counted.falseInBirdFiles += codesFound.subtracting(target).subtracting(background).count
                    counted.nonBirdDropped += nonBirds
                    counts[key] = counted
                    guard ruleName == defaultRule else { continue }

                    if filtered, t == 0.5, let bird = found.values.first(where: { target.contains($0.id) }) {
                        firstDetection[condition, default: []].append(bird.firstHeard.timeIntervalSince(defaultDate))
                        callCounts[condition, default: []].append(bird.calls)
                    }
                    if c == 0, filtered, t == 0.5 {
                        let name = catalog[targetIndex].commonName
                        perSpecies[name, default: (0, 0)].total += 1
                        if hit { perSpecies[name, default: (0, 0)].hits += 1 }
                    }
                    if verbose, c == 0, !filtered, t == 0.5 {
                        let best = clipConfidences.map { $0[targetIndex] }.max() ?? 0
                        let wrong = found.values.filter { !target.contains($0.id) && !background.contains($0.id) }
                            .sorted { $0.bestConfidence > $1.bestConfidence }.prefix(4)
                            .map { "\($0.species.commonName) \(Int($0.bestConfidence * 100))%" }
                        let extra = wrong.isEmpty ? "" : "  · also reported: " + wrong.joined(separator: ", ")
                        details.append(
                            "  \(displayName(recording)) \(hit ? "✓" : "✗") \(catalog[targetIndex].commonName) "
                                + "\(Int(best * 100))%\(extra)")
                    }
                }
            }
        }
    }
}

// MARK: - Report

struct Row: Encodable {
    let condition: String
    let rule: String
    let threshold: Float
    let filtered: Bool
    let recall: Double  // bird recordings whose target species was reported
    let precision: Double  // correct species / all species reported (bird + noise files)
    let falsePerBirdFile: Double
    let noiseFilesWithBirds: Double  // share of noise clips where any bird was reported
    let nonBirdDropped: Int  // non-bird labels (Engine, Dog, frogs, …) that fired and were dropped
}

@MainActor func row(_ key: Key) -> Row {
    let c = counts[key] ?? Counts()
    let reported = c.hits + c.falseInBirdFiles + c.falseInNoise
    return Row(
        condition: key.condition, rule: key.rule, threshold: key.threshold, filtered: key.filtered,
        recall: c.birdFiles == 0 ? 0 : Double(c.hits) / Double(c.birdFiles),
        precision: reported == 0 ? 0 : Double(c.hits) / Double(reported),
        falsePerBirdFile: c.birdFiles == 0 ? 0 : Double(c.falseInBirdFiles) / Double(c.birdFiles),
        noiseFilesWithBirds: c.noiseFiles == 0 ? 0 : Double(c.noiseFilesWithBirds) / Double(c.noiseFiles),
        nonBirdDropped: c.nonBirdDropped)
}

func pct(_ x: Double) -> String { String(format: "%5.1f%%", x * 100) }
let elapsed = Date().timeIntervalSince(started)
let summary = counts[Key(condition: "clean", filtered: true, threshold: 0.5)] ?? Counts()

print(
    "Overheard eval · \(summary.birdFiles) bird recordings, \(summary.noiseFiles) noise clips, \(clipsTotal) clips"
        + String(
            format: " in %.1f s (%.1f ms/clip incl. decoding)", elapsed, elapsed * 1000 / Double(max(clipsTotal, 1))))
print("Location filter: BirdNET's location model at each recording's place and week.")
print(String(format: "Clips: 3 s every %.1f s · calls split after %.1f s without a detection.", hopSeconds, callGap))
print("Confirmation (main tables): \(defaultRule) — the app's default.\n")
print("filter  thresh  recall  precision  false/bird-file  noise→bird  non-bird dropped")
var rows: [Row] = []
for filtered in [false, true] {
    for t in thresholds {
        let r = row(Key(condition: "clean", filtered: filtered, threshold: t))
        rows.append(r)
        print(
            String(
                format: "%-6@  %5.2f  %@  %@     %6.2f        %@        %d", filtered ? "on" : "off", t,
                pct(r.recall), pct(r.precision), r.falsePerBirdFile, pct(r.noiseFilesWithBirds), r.nonBirdDropped))
    }
}
print("\nrecall = target bird found · precision = right species / all species reported (bird + noise files)")
print("Non-bird labels (Engine, Dog, frogs, insects, …) are never reported; \"dropped\" counts how often one fired.")

if conditions.count > 1 {
    print("\nWith city noise mixed in (filter on; +10 dB = bird louder, -5 dB = noise louder):")
    print("noise    thresh  recall  precision  false/bird-file")
    for condition in conditions {
        for t in thresholds {
            let r = row(Key(condition: condition, filtered: true, threshold: t))
            if condition != "clean" { rows.append(r) }
            print(
                String(
                    format: "%-7@  %5.2f  %@  %@     %6.2f", condition, t, pct(r.recall), pct(r.precision),
                    r.falsePerBirdFile))
        }
    }
}

print("\nConfirmation rules (filter on):")
print("rule               noise    thresh  recall  precision  false/bird-file")
for (ruleName, _) in confirmationRules {
    for condition in conditions where condition == "clean" || condition == "+0 dB" {
        for t: Float in [0.35, 0.5] {
            let r = row(Key(condition: condition, filtered: true, threshold: t, rule: ruleName))
            rows.append(r)
            print(
                String(
                    format: "%-17@  %-7@  %5.2f  %@  %@     %6.2f", ruleName, condition, t, pct(r.recall),
                    pct(r.precision), r.falsePerBirdFile))
        }
    }
}

func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return .nan }
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}
print("\nWhen the target bird is found (filter on, 0.50):")
print("noise    first heard (median / mean)   calls per recording (median / max)")
for condition in conditions {
    let times = firstDetection[condition] ?? []
    let calls = (callCounts[condition] ?? []).map(Double.init)
    print(
        String(
            format: "%-7@     %5.1f s / %5.1f s              %5.1f / %3.0f", condition, median(times),
            times.isEmpty ? .nan : times.reduce(0, +) / Double(times.count), median(calls), calls.max() ?? .nan))
}
print("first heard = seconds into the recording when the target was first reported (a clip can't end before 3 s)")

if !perSpecies.isEmpty {
    print("\nPer species (threshold 0.50, filter on):")
    for (name, v) in perSpecies.sorted(by: { $0.key < $1.key }) {
        print("  \(name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(v.hits)/\(v.total)")
    }
}

if verbose {
    print("\nPer recording (clean, threshold 0.50, filter off; ✓ = target found):")
    for line in details { print(line) }
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
