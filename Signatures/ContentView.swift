//
//  ContentView.swift
//  Signatures
//
//  Created by Tristan Germer on 03.11.24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationSplitView {
            SavedSignaturesList(modelContext: modelContext)
        } detail: {
            VStack(alignment: .center, spacing: 40) {
                Text("Wählen Sie eine Unterschrift aus oder erstellen Sie eine neue")
                    .foregroundColor(.secondary)
                NavigationLink {
                    NewSignatureView(viewModel: SignatureViewModel(modelContext: modelContext))
                } label: {
                    Label("Neue Unterschrift", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: SignatureModel.self)
}
