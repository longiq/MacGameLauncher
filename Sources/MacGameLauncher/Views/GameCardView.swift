import AppKit
import SwiftUI

struct GameCardView: View {
    @Environment(GameStore.self) private var store
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(ArtworkService.self) private var artwork

    let game: Game
    let isSelected: Bool

    @State private var artworkImage: NSImage?
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Artwork background
            artworkBackground
                .frame(width: 160, height: 240)
                .clipped()

            // Bottom overlay: name + status
            VStack(alignment: .leading, spacing: 3) {
                if monitor.isRunning(game) {
                    Label("Playing", systemImage: "play.fill")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                Text(game.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)

            // Play overlay on hover
            if isHovered && !monitor.isRunning(game) {
                Color.black.opacity(0.4)
                    .frame(width: 160, height: 240)
                Image(systemName: "play.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 160, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
        }
        .shadow(color: .black.opacity(0.3), radius: isSelected ? 8 : 4, y: 2)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .animation(.spring(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu { contextMenuItems }
        .task(id: game.steamAppID) {
            guard let appID = game.steamAppID else { return }
            artworkImage = await artwork.artwork(for: appID, style: .libraryGrid)
        }
    }

    @ViewBuilder
    private var artworkBackground: some View {
        if let img = artworkImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
        } else if game.source == .epic {
            epicArtwork
        } else {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.indigo.opacity(0.6), .purple.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }

    @ViewBuilder
    private var epicArtwork: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [.black, Color(red: 0.1, green: 0.05, blue: 0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("EPIC GAMES")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if monitor.isRunning(game) {
            Button("Force Quit", role: .destructive) {
                monitor.terminate(game)
            }
        } else {
            Button("Play") {
                launchGame()
            }
        }

        Divider()

        if let appID = game.steamAppID {
            Button("Launch via Steam") {
                guard let wine = store.wineEnv,
                      let bottle = store.bottle(for: game) else { return }
                let process = try? SteamService.launchSteamGame(
                    appID: appID,
                    bottle: bottle,
                    wine: wine
                )
                if let process {
                    Task { @MainActor in monitor.register(process: process, for: game) }
                }
            }
        }

        if let appName = game.epicAppName {
            Button("Launch via Epic") {
                guard let wine = store.wineEnv,
                      let bottle = store.bottle(for: game) else { return }
                let process = try? EpicService.launchEpicGame(
                    appName: appName,
                    bottle: bottle,
                    wine: wine
                )
                if let process {
                    Task { @MainActor in monitor.register(process: process, for: game) }
                }
            }
        }

        Divider()

        Button("Remove Game", role: .destructive) {
            store.removeGame(game)
        }
    }

    private func launchGame() {
        guard let wine = store.wineEnv,
              let bottle = store.bottle(for: game) else { return }
        do {
            let process: Process
            if game.source == .epic, let appName = game.epicAppName {
                if LegendaryService.isInstalled && LegendaryService.isAuthenticated {
                    process = try LegendaryService.launchGame(appName: appName, bottle: bottle, wine: wine)
                } else {
                    process = try EpicService.launchEpicGame(appName: appName, bottle: bottle, wine: wine)
                }
            } else {
                let exeURL = game.resolvedExecutablePath(in: bottle)
                let workDir = game.resolvedWorkingDirectory(in: bottle)
                process = try WineService.launch(
                    executable: exeURL,
                    args: game.executableArgs,
                    workingDirectory: workDir,
                    bottle: bottle,
                    wine: wine
                )
            }
            Task { @MainActor in
                monitor.register(process: process, for: game)
                var updated = game
                updated.lastPlayed = Date()
                store.updateGame(updated)
            }
        } catch {
            print("[GameCard] launch failed: \(error.localizedDescription)")
        }
    }
}
