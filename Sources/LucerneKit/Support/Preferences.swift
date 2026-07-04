import Foundation
import CoreGraphics

// App-level preferences backed by UserDefaults. Kept in LucerneKit so views (the
// ruler) can read them; the Settings window (in the executable) writes them. A
// change posts `didChange` so open windows can refresh.

/// The unit the ruler labels and ticks use.
public enum RulerUnit: String, CaseIterable {
    case centimeters
    case inches

    public var displayName: String {
        switch self {
        case .centimeters: return "Centimeters"
        case .inches: return "Inches"
        }
    }

    /// Points (1/72") per one unit.
    public var pointsPerUnit: CGFloat {
        switch self {
        case .centimeters: return 72.0 / 2.54     // ≈ 28.3465
        case .inches: return 72
        }
    }

    /// Minor tick subdivisions drawn per unit (the major, labelled tick is every unit).
    public var subdivisions: Int {
        switch self {
        case .centimeters: return 4               // quarter-centimetre ticks
        case .inches: return 8                    // eighth-inch ticks
        }
    }
}

public enum Preferences {
    /// Posted when any preference changes so live views can refresh.
    public static let didChange = Notification.Name("ch.lkmc.lucerne.preferencesDidChange")

    private static let rulerUnitKey = "rulerUnit"
    private static let smartQuotesKey = "smartQuotes"
    private static let smartDashesKey = "smartDashes"
    private static let markdownShortcutsKey = "markdownShortcuts"

    /// The ruler unit. Defaults to centimetres.
    public static var rulerUnit: RulerUnit {
        get { RulerUnit(rawValue: UserDefaults.standard.string(forKey: rulerUnitKey) ?? "") ?? .centimeters }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: rulerUnitKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Automatic smart-quote substitution in the editor. Off by default — a
    /// period-correct opt-in; a letters tool shouldn't silently rewrite what you type.
    public static var smartQuotes: Bool {
        get { UserDefaults.standard.bool(forKey: smartQuotesKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: smartQuotesKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Automatic smart-dash substitution in the editor. Off by default (see `smartQuotes`).
    public static var smartDashes: Bool {
        get { UserDefaults.standard.bool(forKey: smartDashesKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: smartDashesKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Markdown block shortcuts in the editor: typing a marker + space at the start
    /// of a paragraph ("# " → Heading 1, "> " → the quote style, …) applies the
    /// matching paragraph style and swallows the marker. Unlike the substitutions
    /// above this is **on** by default — it fires only on an explicit marker you
    /// just typed, the change is immediately visible, and a single ⌘Z restores the
    /// literal text, so it isn't a silent rewrite of anything already on the page.
    public static var markdownShortcuts: Bool {
        get {
            let defaults = UserDefaults.standard
            return defaults.object(forKey: markdownShortcutsKey) == nil
                ? true
                : defaults.bool(forKey: markdownShortcutsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: markdownShortcutsKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}
