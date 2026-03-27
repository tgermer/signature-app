import SwiftUI

struct StripedBackground: View {
    let stripeColor: Color
    let stripeWidth: CGFloat
    let spacing: CGFloat
    
    var body: some View {
        Canvas { context, size in
            // Calculate diagonal length to ensure stripes cover the entire view
            let diagonal = sqrt(pow(size.width, 2) + pow(size.height, 2))
            let stripesCount = Int(diagonal / (stripeWidth + spacing))
            
            // Move to center and rotate
            context.translateBy(x: size.width/2, y: size.height/2)
            context.rotate(by: .degrees(45))
            context.translateBy(x: -diagonal/2, y: -diagonal/2)
            
            // Draw stripes
            for i in 0...stripesCount {
                let x = CGFloat(i) * (stripeWidth + spacing)
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x + stripeWidth, y: 0))
                    p.addLine(to: CGPoint(x: x + stripeWidth, y: diagonal))
                    p.addLine(to: CGPoint(x: x, y: diagonal))
                    p.closeSubpath()
                }
                
                context.fill(path, with: .color(stripeColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue.opacity(0.05))
    }
}

#Preview {
    StripedBackground(stripeColor: .gray, stripeWidth: 10, spacing: 10)
}
