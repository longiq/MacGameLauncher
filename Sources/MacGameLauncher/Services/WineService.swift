import Foundation

enum WineError: LocalizedError {
    case wineNotFound
    case bottleNotInitialized
    case executableNotFound(URL)
    case processLaunchFailed(Error)
    case commandFailed(Int32, String)

    var errorDescription: String? {
        switch self {
        case .wineNotFound:
            return "Wine not found. Install Whisky or Homebrew wine."
        case .bottleNotInitialized:
            return "Bottle is not initialized. Create it first."
        case .executableNotFound(let url):
            return "Executable not found: \(url.path)"
        case .processLaunchFailed(let e):
            return "Failed to launch process: \(e.localizedDescription)"
        case .commandFailed(let code, let output):
            return "Wine command exited with code \(code): \(output)"
        }
    }
}

struct WineService {

    // MARK: - Launch a Windows executable in a bottle

    static func launch(
        executable: URL,
        args: [String] = [],
        workingDirectory: URL? = nil,
        bottle: Bottle,
        wine: WineEnvironment
    ) throws -> Process {
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw WineError.executableNotFound(executable)
        }

        let process = Process()
        process.executableURL = wine.wine64Path
        process.arguments = [executable.path] + args
        process.currentDirectoryURL = workingDirectory
            ?? executable.deletingLastPathComponent()
        process.environment = bottle.launchEnvironment(wine: wine)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw WineError.processLaunchFailed(error)
        }
        return process
    }

    // MARK: - Run a wine utility command and capture output

    static func runCommand(
        _ command: String,
        args: [String] = [],
        bottle: Bottle,
        wine: WineEnvironment
    ) async throws -> String {
        let process = Process()
        process.executableURL = wine.wine64Path
        process.arguments = [command] + args
        process.environment = bottle.launchEnvironment(wine: wine)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw WineError.processLaunchFailed(error)
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
        }
    }

    // MARK: - Initialize a new bottle prefix (wineboot --init)

    static func initBottle(_ bottle: Bottle, wine: WineEnvironment) async throws {
        try FileManager.default.createDirectory(
            at: bottle.path,
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = wine.wine64Path
        process.arguments = ["wineboot", "--init"]
        process.environment = bottle.launchEnvironment(wine: wine)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw WineError.processLaunchFailed(error)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { proc in
                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    continuation.resume(throwing: WineError.commandFailed(proc.terminationStatus, output))
                }
            }
        }
    }

    // MARK: - Kill wineserver for a bottle

    static func killBottle(_ bottle: Bottle, wine: WineEnvironment) async throws {
        let process = Process()
        process.executableURL = wine.wineServerPath
        process.arguments = ["-k"]
        process.environment = bottle.launchEnvironment(wine: wine)

        try process.run()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
    }

    // MARK: - Run winecfg (configuration GUI)

    static func openWinecfg(bottle: Bottle, wine: WineEnvironment) throws -> Process {
        let process = Process()
        process.executableURL = wine.wine64Path
        process.arguments = ["winecfg"]
        process.environment = bottle.launchEnvironment(wine: wine)
        try process.run()
        return process
    }

    // MARK: - Stream output from a running process (non-blocking)

    static func streamOutput(from pipe: Pipe, handler: @escaping @Sendable (String) -> Void) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                pipe.fileHandleForReading.readabilityHandler = nil
                return
            }
            if let line = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { handler(line) }
            }
        }
    }

    // MARK: - Get pipe from a process's standardOutput

    static func outputPipe(for process: Process) -> Pipe {
        if let existing = process.standardOutput as? Pipe {
            return existing
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        return pipe
    }
}
