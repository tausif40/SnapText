// Draws the app icon and writes Resources/AppIcon.icns.
// Run from the project root: swift Scripts/make-icon.swift

import AppKit

/// Draws the icon into a square bitmap `pixels` wide. All measurements are for a 1024-point canvas.
func icon(pixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // The rounded tile every macOS icon sits on, with a soft shadow beneath it.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.3))
    NSColor.black.setFill()
    tile.fill()
    context.restoreGState()
    let top = NSColor(srgbRed: 0.36, green: 0.62, blue: 1.0, alpha: 1)
    let bottom = NSColor(srgbRed: 0.16, green: 0.30, blue: 0.88, alpha: 1)
    NSGradient(starting: bottom, ending: top)!.draw(in: tile, angle: 90)

    // Viewfinder corners.
    NSColor.white.setStroke()
    let frame = NSRect(x: 262, y: 262, width: 500, height: 500)
    let arm: CGFloat = 120
    let radius: CGFloat = 56
    let corners = NSBezierPath()
    corners.lineWidth = 44
    corners.lineCapStyle = .round
    for (corner, horizontal, vertical) in [
        (CGPoint(x: frame.minX, y: frame.minY), 1.0, 1.0), (CGPoint(x: frame.maxX, y: frame.minY), -1.0, 1.0),
        (CGPoint(x: frame.maxX, y: frame.maxY), -1.0, -1.0), (CGPoint(x: frame.minX, y: frame.maxY), 1.0, -1.0),
    ] {
        corners.move(to: CGPoint(x: corner.x, y: corner.y + vertical * arm))
        corners.appendArc(
            from: corner, to: CGPoint(x: corner.x + horizontal * arm, y: corner.y), radius: radius)
        corners.line(to: CGPoint(x: corner.x + horizontal * arm, y: corner.y))
    }
    corners.stroke()

    // Three list rows, each a dot and a line, for text.
    NSColor.white.setFill()
    for (y, width) in [(588.0, 232.0), (488.0, 232.0), (388.0, 152.0)] {
        NSBezierPath(ovalIn: NSRect(x: 356, y: y, width: 48, height: 48)).fill()
        NSBezierPath(roundedRect: NSRect(x: 436, y: y, width: width, height: 48), xRadius: 24, yRadius: 24).fill()
    }
    return bitmap
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let png = icon(pixels: points * scale).representation(using: .png, properties: [:])!
        try png.write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(iconutil.terminationStatus)
