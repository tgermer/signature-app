import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: SignatureViewModel
    
    let defaultStrokeColorHM = Color(red: 49/255, green: 39/255, blue: 129/255)
    let defaultGuidelineHeightHM: CGFloat = 60
    
    private var hasChanges: Bool {
        return viewModel.strokeColor != defaultStrokeColorHM || 
               viewModel.guidelineHeight != defaultGuidelineHeightHM
    }
    
    var body: some View {
        Form {
            Section("Unterschrift und Canvas") {
                ColorPicker("Stiftfarbe", selection: $viewModel.strokeColor)
                    .onChange(of: viewModel.strokeColor) { oldValue, newValue in
                        viewModel.updateStrokeColor()
                    }
                
                VStack(alignment: .leading) {
                    Text("Hilfslinienhöhe: \(Int(viewModel.guidelineHeight)) mm")
                    Slider(value: $viewModel.guidelineHeight, in: 0...240)
                }
            }
            
            Section("Standardwerte wiederherstellen") {
                Button(action: {
                    viewModel.strokeColor = defaultStrokeColorHM
                    viewModel.guidelineHeight = defaultGuidelineHeightHM
                    viewModel.updateStrokeColor()
                }) {
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
                Toggle("PNG (72 DPI)", isOn: $viewModel.exportSettings.includePNG)
                Toggle("PNG 2x (144 DPI)", isOn: $viewModel.exportSettings.includePNG2x)
                Toggle("SVG", isOn: $viewModel.exportSettings.includeSVG)
                Toggle("PDF", isOn: $viewModel.exportSettings.includePDF)
                Toggle("EMF (Windows)", isOn: $viewModel.exportSettings.includeEMF)
            }
        }
        .navigationTitle("Einstellungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Fertig") {
                    dismiss()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView(viewModel: SignatureViewModel(modelContext: try! ModelContainer(for: SignatureModel.self, configurations: ModelConfiguration()).mainContext))
    }
} 

