import Foundation
import AppKit

struct LegendaryService {

    // MARK: - Paths

    static var toolsDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "MacGameLauncher/Tools")
    }

    static var binaryPath: URL { toolsDir.appending(path: "legendary") }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath.path)
    }

    static var isAuthenticated: Bool {
        let userJson = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/legendary/user.json")
        guard FileManager.default.fileExists(atPath: userJson.path),
              let data = try? Data(contentsOf: userJson),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["access_token"] != nil
    }

    // MARK: - Install

    static func install(job: InstallerJob) async throws {
        let downloadURL = URL(string:
            "https://github.com/legendary-gl/legendary/releases/latest/download/legendary_macOS.zip")!

        try FileManager.default.createDirectory(at: toolsDir, withIntermediateDirectories: true)

        await MainActor.run {
            job.phase = .downloading(progress: 0)
            job.appendLog("Downloading legendary…")
        }

        let (tempZip, _) = try await URLSession.shared.download(from: downloadURL)
        let zipDest = toolsDir.appending(path: "legendary_macOS.zip")
        try? FileManager.default.removeItem(at: zipDest)
        try FileManager.default.moveItem(at: tempZip, to: zipDest)

        await MainActor.run {
            job.phase = .running
            job.appendLog("Extracting…")
        }

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-o", zipDest.path, "-d", toolsDir.path]
        let pipe = Pipe()
        unzip.standardOutput = pipe
        unzip.standardError  = pipe
        WineService.streamOutput(from: pipe) { line in
            Task { @MainActor in job.appendLog(line) }
        }
        try unzip.run()
        unzip.waitUntilExit()
        try? FileManager.default.removeItem(at: zipDest)

        guard isInstalled else {
            let msg = "legendary binary not found after extraction"
            await MainActor.run { job.phase = .failed(msg) }
            throw WineError.commandFailed(-1, msg)
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: binaryPath.path)

        let ver = installedVersion() ?? "unknown"
        await MainActor.run {
            job.phase = .complete
            job.appendLog("legendary \(ver) installed.")
        }
    }

    static func installedVersion() -> String? {
        guard isInstalled else { return nil }
        let p = Process()
        p.executableURL = binaryPath
        p.arguments = ["--version"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Auth
    // Opens Terminal and runs `legendary auth`.
    // legendary prints a URL → user opens it, copies SID → pastes into Terminal.
    static func openAuthInTerminal() {
        let escaped = binaryPath.path.replacingOccurrences(of: "\"", with: "\\\"")
        let src = "tell application \"Terminal\" to do script \"\\\"\(escaped)\\\" auth\""
        if let script = NSAppleScript(source: src) {
            var err: NSDictionary?
            script.executeAndReturnError(&err)
        }
    }

    // MARK: - Import games from bottle manifests

    // Registers games installed via Epic launcher so legendary can launch them.
    static func importGames(from bottle: Bottle) {
        guard isInstalled, isAuthenticated else { return }
        let manifestDir = bottle.driveCPath
            .appending(path: "ProgramData/Epic/EpicGamesLauncher/Data/Manifests")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: manifestDir, includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "item" }) else { return }

        for url in items {
            guard let data  = try? Data(contentsOf: url),
                  let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let appName  = json["AppName"]  as? String,
                  let location = json["InstallLocation"] as? String else { continue }

            let rel = location
                .replacingOccurrences(of: "C:\\", with: "")
                .replacingOccurrences(of: "\\", with: "/")
            let localPath = bottle.driveCPath.appending(path: rel)
            guard FileManager.default.fileExists(atPath: localPath.path) else { continue }

            let p = Process()
            p.executableURL = binaryPath
            p.arguments = ["import-game", "--disable-dlcs", appName, localPath.path]
            p.standardOutput = Pipe()
            p.standardError  = Pipe()
            try? p.run()
            p.waitUntilExit()
        }
    }

    // MARK: - Launch

    static func launchGame(
        appName: String,
        bottle: Bottle,
        wine: WineEnvironment
    ) throws -> Process {
        let p = Process()
        p.executableURL = binaryPath
        p.arguments = [
            "launch", appName,
            "--wine",        wine.wine64Path.path,
            "--wine-prefix", bottle.path.path,
            "--no-wine-setup",
            "--skip-version-check",
        ]
        var env = bottle.launchEnvironment(wine: wine)
        env["XDG_CONFIG_HOME"] = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config").path
        p.environment = env
        do { try p.run() } catch { throw WineError.processLaunchFailed(error) }
        return p
    }

    // MARK: - Uninstall (removes only MacGameLauncher/Tools — legendary config kept)

    static func uninstall() throws {
        try FileManager.default.removeItem(at: toolsDir)
    }
}
