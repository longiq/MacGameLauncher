import SwiftUI
import UniformTypeIdentifiers

struct AddGameSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let bottle: Bottle

    @State private var gameName: String = ""
    @State private var executablePath: String = ""
    @State private var executableArgs: String = ""
    @State private var steamAppIDText: String = ""
    @State private var showFilePicker = false

    var canAdd: Bool {
        !gameName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !executablePath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Game")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Add a Windows game to "\(bottle.name)"")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            Form {
                Section("Game Info") {
                    TextField("Game Name", text: $gameName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        TextField("Executable (relative to C:\\ or absolute)", text: $executablePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .fontDesign(.monospaced)

                        Button("Browse…") { showFilePicker = true }
                            .buttonStyle(.bordered)
                    }

                    TextField("Launch Arguments (optional)", text: $executableArgs)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Optional") {
                    HStack {
                        TextField("Steam App ID", text: $steamAppIDText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        Text("Used for artwork and Steam launch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Game") { addGame() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
            .padding(20)
        }
        .frame(width: 500)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [
                UTType(filenameExtension: "exe") ?? .item,
                UTType(filenameExtension: "bat") ?? .item,
            ],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            // Convert macOS path to a path relative to drive_c if possible
            let driveCPath = bottle.driveCPath.path
            if url.path.hasPrefix(driveCPath) {
                executablePath = String(url.path.dropFirst(driveCPath.count + 1))
            } else {
                executablePath = url.path
            }
            if gameName.isEmpty {
                gameName = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func addGame() {
        let args = executableArgs
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }

        let steamAppID = Int(steamAppIDText.trimmingCharacters(in: .whitespaces))

        let game = Game(
            name: gameName.trimmingCharacters(in: .whitespaces),
            bottleID: bottle.id,
            executablePath: executablePath.trimmingCharacters(in: .whitespaces),
            executableArgs: args,
            source: steamAppID != nil ? .steam : .manual,
            steamAppID: steamAppID
        )
        store.addGame(game)
        dismiss()
    }
}
