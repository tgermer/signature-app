import SwiftUI
import PencilKit
import SwiftData
import TipKit

struct SignatureDetailView: View {
    let signature: SignatureModel
    @StateObject private var viewModel: SignatureViewModel
    @State private var hasUnsavedChanges = false
    @State private var editedTitle: String
    @State private var displayCanvas = PKCanvasView()
    @State private var zipURL: URL?
    @State private var isPreparingZIP = false
    @Environment(\.dismiss) private var dismiss
    let addRenameTip = AddRenameTip()

    init(signature: SignatureModel, modelContext: ModelContext) {
        self.signature = signature
        _viewModel = StateObject(wrappedValue: SignatureViewModel(
            modelContext: modelContext,
            existingSignature: signature
        ))
        _editedTitle = State(initialValue: signature.title)
    }

    private func updateCanvas() {
        displayCanvas.bounds = CGRect(x: 0, y: 0, width: viewModel.canvasWidth, height: viewModel.canvasHeight)
        displayCanvas.backgroundColor = .clear
        displayCanvas.isUserInteractionEnabled = false
        displayCanvas.drawingPolicy = .anyInput
        if let drawing = viewModel.currentDrawing {
            displayCanvas.drawing = drawing
        }
    }

    var body: some View {
        VStack(spacing: 30) {
            TextField("Titel", text: $editedTitle)
                .textFieldStyle(.plain)
                .font(.title)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding()
                .onChange(of: signature.title) { _, newValue in editedTitle = newValue }
                .onChange(of: editedTitle)     { _, newValue in
                    hasUnsavedChanges = newValue != signature.title
                }
                .popoverTip(addRenameTip)

            Text(signature.timestamp.formatted())
                .foregroundColor(.secondary)

            SignaturePadView(
                canvasView: .constant(displayCanvas),
                guidelineHeight: viewModel.guidelineHeight,
                strokeColor: viewModel.strokeColor
            )
            .frame(width: viewModel.canvasWidth, height: viewModel.canvasHeight)
            .background(.white)
            .border(Color.gray, width: 0.5)
            .id(signature.id)

            // Share-Buttons – scrollbar, da es bis zu 7 Buttons geben kann
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    if viewModel.exportSettings.includePNG {
                        ShareLink(
                            item: signature.pngURL,
                            preview: SharePreview(signature.title,
                                image: Image(uiImage: UIImage(contentsOfFile: signature.pngURL.path) ?? UIImage()))
                        ) { Label("PNG", systemImage: "square.and.arrow.up") }
                    }

                    if viewModel.exportSettings.includePNG2x, let url = signature.png2xURL {
                        ShareLink(
                            item: url,
                            preview: SharePreview(signature.title,
                                image: Image(uiImage: UIImage(contentsOfFile: url.path) ?? UIImage()))
                        ) { Label("PNG 2×", systemImage: "square.and.arrow.up") }
                    }

                    if viewModel.exportSettings.includePNG3x, let url = signature.png3xURL {
                        ShareLink(
                            item: url,
                            preview: SharePreview(signature.title,
                                image: Image(uiImage: UIImage(contentsOfFile: url.path) ?? UIImage()))
                        ) { Label("PNG 3×", systemImage: "square.and.arrow.up") }
                    }

                    if viewModel.exportSettings.includeSVG, let url = signature.svgURL {
                        ShareLink(item: url) { Label("SVG", systemImage: "square.and.arrow.up") }
                    }

                    if viewModel.exportSettings.includePDF, let url = signature.pdfURL {
                        ShareLink(item: url) { Label("PDF", systemImage: "square.and.arrow.up") }
                    }

                    if viewModel.exportSettings.includeEMF, let url = signature.emfURL {
                        ShareLink(item: url) { Label("EMF", systemImage: "square.and.arrow.up") }
                    }

                    Divider().frame(height: 24)

                    // ZIP: erst erstellen, dann teilen
                    if isPreparingZIP {
                        ProgressView().controlSize(.small)
                    } else if let url = zipURL {
                        ShareLink(item: url) {
                            Label("ZIP", systemImage: "archivebox")
                        }
                    } else {
                        Button {
                            Task {
                                isPreparingZIP = true
                                zipURL = try? await viewModel.createZIP(for: signature)
                                isPreparingZIP = false
                            }
                        } label: {
                            Label("ZIP erstellen", systemImage: "archivebox")
                        }
                    }
                }
                .padding(.horizontal)
            }

            Button("Speichern") {
                viewModel.renameSignature(signature, newTitle: editedTitle)
                hasUnsavedChanges = false
            }
            .disabled(!hasUnsavedChanges)
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle($editedTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    viewModel.deleteSignature(signature)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundColor(.red)
            }
        }
        .onAppear {
            viewModel.loadDrawing(from: signature)
            updateCanvas()
        }
        .onChange(of: signature.id) {
            viewModel.loadDrawing(from: signature)
            updateCanvas()
            zipURL = nil
        }
        .onChange(of: viewModel.currentDrawing) { _, _ in updateCanvas() }
    }
}

#Preview {
    NavigationStack {
        SignatureDetailView(
            signature: SignatureModel(
                title: "Test Signature",
                timestamp: Date(),
                drawingPath: "test.drawing",
                pngPath: "test.png",
                png2xPath: "test@2x.png",
                svgPath: "test.svg"
            ),
            modelContext: try! ModelContainer(for: SignatureModel.self, configurations: ModelConfiguration()).mainContext
        )
        .task {
            try? Tips.configure([
                .displayFrequency(.immediate),
                .datastoreLocation(.applicationDefault),
            ])
        }
    }
}
