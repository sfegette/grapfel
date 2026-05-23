#!/usr/bin/swift
// generate_icon.swift — run from repo root: swift Scripts/generate_icon.swift
//
// Regenerates the 10 AppIcon.appiconset PNGs by downsampling from
// Resources/AppIcon-master.png (the 1024×1024 master).
//
// Replaces the previous version that drew the icon from CoreGraphics primitives.
// To change the artwork: edit the master SVG in Resources/grapfel-icon-master.svg,
// re-export to PNG at 1024×1024, drop it in as AppIcon-master.png, then re-run.

import AppKit
import CoreGraphics

let masterPath  = "grapfel/Resources/AppIcon-master.png"
let outputDir   = "grapfel/Resources/Assets.xcassets/AppIcon.appiconset"

struct IconEntry {
    let logicalSize: String   // e.g. "16x16"
    let scale: String         // "1x" or "2x"
    let pixels: Int
    var filename: String { "AppIcon-\(logicalSize)@\(scale).png" }
}

let entries: [IconEntry] = [
    .init(logicalSize: "16x16",   scale: "1x", pixels: 16),
    .init(logicalSize: "16x16",   scale: "2x", pixels: 32),
    .init(logicalSize: "32x32",   scale: "1x", pixels: 32),
    .init(logicalSize: "32x32",   scale: "2x", pixels: 64),
    .init(logicalSize: "128x128", scale: "1x", pixels: 128),
    .init(logicalSize: "128x128", scale: "2x", pixels: 256),
    .init(logicalSize: "256x256", scale: "1x", pixels: 256),
    .init(logicalSize: "256x256", scale: "2x", pixels: 512),
    .init(logicalSize: "512x512", scale: "1x", pixels: 512),
    .init(logicalSize: "512x512", scale: "2x", pixels: 1024),
]

// ── Load master ──────────────────────────────────────────────────────────────
guard let masterImage = NSImage(contentsOfFile: masterPath) else {
    fputs("✗ Could not load master at \(masterPath)\n", stderr)
    exit(1)
}
guard let masterCGRef = masterImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("✗ Could not get CGImage from master\n", stderr)
    exit(1)
}
print("✓ Loaded master \(masterCGRef.width)×\(masterCGRef.height)")

// ── Downsample helper (high-quality bicubic via Core Graphics) ──────────────
func downsample(_ src: CGImage, to pixels: Int) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create CGContext at \(pixels)px") }
    ctx.interpolationQuality = .high
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let out = ctx.makeImage()!
    let ns  = NSImage(cgImage: out, size: NSSize(width: pixels, height: pixels))
    let bmp = NSBitmapImageRep(data: ns.tiffRepresentation!)!
    return bmp.representation(using: .png, properties: [:])!
}

// ── Generate PNGs ────────────────────────────────────────────────────────────
let fm = FileManager.default
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
for entry in entries {
    let data = downsample(masterCGRef, to: entry.pixels)
    let path = "\(outputDir)/\(entry.filename)"
    try! data.write(to: URL(fileURLWithPath: path))
    print("✓  \(entry.filename)  (\(entry.pixels)×\(entry.pixels)px)")
}

// ── Write Contents.json ──────────────────────────────────────────────────────
var images: [[String: String]] = []
for entry in entries {
    images.append([
        "filename": entry.filename,
        "idiom":    "mac",
        "scale":    entry.scale,
        "size":     entry.logicalSize,
    ])
}
let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1],
]
let json = try! JSONSerialization.data(
    withJSONObject: contents,
    options: [.prettyPrinted, .sortedKeys]
)
try! json.write(to: URL(fileURLWithPath: "\(outputDir)/Contents.json"))
print("\n✓  Contents.json updated")
print("\nDone — rebuild in Xcode to pick up the new icon.")
