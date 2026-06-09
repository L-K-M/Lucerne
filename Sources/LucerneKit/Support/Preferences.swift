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

    /// The ruler unit. Defaults to centimetres.
    public static var rulerUnit: RulerUnit {
        get { RulerUnit(rawValue: UserDefaults.standard.string(forKey: rulerUnitKey) ?? "") ?? .centimeters }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: rulerUnitKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}
