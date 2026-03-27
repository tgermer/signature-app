import SwiftUI

struct GuidelineView: View {
    let height: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height - height))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - height))
            }
            .stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 0.5, dash: [5]))
        }
    }
}

#Preview {
    GuidelineView(height: 30)
        .frame(width: 226.772, height: 113.386)
        .border(.gray, width: 0.5)
} 