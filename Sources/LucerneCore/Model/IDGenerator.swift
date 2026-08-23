import Foundation

// Stable, unique IDs for paragraphs and placed objects. Needed for paragraph
// anchoring and undo identity (plan §7, "IDs"). A monotonic counter gives
// readable ids; a random suffix guarantees uniqueness even when new
// paragraphs are minted into a document that already loaded ids from disk.
public enum IDGenerator {
    private static var counter: UInt64 = 0
    private static let lock = NSLock()

    public static func next(_ prefix: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        counter &+= 1
        let n = String(counter, radix: 36)
        // The counter restarts every launch, so cross-launch uniqueness rests on
        // the random part: 64 bits, kept unambiguous from the counter by the
        // separator (unpadded base-36 concatenation would collide otherwise).
        let r = String(UInt64.random(in: 0 ..< .max), radix: 36)
        return "\(prefix)\(n)-\(r)"
    }
}
