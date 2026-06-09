import CoreGraphics

// Bridges between the AppKit-free model geometry and CoreGraphics types, kept at
// the boundary so the model stays portable.
public extension RectModel {
    init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.size.width), height: Double(rect.size.height))
    }
    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

public extension PointModel {
    init(_ point: CGPoint) { self.init(x: Double(point.x), y: Double(point.y)) }
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}
