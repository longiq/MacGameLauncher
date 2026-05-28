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
        // Step 1: Install Windows dependencies via winetricks
        await MainActor.run {
            job.phase = .running
            job.appendLog("Installing Windows dependencies (this may take several minutes)…")
        }
        try await DependencyService.installComponents(
            DependencyService.epicDependencies,
            bottle: bottle,
            wine: wine,
            job: job
        )

        // Step 2: Download Epic MSI
        await MainActor.run {
            job.phase = .downloading(progress: 0)
            job.appendLog("Downloading Epic Games Launcher…")
        }
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "EpicInstaller-\(UUID().uuidString).msi")
        let (tempURL, _) = try await URLSession.shared.download(from: epicInstallerURL)
        try FileManager.default.moveItem(at: tempURL, to: destination)

        // Step 3: Run msiexec to install Epic
        await MainActor.run {
            job.phase = .running
            job.appendLog("Running Epic installer…")
        }

        let process = Process()
        process.executableURL = wine.wine64Path
        process.arguments = ["msiexec", "/i", destination.path, "/quiet", "/norestart"]
        process.environment = bottle.launchEnvironment(wine: wine)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe
        job.setWineProcess(process)
        WineService.streamOutput(from: pipe) { line in job.appendLog(line) }

        do { try process.run() } catch { throw WineError.processLaunchFailed(error) }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                try? FileManager.default.removeItem(at: destination)
                Task { @MainActor in
                    if proc.terminationStatus == 0 {
                        job.phase = .complete
                        continuation.resume()
                    } else {
                        let msg = "Epic installer exited with code \(proc.terminationStatus)"
                        job.phase = .failed(msg)
                        continuation.resume(throwing: WineError.commandFailed(proc.terminationStatus, msg))
                    }
                }
            }
        }

        // Ensure managed desktop registry is set so child processes (updater restarts) get a shell
        configureManagedDesktop(bottle: bottle, wine: wine)
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

    // MARK: - Resolve Epic exe (installer may place it in Win64 or Win32)

    static func epicExePath(in bottle: Bottle) -> URL? {
        let candidates = [
            "Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
            "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe",
            "Program Files (x86)/Epic Games/Launcher/Portal/Binaries/Win32/EpicGamesLauncher.exe",
        ]
        return candidates
            .map { bottle.driveCPath.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Launch a game via Epic launcher URL protocol

    static func launchEpicGame(
        appName: String,
        bottle: Bottle,
        wine: WineEnvironment
    ) throws -> Process {
        guard let epicExe = epicExePath(in: bottle) else {
            throw WineError.executableNotFound(bottle.driveCPath.appending(path: "EpicGamesLauncher.exe"))
        }
        return try launchWithDesktop(epicExe, args: ["-com.epicgames.launcher://apps/\(appName)?action=launch&silent=true"], bottle: bottle, wine: wine)
    }

    static func launchEpic(bottle: Bottle, wine: WineEnvironment) throws -> Process {
        guard let epicExe = epicExePath(in: bottle) else {
            throw WineError.executableNotFound(bottle.driveCPath.appending(path: "EpicGamesLauncher.exe"))
        }
        return try launchWithDesktop(epicExe, args: [], bottle: bottle, wine: wine)
    }

    static func isEpicInstalled(in bottle: Bottle) -> Bool {
        epicExePath(in: bottle) != nil
    }

    // Configure managed desktop in bottle registry so ALL child processes (including
    // EpicGamesUpdater restarts) automatically get a virtual desktop shell.
    static func configureManagedDesktop(bottle: Bottle, wine: WineEnvironment) {
        let reg = Process()
        reg.executableURL = wine.wine64Path
        reg.arguments = ["reg", "add",
            "HKCU\\Software\\Wine\\Explorer",
            "/v", "Desktop", "/t", "REG_SZ", "/d", "Default", "/f"]
        reg.environment = bottle.launchEnvironment(wine: wine)
        try? reg.run(); reg.waitUntilExit()

        let reg2 = Process()
        reg2.executableURL = wine.wine64Path
        reg2.arguments = ["reg", "add",
            "HKCU\\Software\\Wine\\Explorer\\Desktops",
            "/v", "Default", "/t", "REG_SZ", "/d", "1920x1080", "/f"]
        reg2.environment = bottle.launchEnvironment(wine: wine)
        try? reg2.run(); reg2.waitUntilExit()
    }

    // Launch inside Wine virtual desktop.
    // explorer /desktop keeps explorer.exe alive as the Windows shell — required so that
    // Epic's bootstrap can call LaunchNonElevatedProcess when handing off to the full UI.
    // The managed-desktop registry keys (set by configureManagedDesktop) ensure child
    // processes spawned by the self-updater also run inside the virtual desktop.
    private static func launchWithDesktop(
        _ exe: URL,
        args: [String],
        bottle: Bottle,
        wine: WineEnvironment
    ) throws -> Process {
        let process = Process()
        process.executableURL = wine.wine64Path
        process.arguments = [
            "explorer", "/desktop=epic,1920x1080",
            exe.path,
            "--no-cef-sandbox",
            "-AllowSoftwareRendering",
            "-SaveToUserDir",
            "--in-process-gpu",                    // run GPU in main process — avoids IPC channel crash
            "--disable-accelerated-video-decode",  // prevent DXVA stub from being called
            "--disable-accelerated-video-encode",
            "--ignore-certificate-errors",         // Wine cert store lacks trusted roots
        ] + args
        process.environment = bottle.launchEnvironment(wine: wine)
        process.currentDirectoryURL = exe.deletingLastPathComponent()
        do { try process.run() } catch { throw WineError.processLaunchFailed(error) }
        return process
    }
}
