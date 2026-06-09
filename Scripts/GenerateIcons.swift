#!/usr/bin/env swift
import AppKit
import Foundation

// Generates the app icon and a derived document icon from media-sources/icon.png.
// Runs on macOS (uses AppKit for compositing and `iconutil` for packaging). Output:
//   Scripts/AppIcon.icns       — rounded white tile with the Lucerne artwork
//   Scripts/DocumentIcon.icns  — a page with a folded corner showing the artwork
//
// Run from the repository root:  swift Scripts/GenerateIcons.swift
// Invoked automatically by Scripts/make-app.sh.

let sourcePath = "media-sources/icon.png"
guard let source = NSImage(contentsOfFile: sourcePath) else {
    FileHandle.standardError.write(Data("error: \(sourcePath) not found (run from the repo root)\n".utf8))
    exit(1)
}

// The iconset entries macOS expects: (file name, pixel dimension).
let entries: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

func renderPNG(pixels: Int, _ draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:]) ?? Data()
}

// MARK: - App icon: rounded white tile with the artwork inset.

func drawAppIcon(_ s: CGFloat) {
    let tile = NSRect(x: s * 0.04, y: s * 0.04, width: s * 0.92, height: s * 0.92)
    let radius = tile.width * 0.2237
    let bg = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
    NSColor.white.setFill()
    bg.fill()
    bg.lineWidth = max(1, s * 0.004)
    NSColor(calibratedWhite: 0.85, alpha: 1).setStroke()
    bg.stroke()

    let inset = s * 0.15
    source.draw(in: tile.insetBy(dx: inset, dy: inset), from: .zero,
                operation: .sourceOver, fraction: 1)
}

// MARK: - Document icon: a page with a folded corner, artwork in the lower area.

func drawDocumentIcon(_ s: CGFloat) {
    let pageW = s * 0.62, pageH = s * 0.80
    let page = NSRect(x: (s - pageW) / 2, y: (s - pageH) / 2, width: pageW, height: pageH)
    let fold = pageW * 0.24

    let outline = NSBezierPath()
    outline.move(to: NSPoint(x: page.minX, y: page.minY))
    outline.line(to: NSPoint(x: page.minX, y: page.maxY))
    outline.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    outline.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    outline.line(to: NSPoint(x: page.maxX, y: page.minY))
    outline.close()
    NSColor.white.setFill()
    outline.fill()
    outline.lineWidth = max(1, s * 0.006)
    NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
    outline.stroke()

    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
    corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    corner.close()
    NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
    corner.fill()
    corner.lineWidth = max(1, s * 0.006)
    NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
    corner.stroke()

    let artW = pageW * 0.76
    let artRect = NSRect(x: page.minX + (pageW - artW) / 2,
                         y: page.minY + pageH * 0.12, width: artW, height: artW)
    source.draw(in: artRect, from: .zero, operation: .sourceOver, fraction: 1)
}

// MARK: - Build each .iconset and package it with iconutil.

func buildIcns(named name: String, draw: @escaping (CGFloat) -> Void) {
    let iconsetURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(name)-\(UUID().uuidString).iconset")
    try? FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for (fileName, pixels) in entries {
        let data = renderPNG(pixels: pixels, draw)
        try? data.write(to: iconsetURL.appendingPathComponent("\(fileName).png"))
    }

    let output = "Scripts/\(name).icns"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", "-o", output, iconsetURL.path]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        FileHandle.standardError.write(Data("error: iconutil failed: \(error)\n".utf8))
        exit(1)
    }
    try? FileManager.default.removeItem(at: iconsetURL)
    print("wrote \(output)")
}

buildIcns(named: "AppIcon", draw: drawAppIcon)
buildIcns(named: "DocumentIcon", draw: drawDocumentIcon)
