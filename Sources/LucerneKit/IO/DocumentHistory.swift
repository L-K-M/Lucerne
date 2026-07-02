import Foundation

// A dated snapshot of the document's derived Markdown text, stored under history/
// inside the .luce package (D3). It's a safety net: if you accidentally delete a
// lot of text and save, you can still recover earlier prose by unzipping the file.
// Markdown is tiny, so keeping many costs almost nothing.
public struct HistorySnapshot: Equatable {
    public let timestamp: Date
    public let markdown: String
    public init(timestamp: Date, markdown: String) {
        self.timestamp = timestamp
        self.markdown = markdown
    }
}

// Decides which snapshots to keep so backups stay dense for recent edits and thin
// out as they age (staggered cleanup): keep the most recent N always, then one per
// hour for the last day, one per day for the last month, one per week for the last
// year, and one per month beyond — capped to a maximum.
public enum HistoryPruner {

    /// Adds the current Markdown as a new snapshot (unless identical to the most
    /// recent) and prunes per the retention policy. Returns snapshots sorted oldest→newest.
    public static func updated(history: [HistorySnapshot], addingMarkdown markdown: String,
                               now: Date) -> [HistorySnapshot] {
        var snapshots = history
        let newest = snapshots.max(by: { $0.timestamp < $1.timestamp })
        if newest?.markdown != markdown {
            // Entry names have one-second granularity (see entryName), so two saves in
            // the same second would collide into one ZIP entry name. Nudge the new
            // snapshot forward whole seconds until its name is unique (2.8). A few
            // seconds' drift doesn't perturb the age-based pruning buckets below.
            let takenNames = Set(snapshots.map { entryName(for: $0.timestamp) })
            var stamp = now
            while takenNames.contains(entryName(for: stamp)) {
                stamp = stamp.addingTimeInterval(1)
            }
            snapshots.append(HistorySnapshot(timestamp: stamp, markdown: markdown))
        }
        let keepDates = keep(timestamps: snapshots.map(\.timestamp), now: now)
        return snapshots
            .filter { keepDates.contains($0.timestamp) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// The subset of timestamps to retain (newest-first tiers).
    public static func keep(timestamps: [Date], now: Date,
                            recent: Int = 12, maxCount: Int = 120) -> Set<Date> {
        let sorted = timestamps.sorted(by: >)     // newest first
        var kept: [Date] = []
        var seenBuckets = Set<String>()
        for (index, timestamp) in sorted.enumerated() {
            if index < recent {
                kept.append(timestamp)
                continue
            }
            let bucket = bucketKey(timestamp, age: now.timeIntervalSince(timestamp))
            if seenBuckets.insert(bucket).inserted {
                kept.append(timestamp)
            }
        }
        if kept.count > maxCount { kept = Array(kept.prefix(maxCount)) }
        return Set(kept)
    }

    private static func bucketKey(_ timestamp: Date, age: TimeInterval) -> String {
        let t = timestamp.timeIntervalSince1970
        let day: TimeInterval = 86_400
        if age < day { return "h\(Int(t / 3600))" }            // hourly for the last day
        if age < 30 * day { return "d\(Int(t / day))" }        // daily for the last month
        if age < 365 * day { return "w\(Int(t / (7 * day)))" } // weekly for the last year
        return "M\(Int(t / (30 * day)))"                       // ~monthly beyond
    }

    // MARK: - history/ entry names (history/<UTC timestamp>.md)

    public static let directory = "history/"

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public static func entryName(for timestamp: Date) -> String {
        directory + formatter.string(from: timestamp) + ".md"
    }

    public static func timestamp(fromEntryName name: String) -> Date? {
        guard name.hasPrefix(directory), name.hasSuffix(".md") else { return nil }
        let stem = String(name.dropFirst(directory.count).dropLast(3))
        return formatter.date(from: stem)
    }
}
