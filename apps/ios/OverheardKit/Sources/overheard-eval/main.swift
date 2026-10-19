// Runs the app's detection pipeline over labeled recordings and reports detection quality.
//
// From the repo root:
//   swift run -c release --package-path apps/ios/OverheardKit overheard-eval [--verbose] [--json out.json] [--no-mix]
//     [--hop 1]   seconds between clip starts (the app uses 1: a 3 s clip every second)
//
// Inputs (defaults relative to the current directory):
//   --manifest       ml/eval/manifest.json,ml/eval/manifest-rare.json   (fetch.py, fetch_rare.py; missing ones skipped)
//   --audio-model    ml/models/coreml/BirdNETAudio.mlpackage
//   --location-model ml/models/coreml/BirdNETMeta.mlpackage
//   --catalog        ml/models/coreml/species.json
//
// Each recording is scored with the location model at the place and week it was recorded,
// and its clips are played through DetectionSession, exactly like a live session.
//
// To try an idea, add a `Variant` (detection rules + confirmation) to `variants` below: every
// variant is scored on every recording and noise condition, and the tables pick variants by tag.

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
let manifestURLs = argument("manifest", default: "ml/eval/manifest.json,ml/eval/manifest-rare.json")
    .split(separator: ",").map { URL(fileURLWithPath: String($0)) }

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
    /// Which eval set it belongs to: nil for the main set, "rare" for unlikely-here birds
    /// (fetch_rare.py). Sets are reported separately so baselines stay comparable.
    let subset: String?
    /// Set when loaded: the manifest's folder, which `file` is relative to.
    var baseDir = URL(fileURLWithPath: ".")

    enum Kind: String, Decodable { case bird, noise }
    enum CodingKeys: String, CodingKey {
        case file, kind, species, also, date, lat, lon, category
        case subset = "set"
    }

    var set: String { subset ?? "main" }
}
struct Manifest: Decodable { let recordings: [Recording] }

let recordings: [Recording] = try manifestURLs.flatMap { url -> [Recording] in
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url)).recordings.map {
        var r = $0
        r.baseDir = url.deletingLastPathComponent()
        return r
    }
}

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

// MARK: - Variants

/// One way of running the pipeline: which detections are reportable, and when a call counts.
struct Variant: Hashable {
    let name: String
    let tags: Set<String>
    let rules: DetectionRules
    let confirmation: Confirmation
}

let thresholds: [Float] = [0.25, 0.35, 0.5, 0.65, 0.8]
let defaultConfirmation = Confirmation()

let confirmationRules: [(name: String, rule: Confirmation)] = [
    ("none", .none),
    ("2 clips", Confirmation(minClips: 2, strongConfidence: 2)),
    ("2 clips or 0.90", Confirmation(minClips: 2, strongConfidence: 0.9)),
    ("2 clips or 0.80", Confirmation(minClips: 2, strongConfidence: 0.8)),
    ("2 clips or 0.70", Confirmation(minClips: 2, strongConfidence: 0.7)),
    ("3 clips or 0.80", Confirmation(minClips: 3, strongConfidence: 0.8)),
]

typealias Tier = ConfidenceBar.Tier
let bars: [(name: String, bar: ConfidenceBar)] = [
    ("hard cutoff (old)", .hardCutoff),
    ("standard +0.20/+0.40", .standard),
    (
        "first try +0.15/+0.30",
        ConfidenceBar(tiers: [
            Tier(minOccurrence: 0.10, extraConfidence: 0, commonness: .common),
            Tier(minOccurrence: 0.03, extraConfidence: 0.15, commonness: .uncommon),
            Tier(minOccurrence: 0.01, extraConfidence: 0.30, commonness: .unusual),
        ])
    ),
    (
        "gentle +0.10/+0.20",
        ConfidenceBar(tiers: [
            Tier(minOccurrence: 0.10, extraConfidence: 0, commonness: .common),
            Tier(minOccurrence: 0.03, extraConfidence: 0.10, commonness: .uncommon),
            Tier(minOccurrence: 0.01, extraConfidence: 0.20, commonness: .unusual),
        ])
    ),
    (
        "wide (unusual ≥0.5%)",
        ConfidenceBar(tiers: [
            Tier(minOccurrence: 0.10, extraConfidence: 0, commonness: .common),
            Tier(minOccurrence: 0.03, extraConfidence: 0.20, commonness: .uncommon),
            Tier(minOccurrence: 0.005, extraConfidence: 0.40, commonness: .unusual),
        ])
    ),
]

let variants: [Variant] = {
    var list: [Variant] = []
    for filtered in [false, true] {
        for t in thresholds {
            list.append(
                Variant(
                    name: "\(filtered ? "on" : "off") \(t)", tags: ["main"],
                    rules: DetectionRules(minConfidence: t, useLocationFilter: filtered),
                    confirmation: defaultConfirmation))
        }
    }
    for (name, rule) in confirmationRules {
        for t: Float in [0.35, 0.5] {
            list.append(
                Variant(
                    name: name, tags: ["confirmation"], rules: DetectionRules(minConfidence: t), confirmation: rule))
        }
    }
    for (name, bar) in bars {
        for t: Float in [0.35, 0.5] {
            list.append(
                Variant(
                    name: name, tags: ["bar"], rules: DetectionRules(minConfidence: t, bar: bar),
                    confirmation: defaultConfirmation))
        }
    }
    return list
}()
/// The app's defaults: per-recording extras (first heard, calls, per species) use this one.
let appDefault = variants.first { $0.tags.contains("main") && $0.rules == DetectionRules() }!

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
let conditions = ["clean"] + mixLevels.map { String(format: "%+.0f dB", $0) }
let hopSeconds = Double(argument("hop", default: "1")) ?? 1
let hopSamples = Int(hopSeconds * BirdClassifier.sampleRate)
// Back-to-back clips (and one missed clip) stay one call at any hop.
let callGap = max(DetectionSession.defaultCallGap, hopSeconds * 2.5)

struct Key: Hashable {
    let condition: String
    let variant: Variant
    var set = "main"
}
struct Counts {
    var birdFiles = 0
    var hits = 0
    var unusualHits = 0  // target found in the "unusual here" tier
    var falseInBirdFiles = 0
    var noiseFiles = 0
    var falseInNoise = 0
    var noiseFilesWithBirds = 0
    var nonBirdDropped = 0
}
var counts: [Key: Counts] = [:]
var perSpecies: [String: (hits: Int, total: Int)] = [:]  // clean, app default
var firstDetection: [String: [Double]] = [:]  // condition → seconds into the recording (app default)
var callCounts: [String: [Int]] = [:]  // condition → target's calls per recording where found
var details: [String] = []  // --verbose lines (clean, app default but filter off)
var skipped: [String] = []
var clipsTotal = 0
let started = Date()

@MainActor func score(_ audio: [Float]) throws -> [[Float]] {
    let clips = AudioDecoding.clips(audio, hop: hopSamples)
    clipsTotal += clips.count
    return try clips.map { try classifier.confidences(for: $0) }
}

/// Runs every variant over one recording's clip confidences. Reportable scores are computed once
/// per rule set and shared by variants that differ only in confirmation.
@MainActor func runVariants(_ clipConfidences: [[Float]], local: LocalSpecies) -> [Variant: [String: HeardBird]] {
    var reportable: [DetectionRules: [[BirdScore]]] = [:]
    var out: [Variant: [String: HeardBird]] = [:]
    for variant in variants {
        let perClip =
            reportable[variant.rules]
            ?? clipConfidences.map { classifier.reportable($0, local: local, rules: variant.rules) }
        reportable[variant.rules] = perClip
        var session = DetectionSession(callGap: callGap, confirmation: variant.confirmation)
        for (i, scores) in perClip.enumerated() {
            session.record(scores, at: defaultDate.addingTimeInterval(3 + Double(i) * hopSeconds))
        }
        out[variant] = session.byCode
    }
    return out
}

@MainActor func nonBirdsFired(_ clipConfidences: [[Float]], threshold: Float) -> Int {
    catalog.nonBird.filter { i in clipConfidences.contains { $0[i] >= threshold } }.count
}

@MainActor func decode(_ recording: Recording) -> [Float]? {
    let url = recording.baseDir.appendingPathComponent(recording.file)
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
for recording in recordings where recording.kind == .noise {
    guard let audio = decode(recording) else { continue }
    if rms(audio) > 0 { noiseAudio.append(audio) }
    let clipConfidences = try score(audio)
    for (variant, found) in runVariants(clipConfidences, local: noiseLocal) {
        let nonBirds = nonBirdsFired(clipConfidences, threshold: variant.rules.minConfidence)
        for condition in conditions {  // noise false positives count against every condition
            let key = Key(condition: condition, variant: variant)
            var c = counts[key] ?? Counts()
            c.noiseFiles += 1
            c.falseInNoise += found.count
            c.noiseFilesWithBirds += found.isEmpty ? 0 : 1
            c.nonBirdDropped += nonBirds
            counts[key] = c
        }
        if verbose, variant.tags.contains("main"), !variant.rules.useLocationFilter,
            variant.rules.minConfidence == appDefault.rules.minConfidence
        {
            let names = found.values.map(\.species.commonName)
            let extra = names.isEmpty ? "" : "  · reported: " + names.joined(separator: ", ")
            details.append("  \(displayName(recording)) noise: \(recording.category ?? "?")\(extra)")
        }
    }
}

// Bird recordings one at a time, so memory stays flat as the set grows.
for (n, recording) in recordings.enumerated() where recording.kind == .bird {
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
        for (variant, found) in runVariants(clipConfidences, local: local) {
            let targetBird = found.values.first { target.contains($0.id) }
            let key = Key(condition: condition, variant: variant, set: recording.set)
            var counted = counts[key] ?? Counts()
            counted.birdFiles += 1
            counted.hits += targetBird == nil ? 0 : 1
            counted.unusualHits += targetBird?.commonness == .unusual ? 1 : 0
            counted.falseInBirdFiles += Set(found.keys).subtracting(target).subtracting(background).count
            counted.nonBirdDropped += nonBirdsFired(clipConfidences, threshold: variant.rules.minConfidence)
            counts[key] = counted
            guard recording.set == "main" else { continue }  // extras describe the main set

            if variant == appDefault, let targetBird {
                firstDetection[condition, default: []].append(targetBird.firstHeard.timeIntervalSince(defaultDate))
                callCounts[condition, default: []].append(targetBird.calls)
            }
            if variant == appDefault, c == 0 {
                let name = catalog[targetIndex].commonName
                perSpecies[name, default: (0, 0)].total += 1
                if targetBird != nil { perSpecies[name, default: (0, 0)].hits += 1 }
            }
            if verbose, c == 0, variant.tags.contains("main"), !variant.rules.useLocationFilter,
                variant.rules.minConfidence == appDefault.rules.minConfidence
            {
                let best = clipConfidences.map { $0[targetIndex] }.max() ?? 0
                let wrong = found.values.filter { !target.contains($0.id) && !background.contains($0.id) }
                    .sorted { $0.bestConfidence > $1.bestConfidence }.prefix(4)
                    .map { "\($0.species.commonName) \(Int($0.bestConfidence * 100))%" }
                let extra = wrong.isEmpty ? "" : "  · also reported: " + wrong.joined(separator: ", ")
                details.append(
                    "  \(displayName(recording)) \(targetBird == nil ? "✗" : "✓") \(catalog[targetIndex].commonName) "
                        + "\(Int(best * 100))%\(extra)")
            }
        }
    }
}

// MARK: - Report

struct Row: Encodable {
    let variant: String
    let tags: [String]
    let condition: String
    let threshold: Float
    let filtered: Bool
    let recall: Double  // bird recordings whose target species was reported
    let precision: Double  // correct species / all species reported (bird + noise files)
    let falsePerBirdFile: Double
    let unusualHits: Int  // targets found in the "unusual here" tier
    let noiseFilesWithBirds: Double  // share of noise clips where any bird was reported
    let nonBirdDropped: Int  // non-bird labels (Engine, Dog, frogs, …) that fired and were dropped
}

@MainActor func row(_ variant: Variant, _ condition: String, set: String = "main") -> Row {
    let c = counts[Key(condition: condition, variant: variant, set: set)] ?? Counts()
    let reported = c.hits + c.falseInBirdFiles + c.falseInNoise
    return Row(
        variant: variant.name, tags: variant.tags.sorted(), condition: condition,
        threshold: variant.rules.minConfidence, filtered: variant.rules.useLocationFilter,
        recall: c.birdFiles == 0 ? 0 : Double(c.hits) / Double(c.birdFiles),
        precision: reported == 0 ? 0 : Double(c.hits) / Double(reported),
        falsePerBirdFile: c.birdFiles == 0 ? 0 : Double(c.falseInBirdFiles) / Double(c.birdFiles),
        unusualHits: c.unusualHits,
        noiseFilesWithBirds: c.noiseFiles == 0 ? 0 : Double(c.noiseFilesWithBirds) / Double(c.noiseFiles),
        nonBirdDropped: c.nonBirdDropped)
}

func pct(_ x: Double) -> String { String(format: "%5.1f%%", x * 100) }
func padded(_ s: String, _ width: Int) -> String { s.padding(toLength: width, withPad: " ", startingAt: 0) }
let elapsed = Date().timeIntervalSince(started)
let summary = counts[Key(condition: "clean", variant: appDefault)] ?? Counts()
var rows: [Row] = []

print(
    "Overheard eval · \(summary.birdFiles) bird recordings, \(summary.noiseFiles) noise clips, \(clipsTotal) clips"
        + String(
            format: " in %.1f s (%.1f ms/clip incl. decoding)", elapsed, elapsed * 1000 / Double(max(clipsTotal, 1))))
print("Location: BirdNET's location model at each recording's place and week; standard confidence bar.")
print(String(format: "Clips: 3 s every %.1f s · calls split after %.1f s without a detection.", hopSeconds, callGap))
print("Confirmation: 2 clips above the bar, or one clip ≥ max(0.70, bar + 0.15).\n")

print("filter  thresh  recall  precision  false/bird-file  unusual hits  noise→bird  non-bird dropped")
for variant in variants where variant.tags.contains("main") {
    let r = row(variant, "clean")
    rows.append(r)
    print(
        String(
            format: "%-6@  %5.2f  %@  %@     %6.2f          %3d        %@        %d", r.filtered ? "on" : "off",
            r.threshold, pct(r.recall), pct(r.precision), r.falsePerBirdFile, r.unusualHits,
            pct(r.noiseFilesWithBirds), r.nonBirdDropped))
}
print("\nrecall = target bird found · precision = right species / all species reported (bird + noise files)")
print("unusual hits = targets found in the \"unusual here\" tier · non-bird labels are never reported")

if conditions.count > 1 {
    print("\nWith city noise mixed in (filter on; +10 dB = bird louder, -5 dB = noise louder):")
    print("noise    thresh  recall  precision  false/bird-file")
    for condition in conditions {
        for variant in variants where variant.tags.contains("main") && variant.rules.useLocationFilter {
            let r = row(variant, condition)
            if condition != "clean" { rows.append(r) }
            print(
                String(
                    format: "%-7@  %5.2f  %@  %@     %6.2f", condition, r.threshold, pct(r.recall), pct(r.precision),
                    r.falsePerBirdFile))
        }
    }
}

/// A sweep table for variants with `tag`, on clean audio and at equal-loudness city noise.
@MainActor func sweep(_ tag: String, _ title: String) {
    print("\n\(title) (filter on):")
    print("\(padded("variant", 22)) noise    thresh  recall  precision  false/bird-file  unusual hits")
    for variant in variants where variant.tags.contains(tag) {
        for condition in conditions where condition == "clean" || condition == "+0 dB" {
            let r = row(variant, condition)
            rows.append(r)
            print(
                String(
                    format: "%@ %-7@  %5.2f  %@  %@     %6.2f          %3d", padded(variant.name, 22), condition,
                    r.threshold, pct(r.recall), pct(r.precision), r.falsePerBirdFile, r.unusualHits))
        }
    }
}
sweep("confirmation", "Confirmation rules")
sweep("bar", "Confidence bars")

// Rare-bird set: birds the location model rated unlikely (1–3%) where and when they were recorded.
// Only bird recordings, so precision here ignores noise clips.
let rareCount = counts[Key(condition: "clean", variant: appDefault, set: "rare")]?.birdFiles ?? 0
if rareCount > 0 {
    print("\nRare-bird set (\(rareCount) recordings of unlikely-here birds; filter on):")
    print("\(padded("variant", 22)) noise    thresh  recall  precision  false/bird-file  unusual hits")
    for variant in variants where variant.tags.contains("bar") || variant == appDefault {
        for condition in conditions where condition == "clean" || condition == "+0 dB" {
            let r = row(variant, condition, set: "rare")
            rows.append(r)
            print(
                String(
                    format: "%@ %-7@  %5.2f  %@  %@     %6.2f          %3d",
                    padded(variant == appDefault ? "app default" : variant.name, 22), condition, r.threshold,
                    pct(r.recall), pct(r.precision), r.falsePerBirdFile, r.unusualHits))
        }
    }
    print("recall here = unlikely-but-real birds reported · the old hard cutoff hides all of them by design")
}

func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    guard !s.isEmpty else { return .nan }
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}
print("\nWhen the target bird is found (app defaults):")
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
    print("\nPer species (app defaults):")
    for (name, v) in perSpecies.sorted(by: { $0.key < $1.key }) {
        print("  \(padded(name, 30)) \(v.hits)/\(v.total)")
    }
}

if verbose {
    print("\nPer recording (clean, app defaults but filter off; ✓ = target found):")
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
