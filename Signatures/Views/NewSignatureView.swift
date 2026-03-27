import SwiftUI
import PencilKit

struct NewSignatureView: View {
    @ObservedObject var viewModel: SignatureViewModel
    @Environment(\.dismiss) private var dismiss
    var addNewSignatureTip = AddNewSignatureTip()
    
    var body: some View {
        ZStack {
            StripedBackground(
                stripeColor: Color.gray.opacity(0.05),
                stripeWidth: 50,
                spacing: 30
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                SignaturePadView(
                    canvasView: $viewModel.canvasView,
                    guidelineHeight: viewModel.guidelineHeight,
                    strokeColor: viewModel.strokeColor,
                    strokeWidth: viewModel.strokeWidth
                )
                .frame(width: viewModel.canvasWidth, height: viewModel.canvasHeight)
                .background(.white)
                .border(Color.gray, width: 0.5)
                .popoverTip(addNewSignatureTip)
                
                Button("Unterschrift zurücksetzen") {
                    viewModel.clearSignature()
                }
                .buttonStyle(.bordered)
                .padding(.bottom)
                .controlSize(.small)
                
                ControlPanel(viewModel: viewModel)
            }
            .padding()
        }
        .navigationTitle("Neue Unterschrift")
    }
} 

