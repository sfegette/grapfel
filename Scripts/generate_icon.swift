#!/usr/bin/swift
// generate_icon.swift — run from repo root: swift Scripts/generate_icon.swift
// Generates all 10 Mac app icon sizes for grapfel.

import AppKit
import CoreGraphics

let outputDir = "grapfel/Resources/Assets.xcassets/AppIcon.appiconset"

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

// Four-pointed star path — first point at top (−π/2), alternating outer/inner radii
func makeStar(center: CGPoint, outer: CGFloat, inner: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 - .pi / 2
        let r: CGFloat = i % 2 == 0 ? outer : inner
        let pt = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.closeSubpath()
    return path
}

func generatePNG(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Could not create CGContext at \(pixels)px") }

    // ── Background: deep navy-indigo #121121 ─────────────────────────────────
    ctx.setFillColor(CGColor(colorSpace: cs, components: [0.071, 0.067, 0.129, 1.0])!)
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // ── Purple radial bloom ───────────────────────────────────────────────────
    let bloomColors = [
        CGColor(colorSpace: cs, components: [0.220, 0.118, 0.435, 0.80])!,
        CGColor(colorSpace: cs, components: [0.071, 0.067, 0.129, 0.00])!,
    ] as CFArray
    let bloomLocs: [CGFloat] = [0, 1]
    if let grad = CGGradient(colorsSpace: cs, colors: bloomColors, locations: bloomLocs) {
        ctx.drawRadialGradient(
            grad,
            startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0,
            endCenter:   CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.55,
            options: []
        )
    }

    // ── Four-pointed star ─────────────────────────────────────────────────────
    //  outer: 37% of canvas — makes the star fill most of the icon face
    //  inner: 6.5% — gives the sharp, elegant taper of the ✦ glyph
    let star = makeStar(
        center: CGPoint(x: s / 2, y: s / 2),
        outer: s * 0.370,
        inner: s * 0.065
    )

    // Violet glow (skip at 16px — too small to matter)
    if pixels >= 32 {
        ctx.saveGState()
        ctx.setShadow(
            offset: .zero,
            blur: s * 0.07,
            color: CGColor(colorSpace: cs, components: [0.788, 0.749, 1.000, 0.85])!
        )
        ctx.setFillColor(CGColor(colorSpace: cs, components: [0.969, 0.961, 1.000, 1.0])!)
        ctx.addPath(star)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Crisp white star on top (ensures clean edges after glow pass)
    ctx.setFillColor(CGColor(colorSpace: cs, components: [0.969, 0.961, 1.000, 1.0])!)
    ctx.addPath(star)
    ctx.fillPath()

    let cgImage = ctx.makeImage()!
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: pixels, height: pixels))
    let tiff = nsImage.tiffRepresentation!
    let bmp  = NSBitmapImageRep(data: tiff)!
    return bmp.representation(using: .png, properties: [:])!
}

// ── Generate PNGs ─────────────────────────────────────────────────────────────
let fm = FileManager.default
for entry in entries {
    let data = generatePNG(pixels: entry.pixels)
    let path = "\(outputDir)/\(entry.filename)"
    try! data.write(to: URL(fileURLWithPath: path))
    print("✓  \(entry.filename)  (\(entry.pixels)×\(entry.pixels)px)")
}

// ── Rewrite Contents.json ─────────────────────────────────────────────────────
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
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(outputDir)/Contents.json"))
print("\n✓  Contents.json updated")
print("\nDone — rebuild in Xcode to pick up the new icon.")
