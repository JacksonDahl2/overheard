// Cuts each drawn bird out of its white background into a transparent PNG.
//
// Usage (from the repo root):
//   swift art/birds/cutout.swift art/birds/out/raw art/birds/cutouts [--size 768] [--only norcar,blujay]
//
// For each image:
//   1. Lift the subject (bird and perch) with Vision, the same as "lift subject" in Photos.
//      It runs on the Mac, with no model to download.
//   2. Scale the long side down to --size.
//   3. Defringe the soft edges: the art was drawn on white, so a half-transparent edge pixel is
//      part bird, part white paper. Removing the white avoids a pale halo on dark pages.
//   4. Write a PNG.
//
// Birds that already have a cutout are skipped, unless they're named in --only.

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let context = CIContext()
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

struct CutoutError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

// MARK: - Steps

/// Step 1: the image with everything but its subjects transparent, cropped to them.
func liftSubject(from url: URL) throws -> CIImage {
    let handler = VNImageRequestHandler(url: url)
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])

    guard let result = request.results?.first, !result.allInstances.isEmpty else {
        throw CutoutError("no subject found")
    }

    let masked = try result.generateMaskedImage(
        ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
    return CIImage(cvPixelBuffer: masked)
}

/// Step 2: scaled so its long side is at most `maxSize` (never scaled up).
func scaled(_ image: CIImage, maxSize: Double) -> CIImage {
    let scale = min(1, maxSize / max(image.extent.width, image.extent.height))
    guard scale < 1 else { return image }

    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(scale, forKey: kCIInputScaleKey)
    filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    return filter.outputImage!
}

/// Step 3: takes the white paper out of half-transparent edge pixels (RGBA8, premultiplied).
///
/// A pixel that looks like `seen` at coverage `a` was mixed with white: seen = a·bird + (1 − a)·white.
/// So in premultiplied terms the bird's share is `seen − (1 − a)`.
func defringe(_ pixels: inout [UInt8]) {
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Double(pixels[i + 3]) / 255
        guard alpha > 0, alpha < 1 else { continue }  // fully clear or fully bird: nothing to fix

        for channel in 0..<3 {
            let seen = Double(pixels[i + channel]) / 255 / alpha  // un-premultiply
            let bird = (seen - (1 - alpha)) * alpha  // remove white, premultiply again
            pixels[i + channel] = UInt8((max(0, min(alpha, bird)) * 255).rounded())
        }
    }
}

/// Step 4: renders `image`, defringes it, and writes it as a PNG.
func writePNG(_ image: CIImage, to url: URL) throws {
    let width = Int(image.extent.width)
    let height = Int(image.extent.height)

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    context.render(
        image, toBitmap: &pixels, rowBytes: width * 4, bounds: image.extent, format: .RGBA8, colorSpace: sRGB)

    defringe(&pixels)

    let cgImage = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: sRGB, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: true,
        intent: .defaultIntent)!

    guard let file = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CutoutError("can't create \(url.path)")
    }
    CGImageDestinationAddImage(file, cgImage, nil)
    guard CGImageDestinationFinalize(file) else {
        throw CutoutError("can't write \(url.path)")
    }
}

// MARK: - Run

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: swift cutout.swift <raw dir> <out dir> [--size 768] [--only a,b]")
    exit(2)
}

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: "--\(name)"), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let rawDir = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])
let maxSize = option("size").flatMap(Double.init) ?? 768
let only = option("only").map { Set($0.split(separator: ",").map(String.init)) }

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let images = try FileManager.default.contentsOfDirectory(at: rawDir, includingPropertiesForKeys: nil)
    .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

/// Whether this bird needs a (new) cutout.
func shouldCut(_ code: String, output: URL) -> Bool {
    if let only { return only.contains(code) }
    return !FileManager.default.fileExists(atPath: output.path)
}

var failed = 0

for image in images {
    let code = image.deletingPathExtension().lastPathComponent
    let output = outDir.appendingPathComponent("\(code).png")
    guard shouldCut(code, output: output) else { continue }

    do {
        let bird = scaled(try liftSubject(from: image), maxSize: maxSize)
        try writePNG(bird, to: output)
        print("✓ \(code) \(Int(bird.extent.width))×\(Int(bird.extent.height))")
    } catch {
        failed += 1
        print("✗ \(code): \(error.localizedDescription)")
    }
}

exit(failed == 0 ? 0 : 1)
