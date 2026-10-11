import AppKit

/// Captures a region of the screen with the system's own selection crosshair.
enum ScreenCapture {
    private static var selection: Process?

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Adds the app to the Screen Recording list in System Settings. The first call also shows the system prompt.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Lets the user drag over part of the screen. Returns nil if they press Escape.
    static func captureSelection() async throws -> CGImage? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("CopyText-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }

        // -i: interactive selection, -x: no shutter sound, -o: no window shadow when a whole window is picked.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-o", file.path]

        selection = process
        defer { selection = nil }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }

        // Read the file into memory so the image no longer depends on it once it is deleted.
        guard let data = try? Data(contentsOf: file),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Dismisses the crosshair if a selection is in progress.
    static func cancelSelection() {
        selection?.terminate()
    }
}
