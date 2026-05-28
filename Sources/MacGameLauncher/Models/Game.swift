import Foundation

struct Game: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var bottleID: UUID
    var executablePath: String   // relative to drive_c (e.g. "Program Files/Game/game.exe") OR absolute
    var executableArgs: [String]
    var workingDirectory: String?
    var source: GameSource
    var steamAppID: Int?
    var epicAppName: String?
    var lastPlayed: Date?
    var totalPlayTime: TimeInterval

    enum GameSource: String, Codable {
        case manual, steam, epic
    }

    init(
        id: UUID = UUID(),
        name: String,
        bottleID: UUID,
        executablePath: String,
        executableArgs: [String] = [],
        workingDirectory: String? = nil,
        source: GameSource = .manual,
        steamAppID: Int? = nil,
        epicAppName: String? = nil,
        lastPlayed: Date? = nil,
        totalPlayTime: TimeInterval = 0
    ) {
        self.id = id
        self.name = name
        self.bottleID = bottleID
        self.executablePath = executablePath
        self.executableArgs = executableArgs
        self.workingDirectory = workingDirectory
        self.source = source
        self.steamAppID = steamAppID
        self.epicAppName = epicAppName
        self.lastPlayed = lastPlayed
        self.totalPlayTime = totalPlayTime
    }

    // Resolves the macOS filesystem path to the executable
    func resolvedExecutablePath(in bottle: Bottle) -> URL {
        if executablePath.hasPrefix("/") {
            return URL(fileURLWithPath: executablePath)
        }
        return bottle.driveCPath.appending(path: executablePath)
    }

    func resolvedWorkingDirectory(in bottle: Bottle) -> URL {
        if let wd = workingDirectory {
            if wd.hasPrefix("/") { return URL(fileURLWithPath: wd) }
            return bottle.driveCPath.appending(path: wd)
        }
        return resolvedExecutablePath(in: bottle).deletingLastPathComponent()
    }
}
