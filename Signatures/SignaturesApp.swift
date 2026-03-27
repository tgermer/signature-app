import SwiftUI
import SwiftData
import TipKit

@main
struct SignaturesApp: App {
    let container: ModelContainer?

    init() {
        do {
            let schema = Schema([SignatureModel.self])
            let config = ModelConfiguration(schema: schema)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("Could not initialize ModelContainer: \(error)")
            container = nil
        }
    }

    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView()
                    .task {
                        try? Tips.configure([
                            .displayFrequency(.immediate),
                            .datastoreLocation(.applicationDefault),
                        ])
                    }
                    .modelContainer(container)
            } else {
                Text("Die Datenbank konnte nicht geladen werden.\nBitte starte die App neu.")
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}
