import Foundation

/// Settings changed from the menu bar, kept across launches.
enum Preferences {
    static let frameRates = [30, 60, 120]

    private static let defaults = UserDefaults.standard

    static var keepsWindowOnTop: Bool {
        get { defaults.bool(forKey: "keepsWindowOnTop") }
        set { defaults.set(newValue, forKey: "keepsWindowOnTop") }
    }

    static var bringsWindowToFrontOnCursorEnter: Bool {
        get { defaults.object(forKey: "bringsWindowToFrontOnCursorEnter") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "bringsWindowToFrontOnCursorEnter") }
    }

    static var showsCursor: Bool {
        get { defaults.object(forKey: "showsCursor") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showsCursor") }
    }

    static var frameRate: Int {
        get {
            let frameRate = defaults.integer(forKey: "frameRate")
            return frameRates.contains(frameRate) ? frameRate : 60
        }
        set { defaults.set(newValue, forKey: "frameRate") }
    }
}
