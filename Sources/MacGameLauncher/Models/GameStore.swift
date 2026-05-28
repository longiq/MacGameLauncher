import Foundation
import Observation

@Observable
final class GameStore {
    var bottles: [Bottle] = []
    var games: [Game] = []
    var wineEnv: WineEnvironment?
    var activeInstallerJobs: [InstallerJob] = []

    private let storeURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appending(path: "MacGameLauncher")

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        storeURL = appSupport.appending(path: "store.json")
        load()
    }

    // MARK: - Bottle operations

    func addBottle(_ bottle: Bottle) {
        bottles.append(bottle)
        save()
    }

    func removeBottle(_ bottle: Bottle) {
        bottles.removeAll { $0.id == bottle.id }
        games.removeAll { $0.bottleID == bottle.id }
        save()
    }

    func updateBottle(_ bottle: Bottle) {
        if let idx = bottles.firstIndex(where: { $0.id == bottle.id }) {
            bottles[idx] = bottle
            save()
        }
    }

    // MARK: - Game operations

    func addGame(_ game: Game) {
        games.append(game)
        save()
    }

    func removeGame(_ game: Game) {
        games.removeAll { $0.id == game.id }
        save()
    }

    func updateGame(_ game: Game) {
        if let idx = games.firstIndex(where: { $0.id == game.id }) {
            games[idx] = game
            save()
        }
    }

    func games(for bottle: Bottle) -> [Game] {
        games.filter { $0.bottleID == bottle.id }
    }

    func bottle(for game: Game) -> Bottle? {
        bottles.first { $0.id == game.bottleID }
    }

    // MARK: - Installer jobs

    func addInstallerJob(_ job: InstallerJob) {
        activeInstallerJobs.append(job)
    }

    func removeInstallerJob(_ job: InstallerJob) {
        activeInstallerJobs.removeAll { $0.id == job.id }
    }

    // MARK: - Persistence

    func save() {
        let payload = StorePayload(bottles: bottles, games: games)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: storeURL)
        } catch {
            print("[GameStore] save failed: \(error)")
        }
    }

    func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        do {
            let payload = try JSONDecoder().decode(StorePayload.self, from: data)
            bottles = payload.bottles
            games = payload.games
        } catch {
            print("[GameStore] load failed: \(error)")
        }
    }

    private struct StorePayload: Codable {
        let bottles: [Bottle]
        let games: [Game]
    }
}
