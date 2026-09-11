#!/usr/bin/env swift
import AppKit

// Reproducible vector drawing for the brand app; monitor geometry follows the
// OpenCapture family, while the histogram uses the OpenInstaCine accent.
let side = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let full = NSRect(x: 0, y: 0, width: side, height: side)
NSColor(calibratedWhite: 0.065, alpha: 1).setFill()
full.fill()
let yellow = NSColor(red: 1, green: 207 / 255, blue: 0, alpha: 1)
let heights: [CGFloat] = [30, 94, 159, 145, 205, 250, 184, 34, 68, 116, 93, 129, 169, 151, 216, 243, 163, 132, 55]
for (index, height) in heights.enumerated() {
    yellow.withAlphaComponent(index < 9 ? 0.4 : 0.92).setFill()
    NSBezierPath(roundedRect: NSRect(x: 216 + CGFloat(index) * 32, y: 280,
        width: 26, height: height), xRadius: 9, yRadius: 9).fill()
}
NSColor.white.setStroke()
let frame = NSBezierPath(roundedRect: NSRect(x: 163, y: 274, width: 698, height: 476),
    xRadius: 82, yRadius: 82)
frame.lineWidth = 26
frame.stroke()
NSColor.white.setFill()
for x in [66, 894] {
    NSBezierPath(roundedRect: NSRect(x: x, y: 370, width: 64, height: 288),
        xRadius: 16, yRadius: 16).fill()
}
let cross = NSBezierPath()
cross.move(to: NSPoint(x: 474, y: 508)); cross.line(to: NSPoint(x: 550, y: 508))
cross.move(to: NSPoint(x: 512, y: 470)); cross.line(to: NSPoint(x: 512, y: 546))
cross.lineWidth = 10; cross.lineCapStyle = .round; cross.stroke()
for (x, y, sx, sy) in [(220.0, 670.0, 1.0, -1.0), (803, 670, -1, -1),
                       (220, 338, 1, 1), (803, 338, -1, 1)] {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: x, y: y + sy * 30))
    p.curve(to: NSPoint(x: x + sx * 52, y: y - sy * 24),
        controlPoint1: NSPoint(x: x, y: y - sy * 12),
        controlPoint2: NSPoint(x: x + sx * 20, y: y - sy * 24))
    p.lineWidth = 22; p.lineCapStyle = .round; p.stroke()
}
NSColor(red: 1, green: 0.18, blue: 0.19, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 261, y: 586, width: 66, height: 66)).fill()
let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: 57, weight: .heavy), toHaveTrait: .italicFontMask)
("REC" as NSString).draw(at: NSPoint(x: 343, y: 582), withAttributes: [.font: font, .foregroundColor: NSColor.white])
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
for (folder, filename, kind) in [("AppIcon.appiconset", "AppIcon-1024.png", "icon"),
                                 ("AppLogo.imageset", "AppLogo.png", "image")] {
    let directory = root.appendingPathComponent("Apps/Apple/OpenInstaCine/Assets.xcassets/\(folder)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try png.write(to: directory.appendingPathComponent(filename))
    var entry: [String: String] = ["filename": filename, "idiom": "universal"]
    if kind == "icon" { entry["platform"] = "ios"; entry["size"] = "1024x1024" }
    let contents: [String: Any] = ["images": [entry], "info": ["author": "xcode", "version": 1]]
    try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
        .write(to: directory.appendingPathComponent("Contents.json"))
}
print("Generated OpenInstaCine icon and launch mark.")
