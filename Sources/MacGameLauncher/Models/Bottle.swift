import Foundation

struct Bottle: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var path: URL
    var arch: WineArch
    var metalHUD: Bool
    var esync: Bool
    var msync: Bool
    var dxvkEnabled: Bool
    var createdAt: Date

    enum WineArch: String, Codable {
        case win32, win64
    }

    init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        arch: WineArch = .win64,
        metalHUD: Bool = true,
        esync: Bool = true,
        msync: Bool = true,
        dxvkEnabled: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.arch = arch
        self.metalHUD = metalHUD
        self.esync = esync
        self.msync = msync
        self.dxvkEnabled = dxvkEnabled
        self.createdAt = createdAt
    }

    var isInitialized: Bool {
        FileManager.default.fileExists(atPath: path.appending(path: "drive_c").path)
    }

    var driveCPath: URL { path.appending(path: "drive_c") }

    func launchEnvironment(wine: WineEnvironment) -> [String: String] {
        var env = ProcessInfo.processInfo.environment

        env["WINEPREFIX"]  = path.path
        env["WINEARCH"]    = arch.rawValue
        env["WINEESYNC"]   = esync   ? "1" : "0"
        env["WINEMSYNC"]   = msync   ? "1" : "0"
        env["WINEDEBUG"]   = "-all"

        // D3DMetal — best graphics path on Apple Silicon (M4)
        env["DXMT_ENABLE_METAL"]     = "1"
        env["D3DM_ENABLE_METAL"]     = "1"
        env["MVK_ALLOW_METAL_FENCES"] = "1"

        // Metal HUD overlay
        env["MTL_HUD_ENABLED"] = metalHUD ? "1" : "0"
        env["DXMT_HUD"]        = metalHUD ? "1" : "0"

        // DXVK (disabled by default in favour of D3DMetal on Apple Silicon)
        env["DXVK_ASYNC"]    = dxvkEnabled ? "1" : "0"

        // Prepend wine binary directory to PATH so wineserver is found
        let wineDir = wine.wine64Path.deletingLastPathComponent().path
        if let existingPath = env["PATH"] {
            env["PATH"] = wineDir + ":" + existingPath
        } else {
            env["PATH"] = wineDir
        }

        return env
    }
}
