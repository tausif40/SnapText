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

    static var hasShownWelcome: Bool {
        get { defaults.bool(forKey: "hasShownWelcome") }
        set { defaults.set(newValue, forKey: "hasShownWelcome") }
    }
}
