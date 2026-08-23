import AppKit
import LucerneCore

// The AppKit face of the exclusion geometry: the portable rect math lives in
// LucerneCore (Layout/ExclusionRects.swift); this extension wraps each rect in
// the NSBezierPath that NSTextContainer.exclusionPaths consumes.
public extension ExclusionPathController {

    /// Exclusion paths (in container coordinates) for every page-anchored, wrapping
    /// object on `pageIndex` — one rectangular path per `exclusionRects` entry.
    static func exclusionPaths(forPage pageIndex: Int,
                               objects: [PlacedObject],
                               metrics: PageMetrics) -> [NSBezierPath] {
        exclusionRects(forPage: pageIndex, objects: objects, metrics: metrics)
            .map { NSBezierPath(rect: $0) }
    }
}
