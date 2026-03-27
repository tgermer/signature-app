import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: SignatureViewModel

    let defaultStrokeColorHM   = Color(red: 49/255, green: 39/255, blue: 129/255)
    let defaultGuidelineHeight: CGFloat = 60
    let defaultStrokeWidth:     CGFloat = 3.0

    private var hasChanges: Bool {
        viewModel.strokeColor    != defaultStrokeColorHM   ||
        viewModel.guidelineHeight != defaultGuidelineHeight ||
        viewModel.strokeWidth    != defaultStrokeWidth
    }

    var body: some View {
        Form {
            Section("Unterschrift und Canvas") {
                ColorPicker("Stiftfarbe", selection: $viewModel.strokeColor)
                    .onChange(of: viewModel.strokeColor) { _, _ in
                        viewModel.updateStrokeColor()
                    }

                VStack(alignment: .leading) {
                    Text("Strichstärke: \(viewModel.strokeWidth, specifier: "%.1f") pt")
                    Slider(value: $viewModel.strokeWidth, in: 1...20, step: 0.5)
                }

                VStack(alignment: .leading) {
                    Text("Hilfslinienhöhe: \(Int(viewModel.guidelineHeight)) mm")
                    Slider(value: $viewModel.guidelineHeight, in: 0...240)
                }
            }

            Section("Standardwerte wiederherstellen") {
                Button {
                    viewModel.strokeColor     = defaultStrokeColorHM
                    viewModel.strokeWidth     = defaultStrokeWidth
                    viewModel.guidelineHeight = defaultGuidelineHeight
                    viewModel.updateStrokeColor()
                } label: {
                    HStack {
                        Text("HM-Standards")
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
                .foregroundStyle(.blue)
                .disabled(!hasChanges)
            }

            Section("Export-Einstellungen") {
                Toggle("PNG (1×)", isOn: $viewModel.exportSettings.includePNG)

                Toggle("PNG (2×)", isOn: $viewModel.exportSettings.includePNG2x)
                    .onChange(of: viewModel.exportSettings.includePNG2x) { _, isOn in
                        if isOn { Task { await viewModel.regenerateMissingExports() } }
                    }

                Toggle("PNG (3×)", isOn: $viewModel.exportSettings.includePNG3x)
                    .onChange(of: viewModel.exportSettings.includePNG3x) { _, isOn in
                        if isOn { Task { await viewModel.regenerateMissingExports() } }
                    }

                Toggle("SVG", isOn: $viewModel.exportSettings.includeSVG)
                    .onChange(of: viewModel.exportSettings.includeSVG) { _, isOn in
                        if isOn { Task { await viewModel.regenerateMissingExports() } }
                    }

                Toggle("PDF", isOn: $viewModel.exportSettings.includePDF)
                    .onChange(of: viewModel.exportSettings.includePDF) { _, isOn in
                        if isOn { Task { await viewModel.regenerateMissingExports() } }
                    }

                Toggle("EMF (Windows)", isOn: $viewModel.exportSettings.includeEMF)
                    .onChange(of: viewModel.exportSettings.includeEMF) { _, isOn in
                        if isOn { Task { await viewModel.regenerateMissingExports() } }
                    }
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Fertig") { dismiss() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: SignatureViewModel(modelContext: try! ModelContainer(for: SignatureModel.self, configurations: ModelConfiguration()).mainContext))
    }
}
