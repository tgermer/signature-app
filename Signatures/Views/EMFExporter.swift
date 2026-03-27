import Foundation
import PencilKit
import UIKit

/// Generates EMF (Enhanced Metafile Format) binary data from a PencilKit drawing.
/// Implements a subset of the MS-EMF specification entirely on-device.
/// No external servers or libraries required.
///
/// Coordinate system: uses 4× the original 96 DPI pixel density for
/// sub-pixel precision in polygon vertices, avoiding integer-quantization jagginess.
/// Physical size: 60 × 30 mm → 908 × 454 internal units.
///
/// Variable stroke width: uses PKStrokePoint.size (pressure/tilt) to build
/// filled outline polygons with Chaikin-smoothed edges.
struct EMFExporter {

    // 2× canvas (0…453.544 pts) → high-res EMF units
    // scale = 2.0 gives 4× more precision than the 96-DPI pixel baseline
    private static let scale: CGFloat = 2.0
    private static let emfW:  Int32   = 908   // 453.544 × 2 ≈ 908
    private static let emfH:  Int32   = 454   // 226.772 × 2 ≈ 454

    // MARK: - Public API

    static func generate(drawing: PKDrawing, strokeColor: UIColor, strokeWidth: CGFloat) -> Data {
        var g = EMFExporter()
        return g.build(drawing: drawing, color: strokeColor)
    }

    // MARK: - State

    private var buf = Data()
    private var recordCount: UInt32 = 0

    // MARK: - Build

    private mutating func build(drawing: PKDrawing, color: UIColor) -> Data {
        let headerStart = buf.count
        appendHeader()
        appendCreateBrush(handle: 1, color: color)
        appendSelectObject(handle: 0x80000008)  // NULL_PEN stock object (no outline)
        appendSelectObject(handle: 1)           // our solid brush

        for stroke in drawing.strokes {
            let pts = Array(stroke.path)
            guard !pts.isEmpty else { continue }
            appendStroke(pts)
        }

        appendDeleteObject(handle: 1)
        appendEOF()
        patchHeader(at: headerStart)
        return buf
    }

    // MARK: - Low-level write helpers

    private mutating func u32(_ v: UInt32) {
        withUnsafeBytes(of: v.littleEndian) { buf.append(contentsOf: $0) }
    }
    private mutating func i32(_ v: Int32)  { u32(UInt32(bitPattern: v)) }
    private mutating func u16(_ v: UInt16) {
        withUnsafeBytes(of: v.littleEndian) { buf.append(contentsOf: $0) }
    }
    private mutating func rect(_ l: Int32, _ t: Int32, _ r: Int32, _ b: Int32) {
        i32(l); i32(t); i32(r); i32(b)
    }
    private mutating func size2(_ cx: Int32, _ cy: Int32) { i32(cx); i32(cy) }

    /// Convert 2×-canvas coordinate to high-res EMF unit.
    private func px(_ v: CGFloat) -> Int32 { Int32(v * Self.scale) }

    // MARK: - EMF Records

    /// EMR_HEADER (type 1) — 108 bytes
    private mutating func appendHeader() {
        u32(1)    // iType
        u32(108)  // nSize
        // rclBounds: inclusive bounding rect in internal units
        rect(0, 0, Self.emfW - 1, Self.emfH - 1)
        // rclFrame: inclusive bounding rect in 0.01 mm (60×30 mm)
        rect(0, 0, 5999, 2999)
        u32(0x464D4520)   // dSignature = " EMF"
        u32(0x00010000)   // nVersion
        u32(0)            // nBytes     — patched later
        u32(0)            // nRecords   — patched later
        u16(1)            // nHandles   (1 brush)
        u16(0)            // sReserved
        u32(0); u32(0)    // nDescription, offDescription
        u32(0)            // nPalEntries
        size2(Self.emfW, Self.emfH)  // szlDevice (internal units)
        size2(60, 30)                // szlMillimeters
        u32(0); u32(0)               // cbPixelFormat, offPixelFormat
        u32(0)                       // bOpenGL
        size2(60000, 30000)          // szlMicrometers
        recordCount += 1
    }

    private mutating func patchHeader(at off: Int) {
        func patch(_ v: UInt32, byteOffset: Int) {
            withUnsafeBytes(of: v.littleEndian) { bytes in
                for (i, b) in bytes.enumerated() { buf[off + byteOffset + i] = b }
            }
        }
        patch(UInt32(buf.count), byteOffset: 48) // nBytes
        patch(recordCount,       byteOffset: 52) // nRecords
    }

    /// EMR_CREATEBRUSHINDIRECT (type 39) — 24 bytes. Solid fill brush.
    private mutating func appendCreateBrush(handle: UInt32, color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let colorRef = UInt32(b * 255) << 16 | UInt32(g * 255) << 8 | UInt32(r * 255)

        u32(39); u32(24)   // iType: EMR_CREATEBRUSHINDIRECT, nSize
        u32(handle)        // ihBrush
        u32(0)             // lbStyle: BS_SOLID
        u32(colorRef)      // lbColor: COLORREF
        u32(0)             // lbHatch
        recordCount += 1
    }

    /// EMR_SELECTOBJECT (type 37) — 12 bytes
    private mutating func appendSelectObject(handle: UInt32) {
        u32(37); u32(12); u32(handle)
        recordCount += 1
    }

    /// EMR_DELETEOBJECT (type 40) — 12 bytes
    private mutating func appendDeleteObject(handle: UInt32) {
        u32(40); u32(12); u32(handle)
        recordCount += 1
    }

    /// EMR_POLYGON (type 3) — filled closed polygon using current brush.
    private mutating func appendPolygon(_ points: [(Int32, Int32)]) {
        guard !points.isEmpty else { return }
        var minX = points[0].0, minY = points[0].1
        var maxX = minX, maxY = minY
        for (x, y) in points {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
        u32(3)
        u32(UInt32(28 + points.count * 8))
        rect(minX, minY, maxX, maxY)
        u32(UInt32(points.count))
        for (x, y) in points { i32(x); i32(y) }
        recordCount += 1
    }

    /// EMR_ELLIPSE (type 42) — filled ellipse (circle) using current brush.
    private mutating func appendEllipse(_ cx: Int32, _ cy: Int32, _ r: Int32) {
        u32(42); u32(24)
        rect(cx - r, cy - r, cx + r, cy + r)
        recordCount += 1
    }

    /// EMR_EOF (type 14) — 20 bytes
    private mutating func appendEOF() {
        u32(14); u32(20)
        u32(0)   // nPalEntries
        u32(20)  // offPalEntries
        u32(20)  // nSizeLast
        recordCount += 1
    }

    // MARK: - Stroke rendering (variable width + smooth edges)

    private mutating func appendStroke(_ pts: [PKStrokePoint]) {
        let n = pts.count - 1

        if pts.count == 1 {
            let p = pts[0]
            let r = max(Int32(p.size.width * Self.scale / 2.0), 1)
            appendEllipse(px(p.location.x), px(p.location.y), r)
            return
        }

        // Compute left/right outline edge points in canvas coordinates
        var Lf: [CGPoint] = [], Rf: [CGPoint] = []
        for i in 0...n {
            let loc   = pts[i].location
            let halfW = max(pts[i].size.width, 0.5) / 2.0
            let t     = tangentAt(i, pts: pts)
            let norm  = CGPoint(x: -t.y, y: t.x)
            Lf.append(CGPoint(x: loc.x + norm.x * halfW, y: loc.y + norm.y * halfW))
            Rf.append(CGPoint(x: loc.x - norm.x * halfW, y: loc.y - norm.y * halfW))
        }

        // Convert to integer EMF units and apply one Chaikin smoothing pass
        let L = chaikin(Lf.map { (px($0.x), px($0.y)) })
        let R = chaikin(Rf.map { (px($0.x), px($0.y)) })

        // Build polygon: left edge forward + right edge backward
        var poly: [(Int32, Int32)] = []
        poly.append(contentsOf: L)
        poly.append(contentsOf: R.reversed())
        appendPolygon(poly)

        // Round caps as filled circles
        let rStart = max(Int32(pts[0].size.width * Self.scale / 2.0), 1)
        let rEnd   = max(Int32(pts[n].size.width * Self.scale / 2.0), 1)
        appendEllipse(px(pts[0].location.x), px(pts[0].location.y), rStart)
        appendEllipse(px(pts[n].location.x), px(pts[n].location.y), rEnd)
    }

    // MARK: - Smoothing & vector helpers

    /// One iteration of Chaikin's corner-cutting algorithm.
    /// Approximates a smooth quadratic B-spline while preserving exact endpoints.
    private func chaikin(_ pts: [(Int32, Int32)]) -> [(Int32, Int32)] {
        guard pts.count >= 3 else { return pts }
        var result: [(Int32, Int32)] = [pts.first!]
        for i in 0..<pts.count - 1 {
            let (x0, y0) = pts[i], (x1, y1) = pts[i + 1]
            result.append(((3 * x0 + x1) / 4, (3 * y0 + y1) / 4))
            result.append(((x0 + 3 * x1) / 4, (y0 + 3 * y1) / 4))
        }
        result.append(pts.last!)
        return result
    }

    private func tangentAt(_ i: Int, pts: [PKStrokePoint]) -> CGPoint {
        let count = pts.count
        let a: CGPoint, b: CGPoint
        if i == 0            { (a, b) = (pts[0].location,         pts[1].location)         }
        else if i == count-1 { (a, b) = (pts[count-2].location,   pts[count-1].location)   }
        else                 { (a, b) = (pts[i-1].location,       pts[i+1].location)       }
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1e-12 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: dx / len, y: dy / len)
    }
}
