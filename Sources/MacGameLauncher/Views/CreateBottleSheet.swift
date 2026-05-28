import SwiftUI

struct CreateBottleSheet: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var onCreated: ((Bottle) -> Void)?

    @State private var name: String = ""
    @State private var arch: Bottle.WineArch = .win64
    @State private var isCreating = false
    @State private var progressMessage = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Bottle")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Create a new Wine environment to install games.")
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

            // Form
            Form {
                Section {
                    TextField("Bottle Name", text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker("Architecture", selection: $arch) {
                        Text("64-bit (recommended)").tag(Bottle.WineArch.win64)
                        Text("32-bit (legacy games)").tag(Bottle.WineArch.win32)
                    }
                    .pickerStyle(.segmented)
                }

                if store.wineEnv == nil {
                    Section {
                        Label(
                            "Wine not found. Install Whisky or Homebrew wine first.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 160)

            if isCreating {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(progressMessage.isEmpty ? "Initializing…" : progressMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }

            Divider()

            // Buttons
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isCreating)
                Button("Create Bottle") { createBottle() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || store.wineEnv == nil
                              || isCreating)
            }
            .padding(20)
        }
        .frame(width: 440)
    }

    private func createBottle() {
        guard let wine = store.wineEnv else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        isCreating = true
        errorMessage = nil

        Task {
            do {
                let bottle = try await BottleService.createBottle(
                    name: trimmedName,
                    arch: arch,
                    wine: wine,
                    store: store
                ) { message in
                    progressMessage = message
                }
                dismiss()
                onCreated?(bottle)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
