import SwiftUI

struct ContentView: View {
    @Environment(GameStore.self) private var store
    @Environment(ProcessMonitor.self) private var monitor

    @State private var selectedBottle: Bottle?
    @State private var selectedGame: Game?
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showRosettaWarning = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedBottle: $selectedBottle, selectedGame: $selectedGame)
        } content: {
            if let bottle = selectedBottle {
                GameLibraryView(bottle: bottle, selectedGame: $selectedGame)
            } else {
                ContentUnavailableView(
                    "No Bottle Selected",
                    systemImage: "wineglass",
                    description: Text("Create a bottle to get started.")
                )
            }
        } detail: {
            if let game = selectedGame, let bottle = store.bottle(for: game) {
                GameDetailView(game: game, bottle: bottle)
            } else if let bottle = selectedBottle {
                BottleDetailView(bottle: bottle)
            } else {
                ContentUnavailableView(
                    "Select a Game",
                    systemImage: "gamecontroller.fill"
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if store.wineEnv == nil {
                store.wineEnv = WineEnvironment.detect()
            }
            if !WineEnvironment.isRosettaInstalled() {
                showRosettaWarning = true
            }
            // Select first bottle by default
            if selectedBottle == nil {
                selectedBottle = store.bottles.first
            }
        }
        .alert("Rosetta 2 Required", isPresented: $showRosettaWarning) {
            Button("OK") {}
        } message: {
            Text("Wine requires Rosetta 2 to run x86-64 Windows binaries on Apple Silicon.\n\nInstall it by running:\nsoftwareupdate --install-rosetta --agree-to-license")
        }
        .sheet(item: Binding(
            get: { store.activeInstallerJobs.first },
            set: { _ in }
        )) { job in
            InstallerProgressView(job: job)
                .environment(store)
        }
    }
}
