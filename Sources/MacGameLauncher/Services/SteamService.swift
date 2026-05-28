import Foundation

struct SteamService {

    // Windows Steam installer (public, no auth)
    static let steamSetupURL = URL(string:
        "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!

    // MARK: - Install Steam into a bottle

    static func installSteam(
        into bottle: Bottle,
        wine: WineEnvironment,
        job: InstallerJob
    ) async throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "SteamSetup-\(UUID().uuidString).exe")

        // Download SteamSetup.exe (indeterminate progress — URLSession async download)
        await MainActor.run { job.phase = .downloading(progress: 0) }
        let (tempURL, _) = try await URLSession.shared.download(from: steamSetupURL)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        await MainActor.run { job.phase = .running }

        let process = try WineService.launch(
            executable: destination,
            bottle: bottle,
            wine: wine
        )
        job.setWineProcess(process)

        let pipe = WineService.outputPipe(for: process)
        WineService.streamOutput(from: pipe) { line in
            job.appendLog(line)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                try? FileManager.default.removeItem(at: destination)
                Task { @MainActor in
                    if proc.terminationStatus == 0 {
                        job.phase = .complete
                        continuation.resume()
                    } else {
                        let err = WineError.commandFailed(proc.terminationStatus, job.logOutput)
                        job.phase = .failed(err.localizedDescription ?? "Unknown error")
                        continuation.resume(throwing: err)
                    }
                }
            }
        }
    }

    // MARK: - Scan Steam library inside a bottle for installed games

    static func scanLibrary(in bottle: Bottle) throws -> [Game] {
        let steamApps = bottle.driveCPath
            .appending(path: "Program Files (x86)/Steam/steamapps")

        guard FileManager.default.fileExists(atPath: steamApps.path) else {
            return []
        }

        let manifests = try FileManager.default.contentsOfDirectory(
            at: steamApps,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("appmanifest_") && $0.pathExtension == "acf" }

        return manifests.compactMap { url -> Game? in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let kv = parseACF(text)
            guard
                let appIDStr = kv["appid"], let appID = Int(appIDStr),
                let name = kv["name"],
                let installDir = kv["installdir"]
            else { return nil }

            let exePath = "Program Files (x86)/Steam/steamapps/common/\(installDir)"

            return Game(
                name: name,
                bottleID: bottle.id,
                executablePath: exePath,
                source: .steam,
                steamAppID: appID
            )
        }
    }

    // MARK: - Launch a Steam game via steam -applaunch

    static func launchSteamGame(
        appID: Int,
        bottle: Bottle,
        wine: WineEnvironment
    ) throws -> Process {
        let steamExe = bottle.driveCPath
            .appending(path: "Program Files (x86)/Steam/steam.exe")
        return try WineService.launch(
            executable: steamExe,
            args: ["-applaunch", "\(appID)"],
            bottle: bottle,
            wine: wine
        )
    }

    // MARK: - Launch Steam client (no specific game)

    static func launchSteam(bottle: Bottle, wine: WineEnvironment) throws -> Process {
        let steamExe = bottle.driveCPath
            .appending(path: "Program Files (x86)/Steam/steam.exe")
        return try WineService.launch(executable: steamExe, bottle: bottle, wine: wine)
    }

    static func isSteamInstalled(in bottle: Bottle) -> Bool {
        let steamExe = bottle.driveCPath
            .appending(path: "Program Files (x86)/Steam/steam.exe")
        return FileManager.default.fileExists(atPath: steamExe.path)
    }

    // MARK: - Minimal ACF/VDF parser for Steam manifests

    static func parseACF(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var lines = text.components(separatedBy: .newlines)
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            // Match: "key"		"value"
            if line.hasPrefix("\"") {
                let parts = extractKeyValue(from: line)
                if let key = parts.0, let value = parts.1 {
                    result[key] = value
                }
            }
            i += 1
        }
        return result
    }

    private static func extractKeyValue(from line: String) -> (String?, String?) {
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        for char in line {
            if char == "\"" {
                if inQuote {
                    tokens.append(current)
                    current = ""
                }
                inQuote.toggle()
            } else if inQuote {
                current.append(char)
            }
        }
        if tokens.count >= 2 {
            return (tokens[0], tokens[1])
        }
        return (tokens.first, nil)
    }
}

