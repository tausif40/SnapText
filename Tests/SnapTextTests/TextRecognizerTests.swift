import AppKit
import Testing
@testable import SnapText

/// Draws into a bitmap at twice the point size, like a capture of a Retina display. The origin is at the top left.
@MainActor
private func image(width: CGFloat, height: CGFloat, background: NSColor = .white, draw: () -> Void) -> CGImage {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2), bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    background.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.cgImage!
}

@MainActor
private func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat = 13, color: NSColor = .black) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: color]
    (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
}

private func read(_ image: CGImage, keepLineBreaks: Bool = true) async throws -> String {
    TextLayout.text(from: try await TextRecognizer.fragments(in: image), keepLineBreaks: keepLineBreaks)
}

// Serialized because Vision compiles its models on first use, which concurrent requests only slow down.
@MainActor
@Suite(.serialized) struct TextRecognizerTests {
    @Test func readsLinesOfEnglish() async throws {
        let capture = image(width: 420, height: 60) {
            draw("The quick brown fox jumps over the lazy dog.", x: 12, y: 10)
            draw("Version 14.2 (Build 23C64)", x: 12, y: 34)
        }
        #expect(try await read(capture) == "The quick brown fox jumps over the lazy dog.\nVersion 14.2 (Build 23C64)")
        #expect(try await read(capture, keepLineBreaks: false) == "The quick brown fox jumps over the lazy dog. Version 14.2 (Build 23C64)")
    }

    @Test func readsLightTextOnADarkBackground() async throws {
        let capture = image(width: 420, height: 40, background: NSColor(white: 0.12, alpha: 1)) {
            draw("Dark mode text should work just as well.", x: 12, y: 10, color: .white)
        }
        #expect(try await read(capture) == "Dark mode text should work just as well.")
    }

    @Test func readsHindi() async throws {
        let capture = image(width: 420, height: 50) {
            draw("नमस्ते दुनिया। यह एक परीक्षण है।", x: 12, y: 10, size: 16)
        }
        #expect(try await read(capture) == "नमस्ते दुनिया। यह एक परीक्षण है।")
    }

    @Test func readsATableRowByRow() async throws {
        let rows = [("Model Name:", "MacBook Pro"), ("Chip:", "Apple M4 Pro"), ("Memory:", "24 GB")]
        let capture = image(width: 360, height: 84) {
            for (index, row) in rows.enumerated() {
                draw(row.0, x: 12, y: CGFloat(10 + index * 24))
                draw(row.1, x: 180, y: CGFloat(10 + index * 24))
            }
        }
        #expect(try await read(capture) == "Model Name:\tMacBook Pro\nChip:\tApple M4 Pro\nMemory:\t24 GB")
    }

    @Test func findsNothingInAnImageWithoutText() async throws {
        let capture = image(width: 200, height: 80) {
            NSColor.systemBlue.setFill()
            NSRect(x: 20, y: 20, width: 60, height: 30).fill()
        }
        #expect(try await read(capture) == "")
    }
}
