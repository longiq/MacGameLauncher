import Foundation
import Observation

@Observable
final class InstallerJob: Identifiable {
    let id = UUID()
    let name: String
    let bottle: Bottle

    enum Phase {
        case downloading(progress: Double)
        case running
        case complete
        case failed(String)

        var isTerminal: Bool {
            switch self {
            case .complete, .failed: return true
            default: return false
            }
        }
    }

    var phase: Phase = .downloading(progress: 0)
    var logOutput: String = ""

    private var downloadTask: URLSessionDownloadTask?
    private var wineProcess: Process?

    init(name: String, bottle: Bottle) {
        self.name = name
        self.bottle = bottle
    }

    func cancel() {
        downloadTask?.cancel()
        wineProcess?.terminate()
        phase = .failed("Cancelled by user")
    }

    func setDownloadTask(_ task: URLSessionDownloadTask) {
        downloadTask = task
    }

    func setWineProcess(_ process: Process) {
        wineProcess = process
    }

    func appendLog(_ line: String) {
        logOutput += line + "\n"
    }
}
