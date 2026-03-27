import Foundation
import PencilKit
import UIKit

/// Generates EMF (Enhanced Metafile Format) binary data from a PencilKit drawing.
/// Implements a subset of the MS-EMF specification entirely on-device.
/// No external servers or libraries required.
struct EMFExporter {

    // 2x canvas coordinates (0…453.544 pts wide) → 0.01mm EMF units (0…6000)
    private static let ptToEMF: CGFloat = 6000.0 / (226.772 * 2)

    private static let emfW: Int32 = 6000  // 60mm in 0.01mm
    private static let emfH: Int32 = 3000  // 30mm in 0.01mm

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

        // Handle 1: geometric pen with round caps and joins
        appendExtCreatePen(handle: 1, color: color, width: width)
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

    /// Convert 2x-canvas point coordinate to 0.01mm EMF unit.
    private func emf(_ v: CGFloat) -> Int32 { Int32(v * Self.ptToEMF) }

    // MARK: - EMF Records

    /// EMR_HEADER (type 1) — 108 bytes
    private mutating func appendHeader() {
        u32(1)    // iType
        u32(108)  // nSize
        rect(0, 0, 226, 113)                           // rclBounds  (pixels, 96 DPI for 60×30 mm)
        rect(0, 0, Self.emfW - 1, Self.emfH - 1)      // rclFrame   (0.01mm)
        u32(0x464D4520)   // dSignature = " EMF"
        u32(0x00010000)   // nVersion
        u32(0)            // nBytes     (patched later)
        u32(0)            // nRecords   (patched later)
        u16(1)            // nHandles   (1 pen)
        u16(0)            // sReserved
        u32(0); u32(0)    // nDescription, offDescription
        u32(0)            // nPalEntries
        size2(227, 114)   // szlDevice      (px, 96 DPI)
        size2(60, 30)     // szlMillimeters
        u32(0); u32(0)    // cbPixelFormat, offPixelFormat
        u32(0)            // bOpenGL
        size2(60000, 30000) // szlMicrometers
        recordCount += 1
    }

    /// Patch nBytes and nRecords into the already-written header.
    private mutating func patchHeader(at off: Int) {
        func patch(_ v: UInt32, byteOffset: Int) {
            withUnsafeBytes(of: v.littleEndian) { bytes in
                for (i, b) in bytes.enumerated() { buf[off + byteOffset + i] = b }
            }
        }
        patch(UInt32(buf.count), byteOffset: 48) // nBytes
        patch(recordCount,       byteOffset: 52) // nRecords
    }

    /// EMR_EXTCREATEPEN (type 95) — 52 bytes
    /// Creates a geometric pen with round end-caps and joins.
    private mutating func appendExtCreatePen(handle: UInt32, color: UIColor, width: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // EMF COLORREF is 0x00BBGGRR
        let colorRef = UInt32(b * 255) << 16 | UInt32(g * 255) << 8 | UInt32(r * 255)

        // Width is in 2x-canvas points; divide by 2 for 1x, then convert to 0.01mm.
        let penWidth = max(1, emf(width * 0.5))

        // elpPenStyle flags:
        let psGeometric:     UInt32 = 0x00010000
        let psSolid:         UInt32 = 0x00000000
        let psEndCapRound:   UInt32 = 0x00000100
        let psJoinRound:     UInt32 = 0x00001000
        let penStyle = psGeometric | psSolid | psEndCapRound | psJoinRound

        u32(95)  // iType: EMR_EXTCREATEPEN
        u32(52)  // nSize
        u32(handle)
        u32(0); u32(0)  // offBmi, cbBmi
        u32(0); u32(0)  // offBits, cbBits
        // EXTLOGPEN:
        u32(penStyle)   // elpPenStyle
        u32(UInt32(bitPattern: penWidth)) // elpWidth
        u32(0)          // elpBrushStyle = BS_SOLID
        u32(colorRef)   // elpColor
        u32(0)          // elpHatch (0 for BS_SOLID; stored as 4 bytes in EMF)
        u32(0)          // elpNumEntries
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

    /// EMR_POLYLINETO (type 6) — 28 + n×8 bytes.
    /// Draws line segments from current position through each point.
    private mutating func appendPolyLineTo(_ points: [(Int32, Int32)]) {
        guard !points.isEmpty else { return }
        var minX = points[0].0, minY = points[0].1
        var maxX = minX, maxY = minY
        for (x, y) in points {
            minX = min(minX, x); minY = min(minY, y)
            maxX = max(maxX, x); maxY = max(maxY, y)
        }
        u32(6)
        u32(UInt32(28 + points.count * 8))  // nSize
        rect(minX, minY, maxX, maxY)         // rclBounds
        u32(UInt32(points.count))
        for (x, y) in points { i32(x); i32(y) }
        recordCount += 1
    }

    /// EMR_BEGINPATH (type 59) — 8 bytes
    private mutating func appendBeginPath() { u32(59); u32(8); recordCount += 1 }

    /// EMR_ENDPATH (type 60) — 8 bytes
    private mutating func appendEndPath()   { u32(60); u32(8); recordCount += 1 }

    /// EMR_STROKEPATH (type 64) — 24 bytes. Strokes the current path with the selected pen.
    private mutating func appendStrokePath() {
        u32(64); u32(24)
        rect(0, 0, Self.emfW - 1, Self.emfH - 1)
        recordCount += 1
    }

    /// EMR_EOF (type 14) — 20 bytes
    private mutating func appendEOF() {
        u32(14); u32(20)
        u32(0)   // nPalEntries
        u32(20)  // offPalEntries (offset from record start)
        u32(20)  // nSizeLast (must equal nSize)
        recordCount += 1
    }

    // MARK: - Stroke rendering

    private mutating func appendStroke(_ pts: [PKStrokePoint]) {
        let fx = emf(pts[0].location.x)
        let fy = emf(pts[0].location.y)

        appendBeginPath()
        appendMoveToEx(fx, fy)

        if pts.count == 1 {
            appendPolyLineTo([(fx, fy)])
        } else {
            // Midpoint spline: use actual points as "pull-through" waypoints,
            // midpoints between them as line endpoints → smooth appearance
            // with enough PencilKit samples (same technique as SVG/PDF exports).
            var linePts: [(Int32, Int32)] = []
            for i in 0..<pts.count - 1 {
                let p = pts[i].location, q = pts[i + 1].location
                linePts.append((emf((p.x + q.x) / 2), emf((p.y + q.y) / 2)))
            }
            linePts.append((emf(pts.last!.location.x), emf(pts.last!.location.y)))
            appendPolyLineTo(linePts)
        }

        appendEndPath()
        appendStrokePath()
    }
}
