import AppKit

// Turns the model's placed objects into NSBezierPath exclusion paths for a given
// page's text container. This is the bridge that makes free placement work: the
// layout engine flows text around whatever paths we hand it (plan §3, Avenue A).
public enum ExclusionPathController {

    /// Exclusion rectangles (in **text-container** coordinates) for every
    /// page-anchored, wrapping object on `pageIndex`. Objects with `wrap == "none"`
    /// are overlays and contribute nothing; paragraph-anchored objects are not
    /// handled here (v1). Exposed alongside `exclusionPaths` so callers can cheaply
    /// diff the rect lists before reassigning paths — assigning `exclusionPaths`
    /// invalidates layout unconditionally, so skipping no-op reassignments matters.
    public static func exclusionRects(forPage pageIndex: Int,
                                      objects: [PlacedObject],
                                      metrics: PageMetrics) -> [CGRect] {
        objects
            .filter { $0.anchorMode == .page && $0.page == pageIndex && $0.wrapMode != .none }
            .sorted { $0.z < $1.z }
            .compactMap { object in
                guard let frame = object.frame else { return nil }
                // Irregular (alpha-outline) wrap is modelled but falls back to the
                // bounding rectangle until that feature lands, so both wrapping
                // modes reduce to the same exclusion rect here.
                return metrics.exclusionRect(forObjectFrame: frame, standoff: object.standoff)
            }
    }

    /// Exclusion paths (in container coordinates) for every page-anchored, wrapping
    /// object on `pageIndex` — one rectangular path per `exclusionRects` entry.
    public static func exclusionPaths(forPage pageIndex: Int,
                                      objects: [PlacedObject],
                                      metrics: PageMetrics) -> [NSBezierPath] {
        exclusionRects(forPage: pageIndex, objects: objects, metrics: metrics)
            .map { NSBezierPath(rect: $0) }
    }
}
