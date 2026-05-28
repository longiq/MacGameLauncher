import SwiftUI

struct SidebarView: View {
    @Environment(GameStore.self) private var store
    @Binding var selectedBottle: Bottle?
    @Binding var selectedGame: Game?
    @State private var showCreateBottle = false
    @State private var bottleToDelete: Bottle?

    var body: some View {
        List(selection: $selectedBottle) {
            Section("Bottles") {
                ForEach(store.bottles) { bottle in
                    SidebarBottleRow(bottle: bottle, selectedBottle: $selectedBottle)
                        .tag(bottle)
                        .contextMenu {
                            Button("Reveal in Finder") {
                                BottleService.revealInFinder(bottle)
                            }
                            Button("Delete Bottle…", role: .destructive) {
                                bottleToDelete = bottle
                            }
                        }
                }
            }
        }
        .navigationTitle("MacGameLauncher")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateBottle = true
                } label: {
                    Label("New Bottle", systemImage: "plus")
                }
                .help("Create a new Wine bottle")
            }
        }
        .sheet(isPresented: $showCreateBottle) {
            CreateBottleSheet(onCreated: { bottle in
                selectedBottle = bottle
            })
        }
        .confirmationDialog(
            "Delete "\(bottleToDelete?.name ?? "")"?",
            isPresented: Binding(
                get: { bottleToDelete != nil },
                set: { if !$0 { bottleToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let bottle = bottleToDelete, let wine = store.wineEnv {
                    if selectedBottle?.id == bottle.id { selectedBottle = nil }
                    Task {
                        try? await BottleService.deleteBottle(bottle, wine: wine, store: store)
                    }
                }
                bottleToDelete = nil
            }
            Button("Cancel", role: .cancel) { bottleToDelete = nil }
        } message: {
            Text("This will permanently delete the bottle and all its data.")
        }
        .onChange(of: selectedBottle) { _, _ in
            selectedGame = nil
        }
    }
}

struct SidebarBottleRow: View {
    let bottle: Bottle
    @Binding var selectedBottle: Bottle?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wineglass")
                .font(.title3)
                .foregroundStyle(selectedBottle?.id == bottle.id ? .white : .accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.name)
                    .fontWeight(.medium)
                Text(bottle.arch.rawValue.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !bottle.isInitialized {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
