import Foundation

/// Settings that persist between launches.
enum Preferences {
    private static let defaults = UserDefaults.standard

    /// Whether copied text keeps the line breaks it has on screen, or is joined into one line.
    static var keepLineBreaks: Bool {
        get { defaults.object(forKey: "keepLineBreaks") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "keepLineBreaks") }
    }

    /// Whether every copy is confirmed with a notice. Off, only a copy that kept the user waiting is.
    static var showCopiedNotice: Bool {
        get { defaults.object(forKey: "showCopiedNotice") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showCopiedNotice") }
    }

    static var shortcut: Shortcut {
        get { Shortcut(propertyList: defaults.object(forKey: "shortcut")) ?? .default }
        set { defaults.set(newValue.propertyList, forKey: "shortcut") }
    }

    static var historyShortcut: Shortcut {
        get { Shortcut(propertyList: defaults.object(forKey: "historyShortcut")) ?? .defaultHistory }
        set { defaults.set(newValue.propertyList, forKey: "historyShortcut") }
    }

    /// Whether picking a copy from the history pastes it into the text field the user is typing in.
    static var pastesFromHistory: Bool {
        get { defaults.object(forKey: "pastesFromHistory") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "pastesFromHistory") }
    }

    /// Whether SnapText has asked macOS for the Accessibility permission that pasting needs.
    static var hasAskedToPaste: Bool {
        get { defaults.bool(forKey: "hasAskedToPaste") }
        set { defaults.set(newValue, forKey: "hasAskedToPaste") }
    }

    /// Whether text the user copies is added to the clipboard history.
    static var keepsHistory: Bool {
        get { defaults.object(forKey: "keepsHistory") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "keepsHistory") }
    }

    /// Whether copies that password managers and similar apps mark as private, such as passwords, are saved in
    /// the history too. Off unless the user turns it on.
    static var savesPrivateCopies: Bool {
        get { defaults.bool(forKey: "savesPrivateCopies") }
        set { defaults.set(newValue, forKey: "savesPrivateCopies") }
    }

    /// Whether the history is limited by the age of its copies rather than by their number.
    static var limitsHistoryByDays: Bool {
        get { defaults.bool(forKey: "limitsHistoryByDays") }
        set { defaults.set(newValue, forKey: "limitsHistoryByDays") }
    }

    static let defaultHistoryCopies = 500
    static let defaultHistoryDays = 30

    /// How many copies the history keeps when it is limited by their number.
    static var historyCopies: Int {
        get { defaults.object(forKey: "historyCopies") as? Int ?? defaultHistoryCopies }
        set { defaults.set(newValue, forKey: "historyCopies") }
    }

    /// How many days of copies the history keeps when it is limited by their age.
    static var historyDays: Int {
        get { defaults.object(forKey: "historyDays") as? Int ?? defaultHistoryDays }
        set { defaults.set(newValue, forKey: "historyDays") }
    }

    static var historyLimit: HistoryLimit {
        limitsHistoryByDays ? .days(historyDays) : .copies(historyCopies)
    }

    static let historyOpacityRange = 0.3...1.0

    /// How opaque the clipboard history popup's background is, from 0.3 to 1.
    static var historyOpacity: Double {
        get { defaults.object(forKey: "historyOpacity") as? Double ?? 1 }
        set {
            defaults.set(newValue, forKey: "historyOpacity")
            NotificationCenter.default.post(name: .historyOpacityChanged, object: nil)
        }
    }

    /// Where the user last dragged the history window to, or nil if they never have.
    static var historyWindowOrigin: CGPoint? {
        get {
            guard let point = defaults.array(forKey: "historyWindowOrigin") as? [Double], point.count == 2 else {
                return nil
            }
            return CGPoint(x: point[0], y: point[1])
        }
        set { defaults.set(newValue.map { [Double($0.x), Double($0.y)] }, forKey: "historyWindowOrigin") }
    }
}

extension Notification.Name {
    /// Posted when the clipboard history popup's background opacity changes.
    static let historyOpacityChanged = Notification.Name("historyOpacityChanged")
}
