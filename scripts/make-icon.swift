#!/usr/bin/env swift
// Renders the MacCleaner app icon into MacCleaner/Resources/Assets.xcassets/AppIcon.appiconset.
//
//   swift scripts/make-icon.swift
//
// Pure CoreGraphics, no dependencies. Follows the macOS icon grid: an 824pt
// rounded-square body centred on a 1024pt canvas.
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let setDir = root.appendingPathComponent("MacCleaner/Resources/Assets.xcassets/AppIcon.appiconset")
let catalogDir = setDir.deletingLastPathComponent()

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Four-point sparkle with concave sides, centred at `c`.
func sparkle(_ c: CGPoint, radius r: CGFloat, waist: CGFloat = 0.16) -> CGPath {
    let p = CGMutablePath()
    let w = r * waist
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + w, y: c.y + w))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + w, y: c.y - w))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - w, y: c.y - w))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - w, y: c.y + w))
    p.closeSubpath()
    return p
}

func render(px: Int) -> Data {
    let s = CGFloat(px) / 1024
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Body: rounded square with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(0x1B2A6B)); ctx.fillPath()
    ctx.restoreGState()

    // Background gradient: deep indigo (bottom-left) to bright teal (top-right).
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: space,
                        colors: [color(0x2B2F8F), color(0x2F6FE0), color(0x22C3D6)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 100, y: 100), end: CGPoint(x: 924, y: 924), options: [])

    // Soft glow behind the main sparkle.
    let glow = CGGradient(colorsSpace: space,
                          colors: [color(0xFFFFFF, 0.38), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 470, y: 470), startRadius: 0,
                           endCenter: CGPoint(x: 470, y: 470), endRadius: 380, options: [])

    // Subtle top sheen.
    let sheen = CGGradient(colorsSpace: space,
                           colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 600), options: [])
    ctx.restoreGState()

    // Sparkles.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(0x0B1450, 0.35))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(sparkle(CGPoint(x: 470, y: 470), radius: 270)); ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF, 0.95))
    ctx.addPath(sparkle(CGPoint(x: 735, y: 730), radius: 110)); ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF, 0.85))
    ctx.addPath(sparkle(CGPoint(x: 760, y: 300), radius: 62)); ctx.fillPath()
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
try fm.createDirectory(at: setDir, withIntermediateDirectories: true)
try #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.write(
    to: catalogDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
        try render(px: pt * scale).write(to: setDir.appendingPathComponent(name))
        images.append(#"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(pt)x\#(pt)" }"#)
    }
}
let contents = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: setDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons to \(setDir.path)")
