import Foundation

struct WineEnvironment: Equatable {
    let wine64Path: URL
    let wineServerPath: URL
    let source: WineSource

    enum WineSource: String, Codable {
        case whisky   = "Whisky"
        case gptk     = "GPTK"
        case homebrew = "Homebrew"
        case custom   = "Custom"
    }

    // Detect Wine in priority order: Whisky first (GPTK-based, best for M4)
    static func detect(customPath: String? = nil) -> WineEnvironment? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        var candidates: [(URL, WineSource)] = [
            (
                home.appending(path: "Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64"),
                .whisky
            ),
            (URL(fileURLWithPath: "/usr/local/bin/wine64"), .gptk),
            (URL(fileURLWithPath: "/opt/homebrew/bin/wine64"), .homebrew),
            (URL(fileURLWithPath: "/usr/local/opt/wine-stable/bin/wine64"), .homebrew),
        ]

        if let custom = customPath, !custom.isEmpty {
            candidates.insert((URL(fileURLWithPath: custom), .custom), at: 0)
        }

        for (url, source) in candidates {
            guard fm.isExecutableFile(atPath: url.path) else { continue }
            let serverURL = url.deletingLastPathComponent().appending(path: "wineserver")
            return WineEnvironment(
                wine64Path: url,
                wineServerPath: serverURL,
                source: source
            )
        }
        return nil
    }

    // Check Rosetta 2 — required on Apple Silicon (M4) to run x86_64 Wine
    static func isRosettaInstalled() -> Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/share/rosetta/rosetta")
    }
}
