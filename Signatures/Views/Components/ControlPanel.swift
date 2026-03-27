import SwiftUI
import SwiftData

struct ControlPanel: View {
    @ObservedObject var viewModel: SignatureViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            TextField("Titel eintragen.      Bspw. Nachname, Vorname ####", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 800)

            Button {
                Task {
                    isSaving = true
                    await viewModel.exportSignature()
                    isSaving = false
                    dismiss()
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Speichern")
                }
            }
            .disabled(viewModel.title.isEmpty || isSaving)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

#Preview {
    ControlPanel(viewModel: SignatureViewModel(modelContext: try! ModelContainer(for: SignatureModel.self, configurations: ModelConfiguration()).mainContext))
        .padding()
}
