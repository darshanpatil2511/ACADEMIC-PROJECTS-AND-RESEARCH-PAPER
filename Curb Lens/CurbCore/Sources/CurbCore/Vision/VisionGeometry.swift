import CoreGraphics

/// Four corners of a detected sign, normalized 0...1 with Vision's origin at the BOTTOM-left.
public struct Quad: Hashable, Sendable, Codable {
    /// Normalized corner (Vision coordinates: origin bottom-left).
    public var topLeft: CGPoint
    public var topRight: CGPoint
    public var bottomRight: CGPoint
    public var bottomLeft: CGPoint

    public init(topLeft: CGPoint, topRight: CGPoint, bottomRight: CGPoint, bottomLeft: CGPoint) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    /// The whole image.
    public static let unit = Quad(topLeft: CGPoint(x: 0, y: 1), topRight: CGPoint(x: 1, y: 1),
                                  bottomRight: CGPoint(x: 1, y: 0), bottomLeft: CGPoint(x: 0, y: 0))

    /// Corners clockwise from the top left.
    public var corners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Area by the shoelace formula (normalized units).
    public var area: CGFloat {
        let p = corners
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Maps a point in the perspective-corrected sign (unit square, bottom-left origin) back into this
    /// quad. Uses the square-to-quad homography (Heckbert 1989), so it is exact for perspective, not
    /// just an approximation. Used to draw text boxes found on the corrected crop onto the original photo.
    public func project(_ p: CGPoint) -> CGPoint {
        let (x0, y0) = (bottomLeft.x, bottomLeft.y)
        let (x1, y1) = (bottomRight.x, bottomRight.y)
        let (x2, y2) = (topRight.x, topRight.y)
        let (x3, y3) = (topLeft.x, topLeft.y)
        let sx = x0 - x1 + x2 - x3
        let sy = y0 - y1 + y2 - y3

        var g: CGFloat = 0, h: CGFloat = 0
        let a, b, d, e: CGFloat
        if abs(sx) < 1e-12 && abs(sy) < 1e-12 {
            // Parallelogram: the mapping is affine.
            a = x1 - x0; b = x3 - x0
            d = y1 - y0; e = y3 - y0
        } else {
            let dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2
            let den = dx1 * dy2 - dx2 * dy1
            if abs(den) > 1e-12 {
                g = (sx * dy2 - dx2 * sy) / den
                h = (dx1 * sy - sx * dy1) / den
            }
            a = x1 - x0 + g * x1; b = x3 - x0 + h * x3
            d = y1 - y0 + g * y1; e = y3 - y0 + h * y3
        }
        let w = g * p.x + h * p.y + 1
        return CGPoint(x: (a * p.x + b * p.y + x0) / w, y: (d * p.x + e * p.y + y0) / w)
    }

    /// Projects a rect from the corrected crop into this quad (returns the bounding box of the 4 projected corners).
    public func project(_ rect: CGRect) -> CGRect {
        let pts = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                   CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)].map(project)
        let xs = pts.map(\.x), ys = pts.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return rect }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Coordinate conversions between Vision's normalized space and pixel spaces.
///
/// Vision: normalized 0...1, origin BOTTOM-left.
/// Core Image: pixels, origin BOTTOM-left (same direction as Vision — scale only).
/// UIKit / SwiftUI / CGImage drawing: pixels, origin TOP-left (y must be flipped).
public enum VisionGeometry {
    /// Where the target coordinate system's origin is.
    public enum Origin: Sendable {
        case bottomLeft   // Core Image
        case topLeft      // UIKit, SwiftUI, image pixel rows
    }

    /// Converts a Vision point (normalized, bottom-left origin) to pixels in an image of `imageSize`.
    public static func pixelPoint(_ normalized: CGPoint, imageSize: CGSize, origin: Origin) -> CGPoint {
        let x = normalized.x * imageSize.width
        switch origin {
        case .bottomLeft: return CGPoint(x: x, y: normalized.y * imageSize.height)
        case .topLeft: return CGPoint(x: x, y: (1 - normalized.y) * imageSize.height)
        }
    }

    /// Converts a Vision rect (normalized, bottom-left origin) to pixels in an image of `imageSize`.
    public static func pixelRect(_ normalized: CGRect, imageSize: CGSize, origin: Origin) -> CGRect {
        let width = normalized.width * imageSize.width
        let height = normalized.height * imageSize.height
        let x = normalized.minX * imageSize.width
        switch origin {
        case .bottomLeft:
            return CGRect(x: x, y: normalized.minY * imageSize.height, width: width, height: height)
        case .topLeft:
            return CGRect(x: x, y: (1 - normalized.maxY) * imageSize.height, width: width, height: height)
        }
    }
}
