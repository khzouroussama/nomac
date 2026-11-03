import Foundation

/// A stroke's outline as polygons to fill with the nonzero rule: a quadrilateral per segment,
/// a join at each inner vertex (and at the start of a closed subpath), a cap at each end of an
/// open one, every polygon turning the same way so that their union fills. CoreSVG's pixels
/// differ from these (ADR 0204); the shape follows SVG's stroke properties.
enum SVGStroke {
    typealias Point = SVGImage.Point

    static func outline(_ subpaths: [(points: [Point], closed: Bool)], width: Double, cap: String, join: String, miterLimit: Double) -> [[Point]] {
        let half = width / 2
        var polygons: [[Point]] = []
        for subpath in subpaths {
            var points: [Point] = []
            for point in subpath.points where points.last.map({ $0.x != point.x || $0.y != point.y }) ?? true { points.append(point) }
            if subpath.closed, points.count > 2, let first = points.first, let last = points.last, first.x == last.x, first.y == last.y { points.removeLast() }
            guard points.count > 1 else {
                if let point = points.first, cap != "butt" { polygons.append(dot(point, half: half, round: cap == "round")) }
                continue
            }
            let closed = subpath.closed && points.count > 2
            let count = closed ? points.count : points.count - 1
            for index in 0..<count {
                let a = points[index], b = points[(index + 1) % points.count]
                var (start, end) = (a, b)
                let direction = unit(a, b)
                if !closed && cap == "square" {
                    if index == 0 { start = Point(x: a.x - direction.x * half, y: a.y - direction.y * half) }
                    if index == count - 1 { end = Point(x: b.x + direction.x * half, y: b.y + direction.y * half) }
                }
                let normal = Point(x: -direction.y * half, y: direction.x * half)
                polygons.append([Point(x: start.x + normal.x, y: start.y + normal.y), Point(x: end.x + normal.x, y: end.y + normal.y),
                                 Point(x: end.x - normal.x, y: end.y - normal.y), Point(x: start.x - normal.x, y: start.y - normal.y)])
            }
            let joints = closed ? Array(0..<points.count) : Array(1..<points.count - 1)
            for index in joints {
                let previous = points[(index - 1 + points.count) % points.count], vertex = points[index], next = points[(index + 1) % points.count]
                polygons.append(contentsOf: self.join(previous, vertex, next, half: half, join: join, miterLimit: miterLimit))
            }
            if !closed && cap == "round" {
                polygons.append(dot(points[0], half: half, round: true))
                polygons.append(dot(points[points.count - 1], half: half, round: true))
            }
        }
        return polygons.map(counterClockwise)
    }

    static func unit(_ a: Point, _ b: Point) -> Point {
        let dx = b.x - a.x, dy = b.y - a.y, length = (dx * dx + dy * dy).squareRoot()
        return length > 0 ? Point(x: dx / length, y: dy / length) : Point(x: 1, y: 0)
    }

    /// The join at `vertex` between the segments from `previous` and to `next`: a round one, a
    /// miter while the miter length over the stroke width stays within the limit, else a bevel.
    static func join(_ previous: Point, _ vertex: Point, _ next: Point, half: Double, join: String, miterLimit: Double) -> [[Point]] {
        let d0 = unit(previous, vertex), d1 = unit(vertex, next)
        let cross = d0.x * d1.y - d0.y * d1.x
        guard abs(cross) > 1e-12 || d0.x * d1.x + d0.y * d1.y < 0 else { return [] }
        if join == "round" { return [dot(vertex, half: half, round: true)] }
        // The outer side of the turn.
        let side: Double = cross > 0 ? -1 : 1
        let n0 = Point(x: -d0.y * half * side, y: d0.x * half * side), n1 = Point(x: -d1.y * half * side, y: d1.x * half * side)
        let a = Point(x: vertex.x + n0.x, y: vertex.y + n0.y), b = Point(x: vertex.x + n1.x, y: vertex.y + n1.y)
        let cosine = max(-1, min(1, -(d0.x * d1.x + d0.y * d1.y)))
        let theta = acos(cosine)
        if join == "miter" || join == "miter-clip", theta > 1e-9, 1 / sin(theta / 2) <= miterLimit {
            let bisector = unit(vertex, Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
            let length = half / sin(theta / 2)
            return [[vertex, a, Point(x: vertex.x + bisector.x * length, y: vertex.y + bisector.y * length), b]]
        }
        return [[vertex, a, b]]
    }

    /// A circle (or a square, for square caps of a lone point) of radius `half`.
    static func dot(_ center: Point, half: Double, round: Bool) -> [Point] {
        guard round else {
            return [Point(x: center.x - half, y: center.y - half), Point(x: center.x + half, y: center.y - half),
                    Point(x: center.x + half, y: center.y + half), Point(x: center.x - half, y: center.y + half)]
        }
        return SVGPath.ellipse(cx: center.x, cy: center.y, rx: half, ry: half)
    }

    static func counterClockwise(_ polygon: [Point]) -> [Point] {
        var area = 0.0
        for index in polygon.indices {
            let a = polygon[index], b = polygon[(index + 1) % polygon.count]
            area += a.x * b.y - b.x * a.y
        }
        return area < 0 ? polygon.reversed() : polygon
    }
}
