import SwiftUI
import UniformTypeIdentifiers

struct BottleDetailView: View {
    @Environment(GameStore.self) private var store
    @Environment(ProcessMonitor.self) private var monitor

    let bottle: Bottle

    @State private var editingBottle: Bottle
    @State private var showRunProgram = false
    @State private var isKillingServer = false
    @State private var errorMessage: String?

    init(bottle: Bottle) {
        self.bottle = bottle
        _editingBottle = State(initialValue: bottle)
    }

    var body: some View {
        Form {
            Section("Configuration") {
                Toggle("Metal HUD", isOn: $editingBottle.metalHUD)
                Toggle("ESync (Enhanced Sync)", isOn: $editingBottle.esync)
                Toggle("MSync (Multi Sync)", isOn: $editingBottle.msync)
                Toggle("DXVK (DX→Vulkan fallback)", isOn: $editingBottle.dxvkEnabled)
                    .help("D3DMetal is used by default on Apple Silicon — enable DXVK only if a game requires it.")
            }

            Section("Tools") {
                Button("Open Bottle in Finder") {
                    BottleService.revealInFinder(editingBottle)
                }
                Button("Run Program…") {
                    showRunProgram = true
                }
                Button("Wine Configuration (winecfg)") {
                    openWinecfg()
                }
                Button("Kill Wine Server", role: .destructive) {
                    killWineServer()
                }
                .disabled(isKillingServer)
            }

            Section("Info") {
                LabeledContent("Path") {
                    Text(editingBottle.path.path)
                        .textSelection(.enabled)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Architecture", value: editingBottle.arch.rawValue.uppercased())
                LabeledContent("Created", value: editingBottle.createdAt.formatted(.dateTime.day().month().year()))
                LabeledContent("Status") {
                    if editingBottle.isInitialized {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not initialized", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
        .onChange(of: editingBottle) { _, new in
            store.updateBottle(new)
        }
        .fileImporter(
            isPresented: $showRunProgram,
            allowedContentTypes: [UTType(filenameExtension: "exe") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            guard let wine = store.wineEnv,
                  let url = try? result.get().first else { return }
            _ = try? WineService.launch(executable: url, bottle: editingBottle, wine: wine)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func openWinecfg() {
        guard let wine = store.wineEnv else {
            errorMessage = "Wine not found. Check Settings."
            return
        }
        do {
            _ = try WineService.openWinecfg(bottle: editingBottle, wine: wine)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func killWineServer() {
        guard let wine = store.wineEnv else { return }
        isKillingServer = true
        Task {
            try? await WineService.killBottle(editingBottle, wine: wine)
            await MainActor.run { isKillingServer = false }
        }
    }
}
