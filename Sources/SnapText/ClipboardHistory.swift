import Foundation

/// Something the user copied, and when.
nonisolated struct ClipboardEntry: Codable, Equatable, Sendable {
    var text: String
    var date: Date
}

/// How much of the clipboard history to keep.
nonisolated enum HistoryLimit: Equatable, Sendable {
    /// This many of the most recent copies.
    case copies(Int)
    /// The copies made within this many days.
    case days(Int)
}

/// The text the user has copied, most recent first. It is saved to disk after every change.
final class ClipboardHistory {
    /// The most copies kept, whatever the limit.
    static let capacity = 1000
    /// Copies larger than this, in bytes, are not kept, so that saving the history stays quick.
    static let largestText = 1_000_000

    /// Where the history is kept between launches.
    static var standardFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.tausif.SnapText", isDirectory: true)
            .appendingPathComponent("History.json")
    }

    private(set) var entries: [ClipboardEntry] = []
    /// Lowering the limit deletes the copies beyond it straight away.
    var limit: HistoryLimit {
        didSet { prune() }
    }
    /// Where the history is saved, or nil to keep it in memory only.
    private let file: URL?

    init(file: URL?, limit: HistoryLimit, now: Date = .now) {
        self.file = file
        self.limit = limit
        if let file, let data = try? Data(contentsOf: file) {
            entries = (try? JSONDecoder().decode([ClipboardEntry].self, from: data)) ?? []
        }
        prune(now: now)
    }

    /// Puts a copy at the top. Text that is already in the history moves to the top rather than appearing twice.
    func add(_ text: String, at date: Date = .now) {
        guard !text.allSatisfy(\.isWhitespace), text.utf8.count <= Self.largestText else { return }
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(text: text, date: date), at: 0)
        trim(now: date)
        save()
    }

    /// Deletes the copy of `entry`'s text, wherever it has moved to since.
    func remove(_ entry: ClipboardEntry) {
        entries.removeAll { $0.text == entry.text }
        save()
    }

    func removeAll() {
        entries = []
        save()
    }

    /// The entries whose text contains `query`, ignoring case and accents. An empty query matches them all.
    func entries(matching query: String) -> [ClipboardEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Deletes the copies the limit no longer allows, such as those that have grown too old.
    func prune(now: Date = .now) {
        if trim(now: now) { save() }
    }

    /// Drops what the limit does not allow. Returns whether anything was dropped.
    @discardableResult
    private func trim(now: Date) -> Bool {
        let count = entries.count
        switch limit {
        case .copies(let copies):
            entries = Array(entries.prefix(max(copies, 0)))
        case .days(let days):
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
            entries.removeAll { $0.date < cutoff }
        }
        if entries.count > Self.capacity {
            entries.removeLast(entries.count - Self.capacity)
        }
        return entries.count != count
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A history that cannot be saved still works until the app quits.
        try? data.write(to: file, options: .atomic)
    }
}
