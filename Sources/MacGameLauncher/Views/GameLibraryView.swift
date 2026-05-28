import SwiftUI

struct GameLibraryView: View {
    @Environment(GameStore.self) private var store
    @Environment(ProcessMonitor.self) private var monitor

    let bottle: Bottle
    @Binding var selectedGame: Game?

    @State private var searchText = ""
    @State private var showAddGame = false
    @State private var sortOrder: SortOrder = .name

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)]

    enum SortOrder: String, CaseIterable {
        case name       = "Name"
        case lastPlayed = "Last Played"
        case playTime   = "Play Time"
    }

    var filteredGames: [Game] {
        var games = store.games(for: bottle)

        if !searchText.isEmpty {
            games = games.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }

        switch sortOrder {
        case .name:
            games.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .lastPlayed:
            games.sort {
                ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast)
            }
        case .playTime:
            games.sort { $0.totalPlayTime > $1.totalPlayTime }
        }

        return games
    }

    var body: some View {
        Group {
            if filteredGames.isEmpty && searchText.isEmpty {
                emptyState
            } else if filteredGames.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredGames) { game in
                            GameCardView(
                                game: game,
                                isSelected: selectedGame?.id == game.id
                            )
                            .onTapGesture { selectedGame = game }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(bottle.name)
        .searchable(text: $searchText, prompt: "Search games")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            if sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }

                launchers

                Button {
                    showAddGame = true
                } label: {
                    Label("Add Game", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddGame) {
            AddGameSheet(bottle: bottle)
        }
    }

    @ViewBuilder
    private var launchers: some View {
        Menu {
            Button {
                launchSteamInstall()
            } label: {
                Label(
                    SteamService.isSteamInstalled(in: bottle) ? "Open Steam" : "Install Steam",
                    systemImage: "arrow.down.circle"
                )
            }
            Button {
                launchEpicInstall()
            } label: {
                Label(
                    EpicService.isEpicInstalled(in: bottle) ? "Open Epic Games" : "Install Epic Games",
                    systemImage: "arrow.down.circle"
                )
            }
            Divider()
            if !LegendaryService.isInstalled {
                Button("Install Legendary (Epic CLI)") {
                    installLegendary()
                }
            } else if !LegendaryService.isAuthenticated {
                Button("Login to Epic (Legendary)") {
                    LegendaryService.openAuthInTerminal()
                }
            } else {
                Button("Sync Epic Library (Legendary)") {
                    importAndScanLegendary()
                }
            }
            Divider()
            Button("Scan for Games") {
                scanGames()
            }
        } label: {
            Label("Launchers", systemImage: "tray.and.arrow.down")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("No Games")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Add a game manually or install Steam / Epic Games.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Add Game") { showAddGame = true }
                    .buttonStyle(.borderedProminent)
                Button("Install Steam") { launchSteamInstall() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func launchSteamInstall() {
        guard let wine = store.wineEnv else { return }
        if SteamService.isSteamInstalled(in: bottle) {
            try? SteamService.launchSteam(bottle: bottle, wine: wine)
        } else {
            let job = InstallerJob(name: "Steam", bottle: bottle)
            store.addInstallerJob(job)
            Task {
                do {
                    try await SteamService.installSteam(into: bottle, wine: wine, job: job)
                    scanGames()
                } catch {
                    print("[Steam] install failed: \(error)")
                }
                store.removeInstallerJob(job)
            }
        }
    }

    private func launchEpicInstall() {
        guard let wine = store.wineEnv else { return }
        if EpicService.isEpicInstalled(in: bottle) {
            try? EpicService.launchEpic(bottle: bottle, wine: wine)
        } else {
            let job = InstallerJob(name: "Epic Games Launcher", bottle: bottle)
            store.addInstallerJob(job)
            Task {
                do {
                    try await EpicService.installEpic(into: bottle, wine: wine, job: job)
                    ensureEpicLauncherEntry()
                    scanGames()
                } catch {
                    print("[Epic] install failed: \(error)")
                }
                store.removeInstallerJob(job)
            }
        }
    }

    private func ensureEpicLauncherEntry() {
        guard let wine = store.wineEnv,
              let epicExe = EpicService.epicExePath(in: bottle) else { return }
        let existing = store.games(for: bottle)
        guard !existing.contains(where: { $0.name == "Epic Games Launcher" }) else { return }
        let relPath = epicExe.path
            .replacingOccurrences(of: bottle.driveCPath.path + "/", with: "")
        let launcher = Game(
            name: "Epic Games Launcher",
            bottleID: bottle.id,
            executablePath: relPath,
            source: .epic,
            epicAppName: nil
        )
        store.addGame(launcher)
    }

    private func installLegendary() {
        let job = InstallerJob(name: "Legendary", bottle: bottle)
        store.addInstallerJob(job)
        Task {
            do {
                try await LegendaryService.install(job: job)
            } catch {
                print("[Legendary] install failed: \(error)")
            }
            store.removeInstallerJob(job)
        }
    }

    private func importAndScanLegendary() {
        LegendaryService.importGames(from: bottle)
        scanGames()
    }

    private func scanGames() {
        let steamGames = (try? SteamService.scanLibrary(in: bottle)) ?? []
        let epicGames  = (try? EpicService.scanLibrary(in: bottle)) ?? []
        let existing   = store.games(for: bottle)

        for game in steamGames + epicGames {
            if !existing.contains(where: { $0.steamAppID == game.steamAppID && game.steamAppID != nil }
            ) && !existing.contains(where: { $0.name == game.name }) {
                store.addGame(game)
            }
        }
    }
}
