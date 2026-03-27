import SwiftUI
import PencilKit
import SwiftData

struct ExportSettings {
    var includePNG = true
    var includePNG2x = true
    var includeSVG = true
    var includePDF = true
    var includeEMF = false

    static func load() -> ExportSettings {
        let d = UserDefaults.standard
        return ExportSettings(
            includePNG:   d.object(forKey: "export.png")   as? Bool ?? true,
            includePNG2x: d.object(forKey: "export.png2x") as? Bool ?? true,
            includeSVG:   d.object(forKey: "export.svg")   as? Bool ?? true,
            includePDF:   d.object(forKey: "export.pdf")   as? Bool ?? true,
            includeEMF:   d.object(forKey: "export.emf")   as? Bool ?? false
        )
    }

    func save() {
        let d = UserDefaults.standard
        d.set(includePNG,   forKey: "export.png")
        d.set(includePNG2x, forKey: "export.png2x")
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
    @Published var guidelineHeight: CGFloat = 60
    @Published var exportSettings = ExportSettings.load() {
        didSet { exportSettings.save() }
    }

    static let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var modelContext: ModelContext

    @Published private(set) var currentDrawing: PKDrawing?

    // Feste Maße (60mm x 30mm) – doppelte Größe für bessere Darstellung
    let canvasWidth: CGFloat  = 226.772 * 2  // 60mm bei 192 DPI
    let canvasHeight: CGFloat = 113.386 * 2  // 30mm bei 192 DPI
    let exportWidth: CGFloat  = 226.772       // 60mm bei 96 DPI
    let exportHeight: CGFloat = 113.386       // 30mm bei 96 DPI

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
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor))
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.bounds = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
    }

    func clearSignature() {
        canvasView.drawing = PKDrawing()
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor))
    }

    func updateStrokeColor() {
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor))
    }

    // MARK: - Export

    func exportSignature() async {
        do {
            try await saveSignature()
        } catch {
            print("Fehler beim Exportieren: \(error)")
        }
    }

    func saveSignature() async throws {
        let filename = generateFilename()

        try await exportPNG(filename: filename)
        try await saveDrawing(filename: filename)

        var png2xFilename: String? = nil
        var svgFilename:   String? = nil
        var pdfFilename:   String? = nil

        if exportSettings.includePNG2x {
            try await exportPNG2x(filename: filename)
            png2xFilename = "\(filename)@2x.png"
        }
        if exportSettings.includeSVG {
            try await exportSVG(filename: filename)
            svgFilename = "\(filename).svg"
        }
        if exportSettings.includePDF {
            try await exportPDF(filename: filename)
            pdfFilename = "\(filename).pdf"
        }

        var emfFilename: String? = nil
        if exportSettings.includeEMF {
            try await exportEMF(filename: filename)
            emfFilename = "\(filename).emf"
        }

        let model = SignatureModel(
            title: title,
            timestamp: Date(),
            drawingPath: "\(filename).drawing",
            pngPath: "\(filename).png",
            png2xPath: png2xFilename,
            svgPath: svgFilename,
            pdfPath: pdfFilename,
            emfPath: emfFilename
        )
        modelContext.insert(model)
        try modelContext.save()
        resetState()
    }

    @MainActor
    private func exportPNG(filename: String) async throws {
        let image = canvasView.drawing.image(from: canvasView.bounds, scale: 1.0)
        guard let data = image.pngData() else { throw ExportError.renderingFailed }
        try await saveFile(data: data, filename: "\(filename).png")
    }

    @MainActor
    private func exportPNG2x(filename: String) async throws {
        let image = canvasView.drawing.image(from: canvasView.bounds, scale: 2.0)
        guard let data = image.pngData() else { throw ExportError.renderingFailed }
        try await saveFile(data: data, filename: "\(filename)@2x.png")
    }

    private func exportSVG(filename: String) async throws {
        let strokes = canvasView.drawing.strokes
        let scale: CGFloat = 2.0

        var svg = """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             width="60mm"
             height="30mm"
             viewBox="0 0 226.772 113.386"
             version="1.1">
        """

        if let tool = canvasView.tool as? PKInkingTool {
            let strokeWidth = tool.width / scale
            let colorHex = UIColor(strokeColor).hexString

            for stroke in strokes {
                let pts = Array(stroke.path)
                guard pts.count >= 2 else { continue }

                // Smooth quadratic spline: actual points become control points,
                // midpoints between them become endpoints – ensures C1 continuity.
                var d = "M\(pts[0].location.x / scale),\(pts[0].location.y / scale)"
                for i in 0..<pts.count - 1 {
                    let p = pts[i], q = pts[i + 1]
                    let cpX  = p.location.x / scale
                    let cpY  = p.location.y / scale
                    let endX = (p.location.x + q.location.x) / (2 * scale)
                    let endY = (p.location.y + q.location.y) / (2 * scale)
                    d += " Q\(cpX),\(cpY) \(endX),\(endY)"
                }
                let last = pts[pts.count - 1]
                d += " L\(last.location.x / scale),\(last.location.y / scale)"

                svg += """
                <path d="\(d)"
                fill="none"
                stroke="\(colorHex)"
                stroke-width="\(strokeWidth)"
                stroke-linecap="round"
                stroke-linejoin="round"/>
                """
            }
        }

        svg += "</svg>"
        try await saveFile(data: Data(svg.utf8), filename: "\(filename).svg")
    }

    private func exportEMF(filename: String) async throws {
        guard let tool = canvasView.tool as? PKInkingTool else { return }
        let data = EMFExporter.generate(
            drawing: canvasView.drawing,
            strokeColor: UIColor(strokeColor),
            strokeWidth: tool.width
        )
        try await saveFile(data: data, filename: "\(filename).emf")
    }

    private func exportPDF(filename: String) async throws {
        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: exportWidth, height: exportHeight)
        let scale: CGFloat = 0.5

        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()

        if let ctx = UIGraphicsGetCurrentContext() {
            ctx.scaleBy(x: scale, y: scale)

            for stroke in canvasView.drawing.strokes {
                let pts = Array(stroke.path)
                guard pts.count >= 2 else { continue }

                let path = UIBezierPath()
                path.move(to: pts[0].location)

                // Same smooth spline technique as SVG export
                for i in 0..<pts.count - 1 {
                    let p = pts[i], q = pts[i + 1]
                    path.addQuadCurve(
                        to: CGPoint(x: (p.location.x + q.location.x) / 2,
                                    y: (p.location.y + q.location.y) / 2),
                        controlPoint: p.location
                    )
                }
                path.addLine(to: pts[pts.count - 1].location)

                UIColor(strokeColor).setStroke()
                if let inkTool = canvasView.tool as? PKInkingTool {
                    path.lineWidth = inkTool.width
                }
                path.lineCapStyle  = .round
                path.lineJoinStyle = .round
                path.stroke()
            }
        }

        UIGraphicsEndPDFContext()
        try await saveFile(data: pdfData as Data, filename: "\(filename).pdf")
    }

    private func saveFile(data: Data, filename: String) async throws {
        let url = Self.documentsDirectory.appendingPathComponent(filename)
        try data.write(to: url)
    }

    private func saveDrawing(filename: String) async throws {
        let data = try canvasView.drawing.dataRepresentation()
        let url = Self.documentsDirectory.appendingPathComponent("\(filename).drawing")
        try data.write(to: url)
    }

    // MARK: - CRUD

    func deleteSignature(_ signature: SignatureModel) {
        try? FileManager.default.removeItem(at: signature.drawingURL)
        try? FileManager.default.removeItem(at: signature.pngURL)
        if let url = signature.png2xURL { try? FileManager.default.removeItem(at: url) }
        if let url = signature.svgURL   { try? FileManager.default.removeItem(at: url) }
        if let url = signature.pdfURL   { try? FileManager.default.removeItem(at: url) }
        if let url = signature.emfURL   { try? FileManager.default.removeItem(at: url) }
        modelContext.delete(signature)
        try? modelContext.save()
    }

    func renameSignature(_ signature: SignatureModel, newTitle: String) {
        signature.title = newTitle
        try? modelContext.save()
    }

    func loadDrawing(from signature: SignatureModel) {
        do {
            let data = try Data(contentsOf: signature.drawingURL)
            currentDrawing = try PKDrawing(data: data)
        } catch {
            print("Failed to load drawing: \(error)")
            currentDrawing = nil
        }
    }

    func getDrawingFor(signature: SignatureModel) -> PKDrawing {
        if loadedSignatureId != signature.id {
            loadDrawing(from: signature)
        }
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
        let ts = fmt.string(from: Date())
        return "\(title.isEmpty ? "Signature" : title)_\(ts)"
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
