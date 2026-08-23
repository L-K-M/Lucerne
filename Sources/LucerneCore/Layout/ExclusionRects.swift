#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation   // swift-corelibs-foundation provides CGFloat/CGPoint/CGSize/CGRect on Linux
#endif

// Turns the model's placed objects into exclusion rectangles for a given page's
// text container. This is the bridge that makes free placement work: the layout
// engine flows text around whatever regions we hand it (plan §3, Avenue A). The
// AppKit half (NSBezierPath construction) lives in LucerneKit; the geometry here
// is platform-independent so ports share one definition of "where text may not go".
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
}
