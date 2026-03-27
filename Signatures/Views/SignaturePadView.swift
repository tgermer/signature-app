import SwiftUI
import PencilKit

struct SignaturePadView: View {
    @Binding var canvasView: PKCanvasView
    var guidelineHeight: CGFloat
    var strokeColor: Color
    var strokeWidth: CGFloat

    var body: some View {
        ZStack {
            CanvasRepresentable(canvasView: canvasView, strokeColor: strokeColor, strokeWidth: strokeWidth)
            GuidelineView(height: guidelineHeight)
        }
    }
}

private struct CanvasRepresentable: UIViewRepresentable {
    let canvasView: PKCanvasView
    var strokeColor: Color
    var strokeWidth: CGFloat

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        if canvasView.isUserInteractionEnabled {
            canvasView.tool = PKInkingTool(.pen, color: UIColor(strokeColor), width: strokeWidth)
        }
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.isUserInteractionEnabled {
            uiView.tool = PKInkingTool(.pen, color: UIColor(strokeColor), width: strokeWidth)
        }
    }
}

#Preview {
    SignaturePadView(
        canvasView: .constant(PKCanvasView()),
        guidelineHeight: 60,
        strokeColor: Color(red: 49/255, green: 39/255, blue: 129/255),
        strokeWidth: 3.0
    )
    .frame(width: 226.772 * 2, height: 113.386 * 2)
    .background(.white)
    .border(.gray, width: 0.5)
}
