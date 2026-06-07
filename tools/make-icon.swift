#!/usr/bin/env swift
//
// make-icon.swift — render one HermesVoice app-icon PNG at a given pixel size.
//
// Draws the warm-amber identity: a macOS-style rounded-square ("squircle")
// filled with a diagonal amber gradient and a centered cream waveform motif —
// the same voice/waveform language used in the menu-bar glyph and empty state.
//
// Usage:  swift tools/make-icon.swift <out.png> <pixelSize>
// Driven by tools/generate-icns.sh to produce every iconset size.

import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3, let size = Int(args[2]), size > 0 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.png> <pixelSize>\n".utf8))
    exit(1)
}
let outPath = args[1]
let N = CGFloat(size)
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [r / 255, g / 255, b / 255, a])!
}

guard let ctx = CGContext(data: nil,
                          width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: srgb,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high
ctx.clear(CGRect(x: 0, y: 0, width: N, height: N))

// macOS 11+ app-icon grid: the rounded square is inset from the full canvas
// (~100/1024) with a ~190/1024 corner radius, leaving transparent margins.
let inset = N * 100 / 1024
let side = N - inset * 2
let rect = CGRect(x: inset, y: inset, width: side, height: side)
let radius = N * 190 / 1024
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Amber body: bright top-left → deep bottom-right (CG origin is bottom-left).
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let body = CGGradient(colorsSpace: srgb,
                      colors: [rgb(242, 169, 140), rgb(201, 116, 90)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(body,
                       start: CGPoint(x: inset, y: N - inset),
                       end: CGPoint(x: N - inset, y: inset),
                       options: [])
// Soft domed highlight across the upper half for depth.
let gloss = CGGradient(colorsSpace: srgb,
                       colors: [rgb(255, 255, 255, 0.20), rgb(255, 255, 255, 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(gloss,
                       start: CGPoint(x: inset, y: N - inset),
                       end: CGPoint(x: inset, y: N * 0.45),
                       options: [])
ctx.restoreGState()

// Centered waveform: cream capsule bars, symmetric heights.
let cream = rgb(255, 247, 240)
let heights: [CGFloat] = [0.34, 0.62, 0.96, 0.62, 0.34]
let barW = N * 78 / 1024
let gap = N * 52 / 1024
let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = (N - totalW) / 2
let cy = N / 2
ctx.setFillColor(cream)
for h in heights {
    let barH = side * 0.72 * h
    let bar = CGRect(x: x, y: cy - barH / 2, width: barW, height: barH)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
    ctx.fillPath()
    x += barW + gap
}

guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
    exit(1)
}
