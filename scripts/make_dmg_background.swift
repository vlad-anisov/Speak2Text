#!/usr/bin/env swift
// Draws the DMG window background (an arrow between the app and the Applications folder).
// Usage: swift scripts/make_dmg_background.swift <out-dir>   -> background.png (600x400) and background@2x.png
import AppKit

func render(scale: CGFloat, to path: String) {
    let w = 600 * scale, h = 400 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w), pixelsHigh: Int(h), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()
    // arrow between the icon centres (150, 190) and (450, 190) in top-left coordinates
    let y = h - 190 * scale
    let arrow = NSBezierPath()
    arrow.lineWidth = 6 * scale; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 240 * scale, y: y)); arrow.line(to: NSPoint(x: 360 * scale, y: y))
    arrow.move(to: NSPoint(x: 336 * scale, y: y + 22 * scale)); arrow.line(to: NSPoint(x: 360 * scale, y: y)); arrow.line(to: NSPoint(x: 336 * scale, y: y - 22 * scale))
    NSColor(calibratedWhite: 0.62, alpha: 1).setStroke()
    arrow.stroke()
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let text = NSAttributedString(string: "Drag Speak2Text to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 13 * scale), .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1), .paragraphStyle: para])
    text.draw(in: NSRect(x: 0, y: h - 60 * scale, width: w, height: 20 * scale))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
render(scale: 1, to: out + "/background.png")
render(scale: 2, to: out + "/background@2x.png")
