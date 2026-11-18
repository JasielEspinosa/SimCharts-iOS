import SwiftUI

@main
struct SimChartsApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(model.settings.theme == "Light" ? .light : .dark)
        }
    }
}
