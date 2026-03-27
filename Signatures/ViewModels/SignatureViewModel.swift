import SwiftUI
import PencilKit
import SwiftData

struct ExportSettings {
    var includePNG    = true
    var includePNG2x  = true
    var includePNG3x  = false
    var includeSVG    = true
    var includePDF    = true
    var includeEMF    = false

    static func load() -> ExportSettings {
        let d = UserDefaults.standard
        return ExportSettings(
            includePNG:   d.object(forKey: "export.png")   as? Bool ?? true,
            includePNG2x: d.object(forKey: "export.png2x") as? Bool ?? true,
            includePNG3x: d.object(forKey: "export.png3x") as? Bool ?? false,
            includeSVG:   d.object(forKey: "export.svg")   as? Bool ?? true,
            includePDF:   d.object(forKey: "export.pdf")   as? Bool ?? true,
            includeEMF:   d.object(forKey: "export.emf")   as? Bool ?? false
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(includePNG,   forKey: "export.png")
        d.set(includePNG2x, forKey: "export.png2x")
        d.set(includePNG3x, forKey: "export.png3x")
        d.set(includeSVG,   forKey: "export.svg")
        d.set(includePDF,   forKey: "export.pdf")
        d.set(includeEMF,   forKey: "export.emf")
    }
}

@MainActor
class SignatureViewModel: ObservableObject {
    let id = UUID()
    private var loadedSignatureId: UUID?

    @Published var canvasView = PKCanvasView()
    @Published var title = ""
    @Published var strokeColor: Color = Color(red: 49/255, green: 39/255, blue: 129/255)
    @Published var strokeWidth: CGFloat = UserDefaults.standard.object(forKey: "strokeWidth") as? CGFloat ?? 3.0 {
        didSet {
            UserDefaults.standard.set(strokeWidth, forKey: "strokeWidth")
            updateStrokeColor()
        }
    }
    @Published var guidelineHeight: CGFloat = 60
    @Published var exportSettings = ExportSettings.load() {
        didSet { exportSettings.save() }
    }

    static let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var modelContext: ModelContext

    @Published private(set) var currentDrawing: PKDrawing?

    // Feste Maße (60mm × 30mm) – doppelte Größe für bessere Darstellung
    let canvasWidth: CGFloat  = 226.772 * 2
    let canvasHeight: CGFloat = 113.386 * 2
    let exportWidth: CGFloat  = 226.772
    let exportHeight: CGFloat = 113.386

    init(modelContext: ModelContext, existingSignature: SignatureModel? = nil) {
        self.modelContext = modelContext
        if let signature = existingSignature {
            self.title = signature.title
            loadedSignatureId = signature.id
            loadDrawing(from: signature)
        }
        setupCanvas()
    }

    func setupCanvas() {
        canvasView = PKCanvasView()
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor), width: strokeWidth)
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.bounds = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
    }

    func clearSignature() {
        canvasView.drawing = PKDrawing()
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor), width: strokeWidth)
    }

    func updateStrokeColor() {
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor), width: strokeWidth)
    }

    // MARK: - Export (neue Unterschrift)

    func exportSignature() async {
        do { try await saveSignature() }
        catch { print("Fehler beim Exportieren: \(error)") }
    }

    func saveSignature() async throws {
        let filename = generateFilename()
        let bounds = canvasView.bounds
        let drawing = canvasView.drawing
        let penColor = UIColor(strokeColor)
        let penWidth = (canvasView.tool as? PKInkingTool)?.width ?? PKInkingTool(.pen).width

        try await exportPNGFromDrawing(drawing, bounds: bounds, scale: 1.0, filename: "\(filename).png")
        try await saveDrawing(filename: filename)

        var png2xFilename: String? = nil
        var png3xFilename: String? = nil
        var svgFilename:   String? = nil
        var pdfFilename:   String? = nil
        var emfFilename:   String? = nil

        if exportSettings.includePNG2x {
            try await exportPNGFromDrawing(drawing, bounds: bounds, scale: 2.0, filename: "\(filename)@2x.png")
            png2xFilename = "\(filename)@2x.png"
        }
        if exportSettings.includePNG3x {
            try await exportPNGFromDrawing(drawing, bounds: bounds, scale: 3.0, filename: "\(filename)@3x.png")
            png3xFilename = "\(filename)@3x.png"
        }
        if exportSettings.includeSVG {
            let svg = makeSVGString(drawing: drawing, strokeColor: penColor, strokeWidth: penWidth)
            try await saveFile(data: Data(svg.utf8), filename: "\(filename).svg")
            svgFilename = "\(filename).svg"
        }
        if exportSettings.includePDF {
            if let data = makePDFData(drawing: drawing, strokeColor: penColor, strokeWidth: penWidth) {
                try await saveFile(data: data, filename: "\(filename).pdf")
                pdfFilename = "\(filename).pdf"
            }
        }
        if exportSettings.includeEMF {
            let data = EMFExporter.generate(drawing: drawing, strokeColor: penColor, strokeWidth: penWidth)
            try await saveFile(data: data, filename: "\(filename).emf")
            emfFilename = "\(filename).emf"
        }

        let model = SignatureModel(
            title: title,
            timestamp: Date(),
            drawingPath: "\(filename).drawing",
            pngPath: "\(filename).png",
            png2xPath: png2xFilename,
            png3xPath: png3xFilename,
            svgPath: svgFilename,
            pdfPath: pdfFilename,
            emfPath: emfFilename
        )
        modelContext.insert(model)
        try modelContext.save()
        resetState()
    }

    // MARK: - Retroaktiver Export (vorhandene Unterschriften)

    /// Generiert fehlende Export-Dateien für alle vorhandenen Unterschriften
    /// basierend auf den aktuellen Export-Einstellungen.
    func regenerateMissingExports() async {
        let descriptor = FetchDescriptor<SignatureModel>()
        guard let signatures = try? modelContext.fetch(descriptor) else { return }

        let penColor = UIColor(strokeColor)
        let penWidth = (canvasView.tool as? PKInkingTool)?.width ?? PKInkingTool(.pen).width
        let bounds   = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        var changed  = false

        for sig in signatures {
            guard let drawing = try? PKDrawing(data: Data(contentsOf: sig.drawingURL)) else { continue }
            // Basis-Dateiname aus pngPath ableiten (z.B. "Max_20241103.png" → "Max_20241103")
            let base = URL(fileURLWithPath: sig.pngPath).deletingPathExtension().lastPathComponent

            // PNG 2x
            if exportSettings.includePNG2x && sig.png2xPath == nil {
                let name = "\(base)@2x.png"
                if let data = drawing.image(from: bounds, scale: 2.0).pngData(),
                   (try? await saveFile(data: data, filename: name)) != nil {
                    sig.png2xPath = name; changed = true
                }
            }
            // PNG 3x
            if exportSettings.includePNG3x && sig.png3xPath == nil {
                let name = "\(base)@3x.png"
                if let data = drawing.image(from: bounds, scale: 3.0).pngData(),
                   (try? await saveFile(data: data, filename: name)) != nil {
                    sig.png3xPath = name; changed = true
                }
            }
            // SVG
            if exportSettings.includeSVG && sig.svgPath == nil {
                let name = "\(base).svg"
                let svg = makeSVGString(drawing: drawing, strokeColor: penColor, strokeWidth: penWidth)
                if (try? await saveFile(data: Data(svg.utf8), filename: name)) != nil {
                    sig.svgPath = name; changed = true
                }
            }
            // PDF
            if exportSettings.includePDF && sig.pdfPath == nil {
                let name = "\(base).pdf"
                if let pdfData = makePDFData(drawing: drawing, strokeColor: penColor, strokeWidth: penWidth),
                   (try? await saveFile(data: pdfData, filename: name)) != nil {
                    sig.pdfPath = name; changed = true
                }
            }
            // EMF
            if exportSettings.includeEMF && sig.emfPath == nil {
                let name = "\(base).emf"
                let data = EMFExporter.generate(drawing: drawing, strokeColor: penColor, strokeWidth: penWidth)
                if (try? await saveFile(data: data, filename: name)) != nil {
                    sig.emfPath = name; changed = true
                }
            }
        }

        if changed { try? modelContext.save() }
    }

    // MARK: - ZIP Export

    /// Packt alle vorhandenen Export-Dateien einer Unterschrift in ein ZIP.
    /// Gibt die URL der temporären ZIP-Datei zurück.
    func createZIP(for signature: SignatureModel) async throws -> URL {
        var files: [(name: String, data: Data)] = []

        func add(_ url: URL?) throws {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
            files.append((name: url.lastPathComponent, data: try Data(contentsOf: url)))
        }

        try add(signature.pngURL)
        try add(signature.png2xURL)
        try add(signature.png3xURL)
        try add(signature.svgURL)
        try add(signature.pdfURL)
        try add(signature.emfURL)

        guard !files.isEmpty else { throw ExportError.saveFailed }

        let safeName = signature.title.isEmpty ? "Signature" : signature.title
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).zip")
        try ZIPExporter.create(files: files).write(to: zipURL)
        return zipURL
    }

    // MARK: - Export-Hilfsfunktionen (zeichnungsbasiert, ohne Canvas-Referenz)

    private func exportPNGFromDrawing(_ drawing: PKDrawing, bounds: CGRect, scale: CGFloat, filename: String) async throws {
        let image = drawing.image(from: bounds, scale: scale)
        guard let data = image.pngData() else { throw ExportError.renderingFailed }
        try await saveFile(data: data, filename: filename)
    }

    private func makeSVGString(drawing: PKDrawing, strokeColor: UIColor, strokeWidth: CGFloat) -> String {
        let cs: CGFloat = 2.0  // 2× canvas → 1× SVG viewBox
        let colorHex = strokeColor.hexString
        let f: (CGFloat) -> String = { String(format: "%.3f", $0) }

        var svg = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             width="60mm"
             height="30mm"
             viewBox="0 0 226.772 113.386"
             version="1.1">
        """

        for stroke in drawing.strokes {
            let pts = Array(stroke.path)
            guard !pts.isEmpty else { continue }

            let n = pts.count - 1

            if pts.count == 1 {
                let p = pts[0]
                let r = max(p.size.width, 0.5) / 2.0 / cs
                svg += "<circle cx=\"\(f(p.location.x / cs))\" cy=\"\(f(p.location.y / cs))\""
                     + " r=\"\(f(r))\" fill=\"\(colorHex)\"/>\n"
                continue
            }

            let (L2, R2) = svgStrokeOutline(pts)
            let L = L2.map { CGPoint(x: $0.x / cs, y: $0.y / cs) }
            let R = R2.map { CGPoint(x: $0.x / cs, y: $0.y / cs) }

            // Round start cap
            let rStart = max(pts[0].size.width, 0.5) / 2.0 / cs
            svg += "<circle cx=\"\(f(pts[0].location.x / cs))\" cy=\"\(f(pts[0].location.y / cs))\""
                 + " r=\"\(f(rStart))\" fill=\"\(colorHex)\"/>\n"
            // Round end cap
            let rEnd = max(pts[n].size.width, 0.5) / 2.0 / cs
            svg += "<circle cx=\"\(f(pts[n].location.x / cs))\" cy=\"\(f(pts[n].location.y / cs))\""
                 + " r=\"\(f(rEnd))\" fill=\"\(colorHex)\"/>\n"

            // Filled outline polygon — midpoint spline for smooth edges
            var d = "M\(f(L[0].x)),\(f(L[0].y))"
            for i in 0..<n {
                let a = L[i], b = L[i + 1]
                d += " Q\(f(a.x)),\(f(a.y)) \(f((a.x + b.x) / 2)),\(f((a.y + b.y) / 2))"
            }
            d += " L\(f(L[n].x)),\(f(L[n].y))"
            d += " L\(f(R[n].x)),\(f(R[n].y))"
            for i in stride(from: n, through: 1, by: -1) {
                let a = R[i], b = R[i - 1]
                d += " Q\(f(a.x)),\(f(a.y)) \(f((a.x + b.x) / 2)),\(f((a.y + b.y) / 2))"
            }
            d += " L\(f(R[0].x)),\(f(R[0].y))"
            d += " Z"
            svg += "<path d=\"\(d)\" fill=\"\(colorHex)\" stroke=\"none\"/>\n"
        }

        svg += "</svg>"
        return svg
    }

    private func makePDFData(drawing: PKDrawing, strokeColor: UIColor, strokeWidth: CGFloat) -> Data? {
        let pdfData = NSMutableData()

        UIGraphicsBeginPDFContextToData(
            pdfData, CGRect(x: 0, y: 0, width: exportWidth, height: exportHeight), nil)
        UIGraphicsBeginPDFPage()

        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndPDFContext()
            return pdfData as Data
        }

        ctx.scaleBy(x: 0.5, y: 0.5)   // 2× canvas → 1× PDF pts
        strokeColor.setFill()

        for stroke in drawing.strokes {
            let pts = Array(stroke.path)
            guard !pts.isEmpty else { continue }

            let n = pts.count - 1
            let rStart = max(pts[0].size.width, 0.5) / 2.0
            let rEnd   = max(pts[n].size.width, 0.5) / 2.0

            if pts.count == 1 {
                let loc = pts[0].location
                UIBezierPath(ovalIn: CGRect(x: loc.x - rStart, y: loc.y - rStart,
                                            width: rStart * 2, height: rStart * 2)).fill()
                continue
            }

            let (L, R) = svgStrokeOutline(pts)

            // Filled outline polygon — midpoint spline for smooth edges
            let path = UIBezierPath()
            path.move(to: L[0])
            for i in 0..<n {
                let mid = CGPoint(x: (L[i].x + L[i+1].x) / 2, y: (L[i].y + L[i+1].y) / 2)
                path.addQuadCurve(to: mid, controlPoint: L[i])
            }
            path.addLine(to: L[n])
            path.addLine(to: R[n])
            for i in stride(from: n, through: 1, by: -1) {
                let mid = CGPoint(x: (R[i].x + R[i-1].x) / 2, y: (R[i].y + R[i-1].y) / 2)
                path.addQuadCurve(to: mid, controlPoint: R[i])
            }
            path.addLine(to: R[0])
            path.close()
            path.fill()

            // Round caps as filled circles
            let s = pts[0].location
            UIBezierPath(ovalIn: CGRect(x: s.x - rStart, y: s.y - rStart,
                                        width: rStart * 2, height: rStart * 2)).fill()
            let e = pts[n].location
            UIBezierPath(ovalIn: CGRect(x: e.x - rEnd, y: e.y - rEnd,
                                        width: rEnd * 2, height: rEnd * 2)).fill()
        }

        UIGraphicsEndPDFContext()
        return pdfData as Data
    }

    // MARK: - Variable-width stroke outline

    /// Returns left and right outline edge points for a stroke (in 2× canvas coords).
    private func svgStrokeOutline(_ pts: [PKStrokePoint]) -> (left: [CGPoint], right: [CGPoint]) {
        var L: [CGPoint] = [], R: [CGPoint] = []
        for i in 0..<pts.count {
            let loc   = pts[i].location
            let halfW = max(pts[i].size.width, 0.5) / 2.0
            let t     = strokeTangent(at: i, pts: pts)
            let n     = CGPoint(x: -t.y, y: t.x)  // perpendicular (90° CCW)
            L.append(CGPoint(x: loc.x + n.x * halfW, y: loc.y + n.y * halfW))
            R.append(CGPoint(x: loc.x - n.x * halfW, y: loc.y - n.y * halfW))
        }
        return (L, R)
    }

    private func strokeTangent(at i: Int, pts: [PKStrokePoint]) -> CGPoint {
        let count = pts.count
        let a: CGPoint, b: CGPoint
        if count == 1    { return CGPoint(x: 1, y: 0) }
        if i == 0        { (a, b) = (pts[0].location, pts[1].location) }
        else if i == count - 1 { (a, b) = (pts[count - 2].location, pts[count - 1].location) }
        else             { (a, b) = (pts[i - 1].location, pts[i + 1].location) }
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1e-12 else { return CGPoint(x: 1, y: 0) }
        return CGPoint(x: dx / len, y: dy / len)
    }

    private func saveFile(data: Data, filename: String) async throws {
        try data.write(to: Self.documentsDirectory.appendingPathComponent(filename))
    }

    private func saveDrawing(filename: String) async throws {
        let data = try canvasView.drawing.dataRepresentation()
        try data.write(to: Self.documentsDirectory.appendingPathComponent("\(filename).drawing"))
    }

    // MARK: - CRUD

    func deleteSignature(_ signature: SignatureModel) {
        for url in [signature.drawingURL, signature.pngURL] { try? FileManager.default.removeItem(at: url) }
        for url in [signature.png2xURL, signature.png3xURL, signature.svgURL, signature.pdfURL, signature.emfURL] {
            if let url { try? FileManager.default.removeItem(at: url) }
        }
        modelContext.delete(signature)
        try? modelContext.save()
    }

    func renameSignature(_ signature: SignatureModel, newTitle: String) {
        signature.title = newTitle
        try? modelContext.save()
    }

    func loadDrawing(from signature: SignatureModel) {
        do {
            currentDrawing = try PKDrawing(data: Data(contentsOf: signature.drawingURL))
        } catch {
            print("Failed to load drawing: \(error)")
            currentDrawing = nil
        }
    }

    func getDrawingFor(signature: SignatureModel) -> PKDrawing {
        if loadedSignatureId != signature.id { loadDrawing(from: signature) }
        return currentDrawing ?? PKDrawing()
    }

    func resetState() {
        title = ""
        clearSignature()
        setupCanvas()
    }

    // MARK: - Helpers

    private func generateFilename() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd_HHmmss"
        return "\(title.isEmpty ? "Signature" : title)_\(fmt.string(from: Date()))"
    }
}

enum ExportError: Error {
    case renderingFailed
    case conversionFailed
    case saveFailed
}

#Preview {
    NavigationStack {
        SignatureDetailView(
            signature: SignatureModel(
                title: "Test Signature",
                timestamp: Date(),
                drawingPath: "test.drawing",
                pngPath: "test.png",
                png2xPath: "test@2x.png",
                svgPath: "test.svg"
            ),
            modelContext: try! ModelContainer(for: SignatureModel.self).mainContext
        )
    }
}
