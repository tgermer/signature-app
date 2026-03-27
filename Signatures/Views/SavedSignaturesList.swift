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
                    VStack(alignment: .leading) {
                        Text(signature.title)
                        Text(signature.timestamp.formatted())
                            .font(.caption)
                            .foregroundColor(.secondary)
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
            SignatureDetailView(
                signature: signature,
                modelContext: modelContext
            )
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
            let signature = signatures[index]
            viewModel.deleteSignature(signature)
        }
    }
} 
