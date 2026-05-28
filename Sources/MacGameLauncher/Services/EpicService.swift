import Foundation

struct EpicService {

    // Epic Games Launcher Windows installer (MSI)
    static let epicInstallerURL = URL(string:
        "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi")!

    // MARK: - Install Epic Games Launcher into a bottle

    static func installEpic(
        into bottle: Bottle,
        wine: WineEnvironment,
        job: InstallerJob
    ) async throws {
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "EpicInstaller-\(UUID().uuidString).msi")

        // Download (indeterminate progress)
        await MainActor.run { job.phase = .downloading(progress: 0) }
        let (tempURL, _) = try await URLSession.shared.download(from: epicInstallerURL)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        await MainActor.run { job.phase = .running }

        // MSI files must be launched via msiexec
        let msiexecPath = bottle.driveCPath.appending(path: "windows/system32/msiexec.exe")
        let process = try WineService.launch(
            executable: msiexecPath,
            args: ["/i", destination.path, "/quiet"],
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
                    job.phase = proc.terminationStatus == 0 ? .complete : .failed("Exit code \(proc.terminationStatus)")
                    if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: WineError.commandFailed(proc.terminationStatus, ""))
                    }
                }
            }
        }
    }

    // MARK: - Scan Epic manifest directory for installed games

    static func scanLibrary(in bottle: Bottle) throws -> [Game] {
        let manifestDir = bottle.driveCPath
            .appending(path: "ProgramData/Epic/EpicGamesLauncher/Data/Manifests")

        guard FileManager.default.fileExists(atPath: manifestDir.path) else {
            return []
        }

        let items = try FileManager.default.contentsOfDirectory(
            at: manifestDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "item" }

        return items.compactMap { url -> Game? in
            guard
                let data = try? Data(contentsOf: url),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let appName = json["AppName"] as? String,
                let displayName = json["DisplayName"] as? String,
                let installLocation = json["InstallLocation"] as? String
            else { return nil }

            // Convert Windows path to relative-to-drive_c path
            let relativePath = installLocation
                .replacingOccurrences(of: "C:\\", with: "")
                .replacingOccurrences(of: "\\", with: "/")

            return Game(
                name: displayName,
                bottleID: bottle.id,
                executablePath: relativePath,
                source: .epic,
                epicAppName: appName
            )
        }
    }

    // MARK: - Launch a game via Epic launcher URL protocol

    static func launchEpicGame(
        appName: String,
        bottle: Bottle,
        wine: WineEnvironment
    ) throws -> Process {
        let epicExe = bottle.driveCPath
            .appending(path: "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe")
        return try WineService.launch(
            executable: epicExe,
            args: ["-com.epicgames.launcher://apps/\(appName)?action=launch&silent=true"],
            bottle: bottle,
            wine: wine
        )
    }

    static func launchEpic(bottle: Bottle, wine: WineEnvironment) throws -> Process {
        let epicExe = bottle.driveCPath
            .appending(path: "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe")
        return try WineService.launch(executable: epicExe, bottle: bottle, wine: wine)
    }

    static func isEpicInstalled(in bottle: Bottle) -> Bool {
        let epicExe = bottle.driveCPath
            .appending(path: "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe")
        return FileManager.default.fileExists(atPath: epicExe.path)
    }
}
