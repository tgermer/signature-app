//
//  SignaturesApp.swift
//  Signatures
//
//  Created by Tristan Germer on 03.11.24.
//

import SwiftUI
import SwiftData
import TipKit

@main
struct SignaturesApp: App {
    let container: ModelContainer
    
    init() {
        do {
            let schema = Schema([SignatureModel.self])
            let modelConfiguration = ModelConfiguration(schema: schema)
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    try? Tips.configure([
                        .displayFrequency(.immediate),
                        .datastoreLocation(.applicationDefault),
                    ])
                }
        }
        .modelContainer(container)
    }
}
