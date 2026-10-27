// Draws the background of the disk image window and writes Resources/DMGBackground.tiff.
// Run from the project root: swift Scripts/make-dmg-background.swift
//
// The window is 640 × 400 points. Scripts/make-dmg-layout.sh puts SnapText's icon at (160, 200), the
// Applications link at (480, 200) and the note at (320, 330), measured from the top left as Finder does, with
// icons 80 points wide. The arrow and the text are drawn around those spots, so change them together.

import AppKit

let size = NSSize(width: 640, height: 400)

/// Converts a distance from the top of the window, as Finder measures, to AppKit's distance from the bottom.
func fromTop(_ y: CGFloat) -> CGFloat {
    size.height - y
}

/// Draws one line of text centered across the window, its top `top` points from the top.
func draw(_ text: String, top: CGFloat, font: NSFont, color: NSColor) {
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let textSize = string.size()
    string.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: fromTop(top) - textSize.height))
}

/// Draws the background into a bitmap at `scale` pixels per point.
func background(scale: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // A pale wash, so the icon labels stay easy to read.
    let top = NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1)
    let bottom = NSColor(srgbRed: 0.89, green: 0.92, blue: 0.98, alpha: 1)
    NSGradient(starting: bottom, ending: top)!.draw(in: NSRect(origin: .zero, size: size), angle: 90)

    let dark = NSColor(white: 0.13, alpha: 1)
    let grey = NSColor(white: 0.40, alpha: 1)
    draw("Drag SnapText into Applications to install it", top: 40, font: .systemFont(ofSize: 20, weight: .semibold),
         color: dark)
    draw("Then open it from Applications or Launchpad.", top: 72, font: .systemFont(ofSize: 13), color: grey)

    // The arrow, from the app's icon to the Applications folder.
    let arrow = NSBezierPath()
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: CGPoint(x: 252, y: fromTop(200)))
    arrow.line(to: CGPoint(x: 386, y: fromTop(200)))
    arrow.move(to: CGPoint(x: 364, y: fromTop(178)))
    arrow.line(to: CGPoint(x: 388, y: fromTop(200)))
    arrow.line(to: CGPoint(x: 364, y: fromTop(222)))
    NSColor(srgbRed: 0.16, green: 0.30, blue: 0.88, alpha: 1).setStroke()
    arrow.stroke()

    draw("Opening it for the first time? Read the note below.", top: 268, font: .systemFont(ofSize: 12), color: grey)
    return bitmap
}

// One TIFF holding both resolutions, so the background is sharp on Retina screens and others alike.
let image = NSImage(size: size)
image.addRepresentation(background(scale: 1))
image.addRepresentation(background(scale: 2))
try image.tiffRepresentation(using: .lzw, factor: 0)!.write(to: URL(fileURLWithPath: "Resources/DMGBackground.tiff"))
