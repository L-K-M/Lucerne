import AppKit

// Turns the model's placed objects into NSBezierPath exclusion paths for a given
// page's text container. This is the bridge that makes free placement work: the
// layout engine flows text around whatever paths we hand it (plan §3, Avenue A).
public enum ExclusionPathController {

    /// Exclusion paths (in container coordinates) for every page-anchored, wrapping
    /// object on `pageIndex`. Objects with `wrap == "none"` are overlays and
    /// contribute nothing; paragraph-anchored objects are not handled here (v1).
    public static func exclusionPaths(forPage pageIndex: Int,
                                      objects: [PlacedObject],
                                      metrics: PageMetrics) -> [NSBezierPath] {
        objects
            .filter { $0.anchorMode == .page && $0.page == pageIndex && $0.wrapMode != .none }
            .sorted { $0.z < $1.z }
            .compactMap { object in
                guard let frame = object.frame else { return nil }
                let rect = metrics.exclusionRect(forObjectFrame: frame, standoff: object.standoff)
                switch object.wrapMode {
                case .rectangular, .irregular:
                    // Irregular (alpha-outline) wrap is modelled but falls back to
                    // the bounding rectangle until that feature lands.
                    return NSBezierPath(rect: rect)
                case .none:
                    return nil
                }
            }
    }
}
