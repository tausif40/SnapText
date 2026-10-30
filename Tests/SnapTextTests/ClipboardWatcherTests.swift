import AppKit
import Testing
@testable import SnapText

/// Puts a copy with `values` for its types on a pasteboard of its own, so the user's clipboard is left alone, and
/// returns what the watcher would keep of it.
@MainActor
private func kept(
    _ values: [NSPasteboard.PasteboardType: Any], includingPrivate: Bool = false, includingFileLocations: Bool = false
) -> String? {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.declareTypes(Array(values.keys), owner: nil)
    for (type, value) in values {
        if let string = value as? String {
            pasteboard.setString(string, forType: type)
        } else {
            pasteboard.setPropertyList(value, forType: type)
        }
    }
    return ClipboardWatcher.text(
        in: pasteboard, includingPrivate: includingPrivate, includingFileLocations: includingFileLocations)
}

@MainActor
@Suite struct ClipboardWatcherTests {
    private let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    @Test func keepsCopiedText() {
        #expect(kept([.string: "Hello"]) == "Hello")
    }

    // Finder puts both the file and its name on the clipboard.
    @Test func leavesOutCopiedFilesAndFolders() {
        #expect(kept([.fileURL: "file:///Users/Shared/Report.pdf", .string: "Report.pdf"]) == nil)
        #expect(kept([filenames: ["/Users/Shared/Photos"], .string: "Photos"]) == nil)
    }

    @Test func keepsTheLocationsOfCopiedFilesWhenAsked() {
        let file = [NSPasteboard.PasteboardType.fileURL: "file:///Users/Shared/Old%20Report.pdf", .string: "Old Report.pdf"]
        #expect(kept(file, includingFileLocations: true) == "/Users/Shared/Old Report.pdf")
        #expect(kept([filenames: ["/Users/Shared/Photos"], .string: "Photos"], includingFileLocations: true)
            == "/Users/Shared/Photos")
    }

    @Test func keepsOneLocationPerLineForSeveralFiles() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([
            URL(fileURLWithPath: "/Users/Shared/a.txt") as NSURL, URL(fileURLWithPath: "/Users/Shared/b.txt") as NSURL,
        ])
        #expect(ClipboardWatcher.text(in: pasteboard, includingPrivate: false, includingFileLocations: true)
            == "/Users/Shared/a.txt\n/Users/Shared/b.txt")
        #expect(ClipboardWatcher.text(in: pasteboard, includingPrivate: false, includingFileLocations: false) == nil)
    }

    @Test func leavesOutPrivateCopiesUnlessAllowed() {
        #expect(kept([.string: "hunter2", concealed: ""]) == nil)
        #expect(kept([.string: "hunter2", concealed: ""], includingPrivate: true) == "hunter2")
    }

    @Test func keepsNothingWithoutText() {
        #expect(kept([.html: "<b>Hello</b>"]) == nil)
    }
}
