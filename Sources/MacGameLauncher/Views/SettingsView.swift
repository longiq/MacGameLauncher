import SwiftUI

struct SettingsView: View {
    @Environment(GameStore.self) private var store
    @AppStorage("winePathOverride") private var winePathOverride: String = ""
    @State private var showClearCacheConfirm = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }

            advancedTab
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 520, height: 300)
    }

    private var generalTab: some View {
        Form {
            Section("Wine") {
                if let env = store.wineEnv {
                    LabeledContent("Wine Source", value: env.source.rawValue)
                    LabeledContent("Binary Path") {
                        Text(env.wine64Path.path)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Wine not found. Install Whisky or Homebrew wine.")
                            .foregroundStyle(.secondary)
                    }
                }

                TextField("Custom wine64 Path (optional)", text: $winePathOverride)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Button("Re-detect Wine") {
                    store.wineEnv = WineEnvironment.detect(customPath: winePathOverride)
                }
                .buttonStyle(.bordered)
            }

            Section("Rosetta 2") {
                HStack {
                    if WineEnvironment.isRosettaInstalled() {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Rosetta 2 is installed")
                    } else {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        Text("Rosetta 2 not found")
                        Spacer()
                        Button("Install") {
                            let process = Process()
                            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
                            process.arguments = ["--install-rosetta", "--agree-to-license"]
                            try? process.run()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            Section("Artwork Cache") {
                LabeledContent("Location") {
                    Text("~/Library/Caches/MacGameLauncher/Artwork/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Clear Artwork Cache…", role: .destructive) {
                    showClearCacheConfirm = true
                }
                .confirmationDialog(
                    "Clear artwork cache?",
                    isPresented: $showClearCacheConfirm
                ) {
                    Button("Clear Cache", role: .destructive) {
                        let cacheDir = FileManager.default
                            .urls(for: .cachesDirectory, in: .userDomainMask)
                            .first!
                            .appending(path: "MacGameLauncher/Artwork")
                        try? FileManager.default.removeItem(at: cacheDir)
                    }
                } message: {
                    Text("This removes all cached game artwork. It will be re-downloaded on demand.")
                }
            }

            Section("Data") {
                LabeledContent("Store Location") {
                    Text("~/Library/Application Support/MacGameLauncher/store.json")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("Bottles Location") {
                    Text("~/Library/Application Support/MacGameLauncher/Bottles/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}
