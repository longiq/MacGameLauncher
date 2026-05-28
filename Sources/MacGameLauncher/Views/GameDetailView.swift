import AppKit
import SwiftUI

struct GameDetailView: View {
    @Environment(GameStore.self) private var store
    @Environment(ProcessMonitor.self) private var monitor
    @Environment(ArtworkService.self) private var artwork

    let game: Game
    let bottle: Bottle

    @State private var heroImage: NSImage?
    @State private var isLaunching = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero image banner
                heroImageView

                VStack(alignment: .leading, spacing: 20) {
                    // Title row
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name)
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            HStack(spacing: 8) {
                                sourceBadge
                                Text("•").foregroundStyle(.tertiary)
                                Text(bottle.name).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }

                        Spacer()

                        playButton
                    }

                    Divider()

                    // Stats
                    HStack(spacing: 24) {
                        statCard(
                            title: "Last Played",
                            value: game.lastPlayed.map {
                                $0.formatted(.relative(presentation: .named))
                            } ?? "Never"
                        )
                        statCard(
                            title: "Play Time",
                            value: formatPlayTime(game.totalPlayTime)
                        )
                        if let appID = game.steamAppID {
                            statCard(title: "Steam App ID", value: "\(appID)")
                        }
                    }

                    Divider()

                    // Executable path
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Executable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(game.executablePath)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(20)
            }
        }
        .task(id: game.steamAppID) {
            guard let appID = game.steamAppID else { return }
            heroImage = await artwork.artwork(for: appID, style: .hero)
        }
    }

    @ViewBuilder
    private var heroImageView: some View {
        if let img = heroImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(height: 200)
                .clipped()
        } else {
            Rectangle()
                .fill(LinearGradient(
                    colors: [.indigo.opacity(0.5), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(height: 120)
                .overlay {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.3))
                }
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if monitor.isRunning(game) {
            Button(role: .destructive) {
                monitor.terminate(game)
            } label: {
                Label("Force Quit", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } else {
            Button {
                launchGame()
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLaunching)
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        switch game.source {
        case .steam:
            Text("Steam")
                .font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.blue.opacity(0.15))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        case .epic:
            Text("Epic")
                .font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.purple.opacity(0.15))
                .foregroundStyle(.purple)
                .clipShape(Capsule())
        case .manual:
            Text("Manual")
                .font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.gray.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }

    private func launchGame() {
        guard let wine = store.wineEnv else { return }
        isLaunching = true
        let exeURL = game.resolvedExecutablePath(in: bottle)
        let workDir = game.resolvedWorkingDirectory(in: bottle)
        do {
            let process = try WineService.launch(
                executable: exeURL,
                args: game.executableArgs,
                workingDirectory: workDir,
                bottle: bottle,
                wine: wine
            )
            Task { @MainActor in
                monitor.register(process: process, for: game)
                var updated = game
                updated.lastPlayed = Date()
                store.updateGame(updated)
            }
        } catch {
            print("[GameDetail] launch error: \(error.localizedDescription)")
        }
        isLaunching = false
    }

    private func formatPlayTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "< 1 min" }
        let hours = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}
