import Foundation
import SwiftData

@Model
final class SignatureModel {
    var id: UUID
    var title: String
    var timestamp: Date
    var drawingPath: String
    var pngPath: String
    var png2xPath: String?
    var svgPath: String?
    var pdfPath: String?
    var emfPath: String?

    private static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    var drawingURL: URL { Self.documentsDirectory.appendingPathComponent(drawingPath) }
    var pngURL: URL    { Self.documentsDirectory.appendingPathComponent(pngPath) }
    var png2xURL: URL? { png2xPath.map { Self.documentsDirectory.appendingPathComponent($0) } }
    var svgURL: URL?   { svgPath.map   { Self.documentsDirectory.appendingPathComponent($0) } }
    var pdfURL: URL?   { pdfPath.map   { Self.documentsDirectory.appendingPathComponent($0) } }
    var emfURL: URL?   { emfPath.map   { Self.documentsDirectory.appendingPathComponent($0) } }

    init(
        id: UUID = UUID(),
        title: String,
        timestamp: Date,
        drawingPath: String,
        pngPath: String,
        png2xPath: String? = nil,
        svgPath: String? = nil,
        pdfPath: String? = nil,
        emfPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.drawingPath = drawingPath
        self.pngPath = pngPath
        self.png2xPath = png2xPath
        self.svgPath = svgPath
        self.pdfPath = pdfPath
        self.emfPath = emfPath
    }
}
