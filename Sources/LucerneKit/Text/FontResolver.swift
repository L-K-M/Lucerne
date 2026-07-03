import AppKit

// Builds an NSFont from a family name + size + bold/italic, and reads those traits
// back out. Centralised so the builder and reader agree on how bold/italic map to
// the font system.
public enum FontResolver {

    public static func font(family: String?, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let familyName = family ?? "Helvetica"

        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }

        // Primary path: ask the font manager for the family with the combined traits
        // in one request (weight 9 == bold, 5 == regular on AppKit's 0–15 scale). It
        // returns the closest matching face, or nil when the family is unavailable.
        if let combined = NSFontManager.shared.font(withFamily: familyName,
                                                    traits: traits,
                                                    weight: bold ? 9 : 5,
                                                    size: size) {
            return combined
        }

        // Fallback: resolve a base font (substituting for a missing family), then add
        // the traits ONE AT A TIME — `convert(toHaveTrait:)` is documented as
        // single-trait, and a combined mask can silently drop a trait for families
        // that need stepwise conversion (review 1.37).
        let base = NSFont(name: familyName, size: size)
            ?? NSFontManager.shared.font(withFamily: familyName, traits: [], weight: 5, size: size)
            ?? NSFont.systemFont(ofSize: size)

        var resolved = base
        if bold { resolved = NSFontManager.shared.convert(resolved, toHaveTrait: .boldFontMask) }
        if italic { resolved = NSFontManager.shared.convert(resolved, toHaveTrait: .italicFontMask) }
        return resolved
    }

    public static func isBold(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    public static func isItalic(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.italicFontMask)
    }
}
