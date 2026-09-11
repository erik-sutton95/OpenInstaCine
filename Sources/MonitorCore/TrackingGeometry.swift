import Foundation

/// Normalized 0…1 tracking box. Stored as top-left origin + size for drawing.
/// The wire (`0x02/0xA6` SET and `0x02/0x89` push) is **centre + size** —
/// Mimo 2026-08-18: drawing origin-as-centre put the top-left on the face.
public struct TrackingBox: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    /// Expand floor for a degenerate drag. Not the Mimo accept threshold.
    public static let minimumNormalizedSize: Double = 0.05

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var centerX: Double { x + width / 2 }
    public var centerY: Double { y + height / 2 }
    public var area: Double { width * height }
    public func intersectionArea(_ other: TrackingBox) -> Double {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        return max(0, x1 - x0) * max(0, y1 - y0)
    }

    public func intersectionOverUnion(_ other: TrackingBox) -> Double {
        let inter = intersectionArea(other)
        let union = area + other.area - inter
        guard union > 0 else { return 0 }
        return inter / union
    }

    public func contains(x: Double, y: Double, padding: Double = 0) -> Bool {
        x >= minX - padding && x <= maxX + padding
            && y >= minY - padding && y <= maxY + padding
    }

    /// Axis-aligned union. Used to size the painted lock from face + pose extent.
    public func union(_ other: TrackingBox) -> TrackingBox {
        let x0 = min(minX, other.minX)
        let y0 = min(minY, other.minY)
        return TrackingBox(
            x: x0, y: y0,
            width: max(maxX, other.maxX) - x0,
            height: max(maxY, other.maxY) - y0)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static func normalized(
        fromX: Double, fromY: Double, toX: Double, toY: Double
    ) -> TrackingBox {
        var x0 = min(max(min(fromX, toX), 0), 1)
        var y0 = min(max(min(fromY, toY), 0), 1)
        var x1 = min(max(max(fromX, toX), 0), 1)
        var y1 = min(max(max(fromY, toY), 0), 1)
        if x1 < x0 { swap(&x0, &x1) }
        if y1 < y0 { swap(&y0, &y1) }
        return TrackingBox(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public static func fromCenter(
        x: Double, y: Double, width: Double, height: Double
    ) -> TrackingBox {
        let w = min(max(width, 0.02), 1)
        let h = min(max(height, 0.02), 1)
        return TrackingBox(x: x - w / 2, y: y - h / 2, width: w, height: h)
    }

    /// Tighter box at the search centre — stand-in until `0xA5` carries a live subject rect.
    public static func subject(from search: TrackingBox) -> TrackingBox {
        let width = min(max(search.width * 0.45, minimumNormalizedSize), search.width)
        let height = min(max(search.height * 0.45, minimumNormalizedSize), search.height)
        return TrackingBox(
            x: search.x + (search.width - width) / 2,
            y: search.y + (search.height - height) / 2,
            width: width,
            height: height
        )
    }

}

/// Ease the painted box toward each `0x89` (~15 Hz). Size is slower than
/// centre so subject motion stays tight while bounding-box flicker settles.
public enum TrackingBoxSmoothing {
    public static let positionTimeConstant: Double = 0.10
    public static let sizeTimeConstant: Double = 0.42

    /// Face AF is sampled slower than the feed. Tick the painted box toward
    /// the last hit on every frame so it does not sit-and-jump.
    public static let facePositionTimeConstant: Double = 0.16
    public static let faceSizeTimeConstant: Double = 0.70

    public static func blend(
        from: TrackingBox?, toward: TrackingBox, dt: Double,
        position: Double = positionTimeConstant,
        size: Double = sizeTimeConstant
    ) -> TrackingBox {
        guard let from, dt > 0, dt.isFinite else { return toward }
        let p = 1 - exp(-dt / max(position, 0.001))
        let s = 1 - exp(-dt / max(size, 0.001))
        let cx = from.centerX + (toward.centerX - from.centerX) * p
        let cy = from.centerY + (toward.centerY - from.centerY) * p
        let w = from.width + (toward.width - from.width) * s
        let h = from.height + (toward.height - from.height) * s
        return TrackingBox.fromCenter(x: cx, y: cy, width: w, height: h)
    }
}
