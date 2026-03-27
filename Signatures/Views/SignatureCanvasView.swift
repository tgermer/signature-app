import SwiftUI
import PencilKit

struct SignatureCanvasView: View {
    let canvasView: PKCanvasView
    let guidelineHeight: CGFloat
    
    var body: some View {
        ZStack {
            PKCanvasRepresentable(canvasView: canvasView)
            GuidelineView(height: guidelineHeight)
        }
    }
}

struct PKCanvasRepresentable: UIViewRepresentable {
    let canvasView: PKCanvasView
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.isUserInteractionEnabled = false
        canvasView.backgroundColor = .clear
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // No updates needed as we're just displaying
    }
}

#Preview {
    SignatureCanvasView(
        canvasView: PKCanvasView(),
        guidelineHeight: 30
    )
    .frame(width: 226.772, height: 113.386)
    .border(.gray, width: 0.5)
} 
