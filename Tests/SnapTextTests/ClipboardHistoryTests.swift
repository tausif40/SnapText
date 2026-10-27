import Foundation
import Testing
@testable import SnapText

@MainActor
@Suite struct ClipboardHistoryTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func newestCopyComesFirst() {
        let history = ClipboardHistory(file: nil, limit: .copies(10))
        history.add("first", at: start)
        history.add("second", at: start + 1)
        #expect(history.entries.map(\.text) == ["second", "first"])
    }

    @Test func copyingAgainMovesToTheTop() {
        let history = ClipboardHistory(file: nil, limit: .copies(10))
        history.add("a", at: start)
        history.add("b", at: start + 1)
        history.add("a", at: start + 2)
        #expect(history.entries == [
            ClipboardEntry(text: "a", date: start + 2), ClipboardEntry(text: "b", date: start + 1),
        ])
    }

    @Test func ignoresBlankCopies() {
        let history = ClipboardHistory(file: nil, limit: .copies(10))
        history.add(" \n\t")
        history.add("")
        #expect(history.entries.isEmpty)
    }

    @Test func keepsTheLastCopiesUpToTheLimit() {
        let history = ClipboardHistory(file: nil, limit: .copies(3))
        for number in 1...5 { history.add("\(number)", at: start + Double(number)) }
        #expect(history.entries.map(\.text) == ["5", "4", "3"])
    }

    @Test func neverKeepsMoreThanItsCapacity() {
        let history = ClipboardHistory(file: nil, limit: .days(365))
        for number in 0...ClipboardHistory.capacity { history.add("\(number)", at: start) }
        #expect(history.entries.count == ClipboardHistory.capacity)
        #expect(history.entries.last?.text == "1")
    }

    @Test func dropsCopiesOlderThanTheLimit() {
        let day: TimeInterval = 24 * 60 * 60
        let history = ClipboardHistory(file: nil, limit: .days(2))
        history.add("old", at: start)
        history.add("recent", at: start + 2 * day)
        history.prune(now: start + 3 * day)
        #expect(history.entries.map(\.text) == ["recent"])
    }

    @Test func removesACopyThatHasMovedSince() {
        let history = ClipboardHistory(file: nil, limit: .copies(10))
        history.add("a", at: start)
        let shown = history.entries[0]
        history.add("b", at: start + 1)
        history.add("a", at: start + 2)
        history.remove(shown)
        #expect(history.entries.map(\.text) == ["b"])
    }

    @Test func loweringTheLimitDeletesAtOnce() {
        let history = ClipboardHistory(file: nil, limit: .copies(10))
        for number in 1...5 { history.add("\(number)") }
        history.limit = .copies(2)
        #expect(history.entries.map(\.text) == ["5", "4"])
    }

    @Test func searchIgnoresCaseAndAccents() {
        let history = ClipboardHistory(file: nil, limit: .copies(10))
        history.add("Café Menu")
        history.add("Invoice 42")
        #expect(history.entries(matching: "cafe").map(\.text) == ["Café Menu"])
        #expect(history.entries(matching: "  ").count == 2)
        #expect(history.entries(matching: "nothing").isEmpty)
    }

    @Test func survivesARelaunch() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapTextTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("History.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let history = ClipboardHistory(file: file, limit: .copies(10))
        history.add("kept", at: start)
        let reopened = ClipboardHistory(file: file, limit: .copies(10))
        #expect(reopened.entries == [ClipboardEntry(text: "kept", date: start)])

        reopened.removeAll()
        #expect(ClipboardHistory(file: file, limit: .copies(10)).entries.isEmpty)
    }
}
