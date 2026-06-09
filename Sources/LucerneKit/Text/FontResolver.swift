import AppKit

// Builds an NSFont from a family name + size + bold/italic, and reads those traits
// back out. Centralised so the builder and reader agree on how bold/italic map to
// the font system.
public enum FontResolver {

    public static func font(family: String?, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let familyName = family ?? "Helvetica"
        let base = NSFont(name: familyName, size: size)
            ?? NSFontManager.shared.font(withFamily: familyName, traits: [], weight: 5, size: size)
            ?? NSFont.systemFont(ofSize: size)

        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        guard !traits.isEmpty else { return base }
        return NSFontManager.shared.convert(base, toHaveTrait: traits)
    }

    public static func isBold(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    public static func isItalic(_ font: NSFont) -> Bool {
        NSFontManager.shared.traits(of: font).contains(.italicFontMask)
    }
}
