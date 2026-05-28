import AppKit
import Foundation

struct BottleService {

    private static var bottlesDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appending(path: "MacGameLauncher/Bottles")
    }

    // MARK: - Create a new bottle

    static func createBottle(
        name: String,
        arch: Bottle.WineArch = .win64,
        wine: WineEnvironment,
        store: GameStore,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> Bottle {
        let bottleDir = bottlesDirectory.appending(path: sanitize(name))
        try FileManager.default.createDirectory(
            at: bottleDir,
            withIntermediateDirectories: true
        )

        let bottle = Bottle(name: name, path: bottleDir, arch: arch)

        await MainActor.run { progress("Initializing Wine prefix…") }

        try await WineService.initBottle(bottle, wine: wine)

        await MainActor.run {
            store.addBottle(bottle)
            progress("Bottle "\(name)" created.")
        }
        return bottle
    }

    // MARK: - Delete a bottle

    static func deleteBottle(
        _ bottle: Bottle,
        wine: WineEnvironment,
        store: GameStore
    ) async throws {
        // Kill any running wineserver for this bottle
        try? await WineService.killBottle(bottle, wine: wine)

        // Remove directory
        try FileManager.default.removeItem(at: bottle.path)

        await MainActor.run { store.removeBottle(bottle) }
    }

    // MARK: - Repair (re-run wineboot)

    static func repairBottle(
        _ bottle: Bottle,
        wine: WineEnvironment
    ) async throws {
        try await WineService.initBottle(bottle, wine: wine)
    }

    // MARK: - Reveal in Finder

    static func revealInFinder(_ bottle: Bottle) {
        NSWorkspace.shared.open(bottle.path)
    }

    private static func sanitize(_ name: String) -> String {
        name.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
    }
}
