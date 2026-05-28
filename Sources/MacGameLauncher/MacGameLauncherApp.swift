import SwiftUI

struct MacGameLauncherApp: App {
    @State private var store = GameStore()
    @State private var monitor = ProcessMonitor()
    @State private var artworkService = ArtworkService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(monitor)
                .environment(artworkService)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}
