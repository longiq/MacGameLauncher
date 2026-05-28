import Foundation
import Observation

@Observable
@MainActor
final class ProcessMonitor {
    private(set) var runningProcesses: [UUID: Process] = [:]

    func register(process: Process, for game: Game) {
        runningProcesses[game.id] = process
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runningProcesses.removeValue(forKey: game.id)
            }
        }
    }

    func isRunning(_ game: Game) -> Bool {
        runningProcesses[game.id]?.isRunning == true
    }

    func terminate(_ game: Game) {
        runningProcesses[game.id]?.terminate()
        runningProcesses.removeValue(forKey: game.id)
    }

    func terminateAll() {
        runningProcesses.values.forEach { $0.terminate() }
        runningProcesses.removeAll()
    }

    var runningCount: Int { runningProcesses.values.filter { $0.isRunning }.count }
}
