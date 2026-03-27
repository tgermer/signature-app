import Foundation
import PencilKit
import UIKit

/// Generates EMF (Enhanced Metafile Format) binary data from a PencilKit drawing.
/// Implements a subset of the MS-EMF specification entirely on-device.
/// No external servers or libraries required.
///
/// Coordinate system: device pixels (96 DPI, 1× canvas size).
/// Scale from 2× canvas pts → 0.5 (divide by 2).
/// Physical size: 60 × 30 mm → 227 × 114 px at 96 DPI.
struct EMFExporter {

    // 2× canvas (0…453.544 pts) → device pixels (0…226)
    private static let scale: CGFloat = 0.5
    private static let emfW:  Int32   = 227   // px at 96 DPI for 60 mm
    private static let emfH:  Int32   = 114   // px at 96 DPI for 30 mm

    // MARK: - Public API

    static func generate(drawing: PKDrawing, strokeColor: UIColor, strokeWidth: CGFloat) -> Data {
        var g = EMFExporter()
        return g.build(drawing: drawing, color: strokeColor, width: strokeWidth)
    }

    // MARK: - State

    private var buf = Data()
    private var recordCount: UInt32 = 0

    // MARK: - Build

    private mutating func build(drawing: PKDrawing, color: UIColor, width: CGFloat) -> Data {
        let headerStart = buf.count
        appendHeader()
        appendCreatePen(handle: 1, color: color, width: width)
        appendSelectObject(handle: 1)

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

    /// Convert 2×-canvas point to device pixel (integer).
    private func px(_ v: CGFloat) -> Int32 { Int32(v * Self.scale) }

    // MARK: - EMF Records

    /// EMR_HEADER (type 1) — 108 bytes
    private mutating func appendHeader() {
        u32(1)    // iType
        u32(108)  // nSize
        // rclBounds: inclusive bounding rect in device pixels
        rect(0, 0, Self.emfW - 1, Self.emfH - 1)
        // rclFrame: inclusive bounding rect in 0.01 mm (60×30 mm)
        rect(0, 0, 5999, 2999)
        u32(0x464D4520)   // dSignature = " EMF"
        u32(0x00010000)   // nVersion
        u32(0)            // nBytes     — patched later
        u32(0)            // nRecords   — patched later
        u16(1)            // nHandles   (1 pen)
        u16(0)            // sReserved
        u32(0); u32(0)    // nDescription, offDescription
        u32(0)            // nPalEntries
        size2(Self.emfW, Self.emfH)  // szlDevice (px)
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

    /// EMR_CREATEPEN (type 38) — 28 bytes.
    /// Cosmetic solid pen; round caps come from GDI's default for polylines.
    private mutating func appendCreatePen(handle: UInt32, color: UIColor, width: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // EMF COLORREF = 0x00BBGGRR
        let colorRef = UInt32(b * 255) << 16 | UInt32(g * 255) << 8 | UInt32(r * 255)
        // width is in 2×-canvas pts; convert to 1× device pixels
        let penW = max(1, Int32(width * Self.scale))

        u32(38); u32(28)        // iType: EMR_CREATEPEN, nSize
        u32(handle)
        u32(0)                  // lopnStyle: PS_SOLID
        i32(penW); i32(0)       // lopnWidth: x = width, y ignored for cosmetic pen
        u32(colorRef)
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

    /// EMR_MOVETOEX (type 27) — 16 bytes. Sets current position without drawing.
    private mutating func appendMoveToEx(_ x: Int32, _ y: Int32) {
        u32(27); u32(16); i32(x); i32(y)
        recordCount += 1
    }

    /// EMR_POLYLINETO (type 6) — draws line segments from current position.
    private mutating func appendPolyLineTo(_ points: [(Int32, Int32)]) {
        guard !points.isEmpty else { return }
        var minX = points[0].0, minY = points[0].1
        var maxX = minX, maxY = minY
        for (x, y) in points {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
        u32(6)
        u32(UInt32(28 + points.count * 8))
        rect(minX, minY, maxX, maxY)
        u32(UInt32(points.count))
        for (x, y) in points { i32(x); i32(y) }
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

    // MARK: - Stroke rendering

    private mutating func appendStroke(_ pts: [PKStrokePoint]) {
        appendMoveToEx(px(pts[0].location.x), px(pts[0].location.y))

        if pts.count == 1 {
            appendPolyLineTo([(px(pts[0].location.x), px(pts[0].location.y))])
        } else {
            // Midpoint spline: actual sample points become "pull-through" waypoints,
            // midpoints between them become line endpoints — matches SVG/PDF smoothing.
            var linePts: [(Int32, Int32)] = []
            for i in 0..<pts.count - 1 {
                let p = pts[i].location, q = pts[i + 1].location
                linePts.append((px((p.x + q.x) / 2), px((p.y + q.y) / 2)))
            }
            linePts.append((px(pts.last!.location.x), px(pts.last!.location.y)))
            appendPolyLineTo(linePts)
        }
    }
}
