import SwiftUI
import SwiftData

struct SavedSignaturesList: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: SignatureViewModel
    @Query(sort: \SignatureModel.timestamp, order: .reverse) private var signatures: [SignatureModel]
    @State private var selectedSignature: SignatureModel?
    @State private var showNewSignature = false

    init(modelContext: ModelContext) {
        _viewModel = StateObject(wrappedValue: SignatureViewModel(modelContext: modelContext))
    }

    var body: some View {
        List {
            Button {
                showNewSignature = true
            } label: {
                Label("Neue Unterschrift", systemImage: "plus")
            }

            ForEach(signatures) { signature in
                Button {
                    selectedSignature = signature
                } label: {
                    HStack(spacing: 12) {
                        if let uiImage = UIImage(contentsOfFile: signature.pngURL.path) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 40)
                                .background(.white)
                                .border(Color.gray, width: 0.5)
                        }
                        VStack(alignment: .leading) {
                            Text(signature.title)
                            Text(signature.timestamp.formatted())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .onDelete(perform: deleteSignatures)
        }
        .navigationTitle("Unterschriften")
        .navigationDestination(isPresented: $showNewSignature) {
            NewSignatureView(viewModel: SignatureViewModel(modelContext: modelContext))
        }
        .navigationDestination(item: $selectedSignature) { signature in
            SignatureDetailView(signature: signature, modelContext: modelContext)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SettingsView(viewModel: viewModel)
                } label: {
                    Image(systemName: "gear")
                }
            }
        }
    }

    private func deleteSignatures(_ indexSet: IndexSet) {
        for index in indexSet {
            viewModel.deleteSignature(signatures[index])
        }
    }
}
