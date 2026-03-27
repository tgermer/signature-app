import SwiftUI
import PencilKit
import SwiftData

struct ExportSettings {
    var includePNG = true
    var includePNG2x = true
    var includeSVG = true
    var includePDF = true
}

@MainActor
class SignatureViewModel: ObservableObject {
    let id = UUID() // Eindeutiger Identifier
    private var loadedSignatureId: UUID?
    
    // Canvas Einstellungen
    @Published var canvasView = PKCanvasView()
    @Published var title = ""
    @Published var strokeColor: Color = Color(red: 49/255, green: 39/255, blue: 129/255)
    @Published var guidelineHeight: CGFloat = 60
    @Published var exportSettings = ExportSettings()
    
    static let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private var modelContext: ModelContext
    
    private var currentSignaturePath: String?
    @Published private(set) var currentDrawing: PKDrawing?
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupCanvas()
    }
    
    init(modelContext: ModelContext, existingSignature: SignatureModel? = nil) {
        self.modelContext = modelContext
        print("Creating ViewModel with ID: \(id)")
        if let signature = existingSignature {
            self.title = signature.title
            loadedSignatureId = signature.id
            loadDrawing(from: signature)
        }
        setupCanvas()
    }
    
    // Feste Maße (60mm x 30mm in Punkten) - doppelte Größe für bessere Darstellung
    let canvasWidth: CGFloat = 226.772 * 2  // 60mm bei 192 DPI
    let canvasHeight: CGFloat = 113.386 * 2 // 30mm bei 192 DPI
    
    // Export Maße
    let exportWidth: CGFloat = 226.772  // 60mm bei 96 DPI
    let exportHeight: CGFloat = 113.386 // 30mm bei 96 DPI
    
    // Canvas Setup
    func setupCanvas() {
        canvasView = PKCanvasView()
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor))
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = .clear
        canvasView.bounds = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        drawGuideline()
    }
    
    // Unterschrift zurücksetzen
    func clearSignature() {
        canvasView.drawing = PKDrawing()
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor))
        drawGuideline()
    }
    
    private func drawGuideline() {
        let renderer = UIGraphicsImageRenderer(size: canvasView.bounds.size)
        let guidelineImage = renderer.image { context in
            let path = UIBezierPath()
            let y = canvasView.bounds.height - guidelineHeight
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: canvasView.bounds.width, y: y))
            
            UIColor.gray.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
        
        canvasView.backgroundColor = UIColor(patternImage: guidelineImage)
    }
    
    // Hilfsmethode für Dateinamen
    private func generateFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        return "\(title.isEmpty ? "Signature" : title)_\(timestamp)"
    }
    
    func exportSignature() {
        Task {
            do {
                try await saveSignature()
                resetState()
            } catch {
                print("Fehler beim Exportieren: \(error)")
            }
        }
    }
    
    @MainActor
    private func exportPNG(filename: String) async throws {
        let image = canvasView.drawing.image(from: canvasView.bounds, scale: 1.0)
        guard let data = image.pngData() else { throw NSError(domain: "", code: -1) }
        try await saveFile(data: data, filename: "\(filename).png")
    }
    
    @MainActor
    private func exportPNG2x(filename: String) async throws {
        let image = canvasView.drawing.image(from: canvasView.bounds, scale: 2.0)
        guard let data = image.pngData() else { throw NSError(domain: "", code: -1) }
        try await saveFile(data: data, filename: "\(filename)@2x.png")
    }
    

    private func exportSVG(filename: String) async throws {
    let strokes = canvasView.drawing.strokes
    
    var svgContent = """
    <?xml version="1.0" encoding="UTF-8" standalone="no"?>
    <svg xmlns="http://www.w3.org/2000/svg"
         width="60mm"
         height="30mm"
         viewBox="0 0 226.772 113.386"
         version="1.1">
    """
    
    // Verwende die tatsächlichen PencilKit-Eigenschaften
    if let tool = canvasView.tool as? PKInkingTool {
        let strokeWidth = tool.width / 2 // Halbiere die Breite für Export
        
        for stroke in strokes {
            let path = stroke.path
            if path.count < 2 { continue }
            
            var pathData = "<path d=\"M"
            
            // Erstelle den SVG-Pfad aus den PencilKit-Punkten
            for (index, point) in path.enumerated() {
                let x = point.location.x / 2
                let y = point.location.y / 2
                
                if index == 0 {
                    pathData += "\(x),\(y)"
                } else {
                    // Verwende Bézierkurven für weichere Linien
                    let prevPoint = path[index - 1]
                    let controlX = (prevPoint.location.x + point.location.x) / 4
                    let controlY = (prevPoint.location.y + point.location.y) / 4
                    pathData += " Q\(controlX),\(controlY) \(x),\(y)"
                }
            }
            
            pathData += "\"\n"
            pathData += "fill=\"none\"\n"
            pathData += "stroke=\"\(UIColor(strokeColor).hexString)\"\n"
            pathData += "stroke-width=\"\(strokeWidth)\"\n"
            pathData += "stroke-linecap=\"round\"\n"
            pathData += "stroke-linejoin=\"round\"\n"
            pathData += "/>"
            
            svgContent += pathData + "\n"
        }
    }
    
    svgContent += "</svg>"
    
    try await saveFile(data: Data(svgContent.utf8), filename: "\(filename).svg")
}


    
    private func saveFile(data: Data, filename: String) async throws {
        let fileURL = Self.documentsDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
    }
    
    private func exportPDF(filename: String) async throws {
        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: exportWidth, height: exportHeight)
        
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        UIGraphicsBeginPDFPage()
        
        if let context = UIGraphicsGetCurrentContext() {
            // Scale the context to match export size
            context.scaleBy(x: 0.5, y: 0.5)
            
            // Draw each stroke as a vector path
            for stroke in canvasView.drawing.strokes {
                let path = UIBezierPath()
                
                if let firstPoint = stroke.path.first {
                    path.move(to: firstPoint.location)
                }
                
                for point in stroke.path.dropFirst() {
                    path.addLine(to: point.location)
                }
                
                // Set stroke properties
                UIColor(strokeColor).setStroke()
                if let inkingTool = canvasView.tool as? PKInkingTool {
                    path.lineWidth = inkingTool.width
                }
                
                path.stroke()
            }
        }
        
        UIGraphicsEndPDFContext()
        
        try await saveFile(data: pdfData as Data, filename: "\(filename).pdf")
    }
    
    func resetState() {
        title = ""
        clearSignature()
        setupCanvas()
    }
    
    func saveSignature() async throws {
        let filename = generateFilename()
        let drawingURL = try await saveDrawing(filename: filename)
        let pngPath = Self.documentsDirectory.appendingPathComponent("\(filename).png")
        var png2xPath: URL? = nil
        var paths: [URL?] = [nil, nil, nil]
        
        try await exportPNG(filename: filename)
        
        if exportSettings.includePNG2x {
            try await exportPNG2x(filename: filename)
            png2xPath = Self.documentsDirectory.appendingPathComponent("\(filename)@2x.png")
        }
        
        if exportSettings.includeSVG {
            try await exportSVG(filename: filename)
            paths[0] = Self.documentsDirectory.appendingPathComponent("\(filename).svg")
        }
        
        if exportSettings.includePDF {
            try await exportPDF(filename: filename)
            paths[1] = Self.documentsDirectory.appendingPathComponent("\(filename).pdf")
        }
        
        let signatureModel = SignatureModel(
            title: title,
            timestamp: Date(),
            drawingPath: drawingURL.path,
            pngPath: pngPath.path,
            png2xPath: png2xPath?.path,
            svgPath: paths[0]?.path,
            pdfPath: paths[1]?.path,
            emfPath: nil
        )
        
        modelContext.insert(signatureModel)
        try modelContext.save()
        resetState()
    }
    
    func deleteSignature(_ signature: SignatureModel) {
        // Delete files
        try? FileManager.default.removeItem(atPath: signature.drawingPath)
        try? FileManager.default.removeItem(atPath: signature.pngPath)
        if let png2xPath = signature.png2xPath {
            try? FileManager.default.removeItem(atPath: png2xPath)
        }
        if let svgPath = signature.svgPath {
            try? FileManager.default.removeItem(atPath: svgPath)
        }
        if let pdfPath = signature.pdfPath {
            try? FileManager.default.removeItem(atPath: pdfPath)
        }
        
        modelContext.delete(signature)
        try? modelContext.save()
    }
    
    private func saveDrawing(filename: String) async throws -> URL {
        let drawing = canvasView.drawing
        let data = try drawing.dataRepresentation()
        let drawingURL = Self.documentsDirectory.appendingPathComponent("\(filename).drawing")
        try data.write(to: drawingURL)
        return drawingURL
    }
    
    func renameSignature(_ signature: SignatureModel, newTitle: String) {
        signature.title = newTitle
        try? modelContext.save()
    }
    
    func updateStrokeColor() {
        canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor))
    }
    
    func loadDrawing(from signature: SignatureModel) {
        print("=== Loading drawing in ViewModel \(id) ===")
        print("For signature: \(signature.title) (\(signature.id))")
        
        let url = Self.documentsDirectory.appendingPathComponent(URL(filePath: signature.drawingPath).lastPathComponent)
        do {
            let drawingData = try Data(contentsOf: url)
            currentDrawing = try PKDrawing(data: drawingData)
            print("Successfully loaded drawing with \(currentDrawing?.strokes.count ?? 0) strokes")
        } catch {
            print("Failed to load drawing: \(error)")
            currentDrawing = nil
        }
    }
    
    func getDrawingFor(signature: SignatureModel) -> PKDrawing {
        print("Getting drawing for signature \(signature.title) in ViewModel \(id)")
        if loadedSignatureId != signature.id {
            loadDrawing(from: signature)
        }
        return currentDrawing ?? PKDrawing()
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
                drawingPath: "/tmp/test.drawing",
                pngPath: "/tmp/test.png",
                png2xPath: "/tmp/test@2x.png",
                svgPath: "/tmp/test.svg"
            ),
            modelContext: try! ModelContainer(for: SignatureModel.self).mainContext
        )
    }
} 
