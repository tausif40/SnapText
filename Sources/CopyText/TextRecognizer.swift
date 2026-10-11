import CoreText
import Vision

/// A piece of recognized text and where it sits in the image, in unit coordinates with the origin at the bottom left.
nonisolated struct TextFragment: Equatable, Sendable {
    var text: String
    var box: CGRect
}

/// Reads text out of images with Vision.
nonisolated enum TextRecognizer {
    /// Recognizes the text in `image` without blocking the caller. Fragments come in reading order.
    @concurrent
    static func fragments(in image: CGImage) async throws -> [TextFragment] {
        let fragments = try recognize(image, detectingLanguage: true)
        if !fragments.isEmpty { return fragments }
        // Vision has been seen to return nothing for plainly legible text. Skipping language detection
        // takes a different path through it, and costs little when there really is no text.
        return try recognize(image, detectingLanguage: false)
    }

    /// Loads Vision's models ahead of the first capture. The first use after installing compiles them,
    /// which can take half a minute.
    static func warmUp() {
        Task.detached(priority: .utility) {
            guard let sample = sampleImage() else { return }
            _ = try? recognize(sample, detectingLanguage: true)
        }
    }

    private static func recognize(_ image: CGImage, detectingLanguage: Bool) throws -> [TextFragment] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = detectingLanguage
        if !detectingLanguage, let supported = try? request.supportedRecognitionLanguages() {
            request.recognitionLanguages = preferredLanguages(among: supported)
        }
        try VNImageRequestHandler(cgImage: image).perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return TextFragment(text: text, box: observation.boundingBox)
        }
    }

    /// The user's languages that Vision can read, most preferred first, always including English.
    static func preferredLanguages(among supported: [String], preferred: [String] = Locale.preferredLanguages) -> [String] {
        var languages: [String] = []
        for identifier in preferred + ["en-US"] {
            let language = identifier.prefix { $0 != "-" }
            // Prefer the entry with the same script ("zh-Hant-TW" → "zh-Hant") over any entry in that language.
            let match = supported.first { identifier.hasPrefix($0) } ?? supported.first { $0.hasPrefix(language + "-") }
            if let match, !languages.contains(match) { languages.append(match) }
        }
        return languages
    }

    private static func sampleImage() -> CGImage? {
        let size = CGSize(width: 400, height: 100)
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        let text = NSAttributedString(
            string: "CopyText 123", attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        context.textPosition = CGPoint(x: 30, y: 35)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        return context.makeImage()
    }
}
