import Foundation

// Plain, platform-independent geometry value types used by the document model.
// These deliberately avoid CoreGraphics so the model layer stays AppKit-free and
// testable anywhere. Conversions to CGRect/NSRect happen in the view layer.
//
// Units are points (1/72") and the coordinate origin is the page top-left with y
// increasing downward — see lucerne-plan.md §7 ("Conventions worth fixing now").

public struct PointModel: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct SizeModel: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct RectModel: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var origin: PointModel { PointModel(x: x, y: y) }
    public var size: SizeModel { SizeModel(width: width, height: height) }

    /// Returns a copy inset (negative = expanded) on all sides by `amount`.
    public func insetBy(_ amount: Double) -> RectModel {
        RectModel(x: x + amount,
                  y: y + amount,
                  width: width - 2 * amount,
                  height: height - 2 * amount)
    }

    /// Returns a copy translated by (dx, dy).
    public func offsetBy(dx: Double, dy: Double) -> RectModel {
        RectModel(x: x + dx, y: y + dy, width: width, height: height)
    }

    /// Intersection with another rect, or nil if they do not overlap.
    public func intersection(_ other: RectModel) -> RectModel? {
        let nx = max(minX, other.minX)
        let ny = max(minY, other.minY)
        let mx = min(maxX, other.maxX)
        let my = min(maxY, other.maxY)
        guard mx > nx, my > ny else { return nil }
        return RectModel(x: nx, y: ny, width: mx - nx, height: my - ny)
    }

    public func intersects(_ other: RectModel) -> Bool {
        intersection(other) != nil
    }
}

public struct EdgeInsetsModel: Codable, Equatable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let zero = EdgeInsetsModel(top: 0, left: 0, bottom: 0, right: 0)

    public static func uniform(_ v: Double) -> EdgeInsetsModel {
        EdgeInsetsModel(top: v, left: v, bottom: v, right: v)
    }
}
