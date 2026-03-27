import SwiftUI
import SwiftData

struct ControlPanel: View {
    @ObservedObject var viewModel: SignatureViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        // Title and Export
        VStack(alignment: .center, spacing: 20) {
            TextField("Titel eintragen.      Bspw. Nachname, Vorname ####", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 800)
            
            Button("Speichern") {
                viewModel.exportSignature()
                dismiss()
            }
            .disabled(viewModel.title.isEmpty)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

#Preview {
    ControlPanel(viewModel: SignatureViewModel(modelContext: try! ModelContainer(for: SignatureModel.self, configurations: ModelConfiguration()).mainContext))
        .padding()
}
