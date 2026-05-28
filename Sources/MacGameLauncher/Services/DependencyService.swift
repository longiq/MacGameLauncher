import Foundation

struct DependencyService {

    // winetricks verbs required before Epic Games Launcher can run
    static let epicDependencies: [String] = [
        "vcrun2019",
        "dotnet48",
        "corefonts",
    ]

    // MARK: - Install winetricks components

    static func installComponents(
        _ components: [String],
        bottle: Bottle,
        wine: WineEnvironment,
        job: InstallerJob
    ) async throws {
        let winetricks = winetricksPath()
        guard let winetricks else {
            await MainActor.run { job.appendLog("winetricks not found — skipping dependencies") }
            return
        }

        for component in components {
            await MainActor.run { job.appendLog("Installing \(component)…") }

            let process = Process()
            process.executableURL = winetricks
            process.arguments = ["--unattended", component]
            var env = bottle.launchEnvironment(wine: wine)
            env["WINEPREFIX"] = bottle.path.path
            process.environment = env

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = pipe
            WineService.streamOutput(from: pipe) { line in job.appendLog(line) }

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { proc in
                    Task { @MainActor in
                        if proc.terminationStatus == 0 {
                            cont.resume()
                        } else {
                            job.appendLog("Warning: \(component) exited with code \(proc.terminationStatus)")
                            cont.resume()  // non-fatal — continue with remaining components
                        }
                    }
                }
                do { try process.run() } catch { cont.resume(throwing: WineError.processLaunchFailed(error)) }
            }
        }
    }

    private static func winetricksPath() -> URL? {
        let candidates = [
            "/usr/local/bin/winetricks",
            "/opt/homebrew/bin/winetricks",
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
