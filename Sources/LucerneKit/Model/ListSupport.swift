import Foundation

// List rendering support, kept AppKit-free so the numbering is unit-testable and
// shared by every layer that needs it: the builder (hanging indent), the reader
// (stripping the derived indent), the layout manager (drawing the marker), the
// editor (apply / indent), and the Markdown exporter. The marker a list item shows
// is *derived* from the run of items around it — never stored — so all of that logic
// lives here in one place.

// MARK: - Geometry

/// The measurements that give a list its hanging indent. `Double` (not `CGFloat`)
/// so this stays in the AppKit-free model; call sites convert.
public enum ListGeometry {
    /// Points of indent added per nesting level.
    public static let indentStep: Double = 24
    /// Gap between a marker's right edge and the text it labels.
    public static let markerGap: Double = 6

    /// Where a level's text (and its wrapped lines) begin, in points from the margin.
    public static func contentIndent(level: Int) -> Double {
        indentStep * Double(max(0, level) + 1)
    }
}

// MARK: - Attribute codec

/// Encodes a `ListItemModel` to / from the `String` stored in the `.lucerneList`
/// attribute (JSON — robust to the struct gaining fields, and plist-safe so it
/// survives archiving, copy/paste, and undo snapshots).
public enum ListItemCodec {
    public static func encode(_ model: ListItemModel) -> String? {
        guard let data = try? JSONEncoder().encode(model) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode(_ value: Any?) -> ListItemModel? {
        guard let string = value as? String, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ListItemModel.self, from: data)
    }
}

// MARK: - Marker resolution (the numbering engine)

/// The visible marker for one item, resolved against its neighbours.
public struct ResolvedMarker: Equatable {
    public let text: String    // "•", "1.", "a." …  (what the reader/layout draws)
    public let number: Int?    // an ordered item's raw count (nil for bullets)
    public init(text: String, number: Int?) {
        self.text = text
        self.number = number
    }
}

public enum ListMarkers {

    /// Resolves the marker of every paragraph in document order. `nil` entries are
    /// non-list paragraphs (they break a list's continuity and reset numbering); a
    /// `nil` result means "no marker". A list is the maximal run of contiguous items
    /// sharing one `list` id — a non-list paragraph or a different id starts a new one.
    public static func resolve(_ items: [ListItemModel?]) -> [ResolvedMarker?] {
        var result = [ResolvedMarker?](repeating: nil, count: items.count)
        var counters: [Int] = []       // counters[level] = current number (0 == not yet started)
        var previousID: String? = nil  // id of the immediately preceding list item, else nil

        for (index, maybe) in items.enumerated() {
            guard let item = maybe else {
                counters = []; previousID = nil
                continue
            }
            let level = max(0, item.level)
            if previousID != item.list { counters = [] }   // new list (or broken by non-list)

            if level >= counters.count {
                while counters.count <= level { counters.append(0) }   // descend: new deeper slots
            } else if level < counters.count - 1 {
                counters.removeSubrange((level + 1) ..< counters.count) // ascend: forget deeper
            }

            if item.ordered {
                counters[level] = counters[level] == 0 ? max(1, item.start ?? 1) : counters[level] + 1
                result[index] = ResolvedMarker(text: orderedLabel(counters[level], style: item.marker) + ".",
                                               number: counters[level])
            } else {
                // A bullet doesn't count: leave the counter untouched. An ordered item
                // that follows keeps counting from where the numbers left off (its slot
                // is still non-zero), while an ordered item with only bullets before it
                // at this level correctly starts at 1 (or its `start`).
                result[index] = ResolvedMarker(text: bulletGlyph(item.marker, level: level), number: nil)
            }
            previousID = item.list
        }
        return result
    }

    // MARK: Marker glyphs / labels

    public static func bulletGlyph(_ marker: String, level: Int) -> String {
        switch marker {
        case "disc":   return "\u{2022}"   // •
        case "circle": return "\u{25E6}"   // ◦
        case "square": return "\u{25AA}"   // ▪
        case "dash":   return "\u{2013}"   // –
        default:
            // Unknown / "auto": cycle by depth like CSS's default bullet ramp.
            let cycle = ["\u{2022}", "\u{25E6}", "\u{25AA}"]
            return cycle[max(0, level) % cycle.count]
        }
    }

    /// The label for an ordered item (without the trailing "."): "1", "a", "IV" …
    public static func orderedLabel(_ n: Int, style: String) -> String {
        switch style {
        case "lower-alpha": return alpha(n, uppercase: false)
        case "upper-alpha": return alpha(n, uppercase: true)
        case "lower-roman": return roman(n, uppercase: false)
        case "upper-roman": return roman(n, uppercase: true)
        default:            return String(max(1, n))   // "decimal" and anything unknown
        }
    }

    /// Bijective base-26: 1→a, 26→z, 27→aa, 52→az, 53→ba …
    public static func alpha(_ n: Int, uppercase: Bool) -> String {
        guard n >= 1 else { return uppercase ? "A" : "a" }
        let base = (uppercase ? UnicodeScalar("A") : UnicodeScalar("a")).value
        var value = n
        var chars: [Character] = []
        while value > 0 {
            value -= 1
            chars.append(Character(UnicodeScalar(base + UInt32(value % 26))!))
            value /= 26
        }
        return String(chars.reversed())
    }

    /// Roman numerals for 1…3999; outside that range falls back to decimal.
    public static func roman(_ n: Int, uppercase: Bool) -> String {
        guard n >= 1, n < 4000 else { return String(n) }
        let table: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
            (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
        ]
        var value = n
        var out = ""
        for (amount, symbol) in table { while value >= amount { out += symbol; value -= amount } }
        return uppercase ? out : out.lowercased()
    }

    // MARK: Marker menus (the styles the UI offers)

    /// Ordered numbering styles, in menu order: (role key, menu label).
    public static let orderedStyles: [(marker: String, label: String)] = [
        ("decimal", "1, 2, 3"),
        ("lower-alpha", "a, b, c"),
        ("upper-alpha", "A, B, C"),
        ("lower-roman", "i, ii, iii"),
        ("upper-roman", "I, II, III"),
    ]

    /// Bullet styles, in menu order: (role key, menu label).
    public static let unorderedStyles: [(marker: String, label: String)] = [
        ("disc", "Disc"),
        ("circle", "Circle"),
        ("square", "Square"),
        ("dash", "Dash"),
    ]

    /// The default marker for a new list of each kind.
    public static let defaultOrderedMarker = "decimal"
    public static let defaultUnorderedMarker = "disc"
}
