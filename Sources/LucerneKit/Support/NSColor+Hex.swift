import AppKit

// Hex ⇆ NSColor for the model's color strings (e.g. "#1a1a1a"). Colors are stored
// and compared in sRGB so round-trips are stable regardless of the device profile.
public extension NSColor {

    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {                              // #RGB shorthand → #RRGGBB
            s = s.map { "\($0)\($0)" }.joined()
        }
        guard s.count == 6 || s.count == 8 else { return nil }

        var value: UInt64 = 0
        guard Scanner(string: s).scanHexInt64(&value) else { return nil }

        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xff) / 255
            g = CGFloat((value >> 16) & 0xff) / 255
            b = CGFloat((value >> 8) & 0xff) / 255
            a = CGFloat(value & 0xff) / 255
        } else {
            r = CGFloat((value >> 16) & 0xff) / 255
            g = CGFloat((value >> 8) & 0xff) / 255
            b = CGFloat(value & 0xff) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }

    /// "#RRGGBB" in sRGB. Alpha is dropped (the model uses opaque text colors).
    var lucerneHexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(round(c.redComponent * 255))
        let g = Int(round(c.greenComponent * 255))
        let b = Int(round(c.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
