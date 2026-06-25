#!/usr/bin/env swift

import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let size: CGFloat
}

let specs = [
    IconSpec(filename: "icon_16x16.png", size: 16),
    IconSpec(filename: "icon_16x16@2x.png", size: 32),
    IconSpec(filename: "icon_32x32.png", size: 32),
    IconSpec(filename: "icon_32x32@2x.png", size: 64),
    IconSpec(filename: "icon_128x128.png", size: 128),
    IconSpec(filename: "icon_128x128@2x.png", size: 256),
    IconSpec(filename: "icon_256x256.png", size: 256),
    IconSpec(filename: "icon_256x256@2x.png", size: 512),
    IconSpec(filename: "icon_512x512.png", size: 512),
    IconSpec(filename: "icon_512x512@2x.png", size: 1024)
]

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_app_icon.swift <output.iconset>\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let fileManager = FileManager.default
try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

for spec in specs {
    let image = NSImage(size: NSSize(width: spec.size, height: spec.size))
    image.lockFocus()
    drawIcon(in: NSRect(x: 0, y: 0, width: spec.size, height: spec.size))
    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fputs("failed to render \(spec.filename)\n", stderr)
        exit(1)
    }

    try png.write(to: outputURL.appendingPathComponent(spec.filename))
}

func drawIcon(in rect: NSRect) {
    let scale = rect.width / 1024.0
    NSGraphicsContext.current?.saveGraphicsState()
    let scaleTransform = NSAffineTransform()
    scaleTransform.scaleX(by: scale, yBy: scale)
    scaleTransform.concat()

    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSColor.clear.setFill()
    canvas.fill()

    let background = NSBezierPath(
        roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880),
        xRadius: 210,
        yRadius: 210
    )
    NSGradient(colors: [
        NSColor(red: 0.06, green: 0.10, blue: 0.18, alpha: 1),
        NSColor(red: 0.06, green: 0.18, blue: 0.16, alpha: 1),
        NSColor(red: 0.10, green: 0.32, blue: 0.22, alpha: 1)
    ])?.draw(in: background, angle: 135)

    NSColor.white.withAlphaComponent(0.14).setStroke()
    background.lineWidth = 10
    background.stroke()

    let screenShadow = NSBezierPath(
        roundedRect: NSRect(x: 204, y: 292, width: 616, height: 442),
        xRadius: 80,
        yRadius: 80
    )
    NSColor.black.withAlphaComponent(0.20).setFill()
    screenShadow.fill()

    let screen = NSBezierPath(
        roundedRect: NSRect(x: 220, y: 314, width: 584, height: 424),
        xRadius: 74,
        yRadius: 74
    )
    NSGradient(colors: [
        NSColor(red: 0.10, green: 0.17, blue: 0.26, alpha: 1),
        NSColor(red: 0.08, green: 0.24, blue: 0.22, alpha: 1)
    ])?.draw(in: screen, angle: 90)

    NSColor(red: 0.25, green: 0.90, blue: 0.48, alpha: 0.86).setStroke()
    screen.lineWidth = 18
    screen.stroke()

    let base = NSBezierPath(
        roundedRect: NSRect(x: 164, y: 224, width: 696, height: 92),
        xRadius: 42,
        yRadius: 42
    )
    NSColor(red: 0.18, green: 0.22, blue: 0.28, alpha: 1).setFill()
    base.fill()

    let baseLip = NSBezierPath(
        roundedRect: NSRect(x: 328, y: 250, width: 368, height: 26),
        xRadius: 13,
        yRadius: 13
    )
    NSColor.white.withAlphaComponent(0.18).setFill()
    baseLip.fill()

    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: 544, y: 668))
    bolt.line(to: NSPoint(x: 398, y: 500))
    bolt.line(to: NSPoint(x: 508, y: 500))
    bolt.line(to: NSPoint(x: 454, y: 356))
    bolt.line(to: NSPoint(x: 628, y: 558))
    bolt.line(to: NSPoint(x: 512, y: 558))
    bolt.close()

    NSColor.black.withAlphaComponent(0.28).setFill()
    let shadow = bolt.copy() as? NSBezierPath
    shadow?.transform(using: .init(translationByX: 0, byY: -18))
    shadow?.fill()

    NSGradient(colors: [
        NSColor(red: 0.30, green: 1.0, blue: 0.52, alpha: 1),
        NSColor(red: 0.16, green: 0.78, blue: 1.0, alpha: 1)
    ])?.draw(in: bolt, angle: -35)

    NSColor.white.withAlphaComponent(0.16).setStroke()
    bolt.lineWidth = 8
    bolt.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()
}
