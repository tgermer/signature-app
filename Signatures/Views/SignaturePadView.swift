import SwiftUI
import PencilKit

struct SignaturePadView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    var guidelineHeight: CGFloat
    var strokeColor: Color
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = canvasView
        canvas.frame = CGRect(x: 0, y: 0, width: canvas.bounds.width, height: canvas.bounds.height)
        
        if canvas.isUserInteractionEnabled {
            canvas.tool = PKInkingTool(.pen, color: UIColor(strokeColor))
        }
        if canvas.backgroundColor == nil {
            drawGuideline(at: guidelineHeight)
        }
        return canvas
    }
    
    /* func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.backgroundColor == nil {
            drawGuideline(at: guidelineHeight)
        }
    } */

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
    if uiView.isUserInteractionEnabled {
        uiView.tool = PKInkingTool(.pen, color: UIColor(strokeColor))
    }
    drawGuideline(at: guidelineHeight)
}
    
    private func drawGuideline(at height: CGFloat) {
        let renderer = UIGraphicsImageRenderer(size: canvasView.bounds.size)
        let guidelineImage = renderer.image { context in
            let path = UIBezierPath()
            let y = canvasView.bounds.height - height
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: canvasView.bounds.width, y: y))
            
            UIColor.gray.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.5
            path.stroke()
        }
        
        canvasView.backgroundColor = UIColor(patternImage: guidelineImage)
    }
} 