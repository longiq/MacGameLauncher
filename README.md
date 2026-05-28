# MacGameLauncher

A personal macOS game launcher for playing Windows-only games (Steam, Epic Games, etc.) on Apple Silicon Macs using Wine/GPTK.

> Built for **Mac mini M4** — macOS 15 Sequoia, Apple Silicon (ARM64).

---

## Features

- **Bottle management** — create isolated Wine prefixes (WINEPREFIX) per game library
- **Steam** — one-click install + auto-scan installed games via `.acf` manifests
- **Epic Games** — install Epic Games Launcher + scan `.item` manifests
- **Game library** — grid view with Steam CDN artwork, search, sort by name/last played/play time
- **D3DMetal** — Apple's DirectX → Metal translation, optimal for M4 (enabled by default)
- **Play time tracking** — last played date and cumulative hours per game
- **Wine detection** — auto-detects Whisky, GPTK, or Homebrew Wine at launch
- **Rosetta 2 check** — warns on first launch if Rosetta 2 is not installed

---

## Requirements

**On your Mac before building:**

1. **Rosetta 2** (required — Wine is x86-64, runs via Rosetta on Apple Silicon):
   ```bash
   softwareupdate --install-rosetta --agree-to-license
   ```

2. **Wine** — install one of:
   - [Whisky](https://getwhisky.app) *(recommended — GPTK-based, best M4 compatibility)*
   - Homebrew: `brew install wine-stable`
   - Apple GPTK: installs to `/usr/local/bin/wine64`

3. **Xcode 16** (or Swift 5.9+ standalone toolchain)

---

## Build

```bash
# Clone
git clone https://github.com/longiq/MacGameLauncher.git
cd MacGameLauncher

# Build (release)
swift build -c release

# Run
.build/release/MacGameLauncher
```

**Or open in Xcode:**
```bash
open Package.swift
```
Press `Cmd+R` to build and run.

> **Verify toolchain** if needed:
> ```bash
> xcode-select -p
> # Should print: /Applications/Xcode.app/Contents/Developer
> ```

---

## Getting Started

1. Launch the app — it auto-detects Wine and warns if Rosetta 2 is missing
2. Click **+** in the sidebar to create a Wine bottle (select Win64 architecture)
3. In the game library toolbar, open **Launchers → Install Steam**
4. SteamSetup.exe downloads and runs in Wine — complete the Windows installer
5. Use **Launchers → Scan for Games** to discover your installed Steam library
6. Click any game tile to play, or use the detail pane's **Play** button

> **Epic Games** works the same way via **Launchers → Install Epic Games**.

---

## Data Locations

| Item | Path |
|------|------|
| Bottles | `~/Library/Application Support/MacGameLauncher/Bottles/` |
| Store (JSON) | `~/Library/Application Support/MacGameLauncher/store.json` |
| Artwork cache | `~/Library/Caches/MacGameLauncher/Artwork/` |

---

## Architecture

```
MacGameLauncher/
├── Package.swift                          # SPM manifest, macOS 15, no external deps
└── Sources/MacGameLauncher/
    ├── main.swift                         # Entry point (MacGameLauncherApp.main())
    ├── MacGameLauncherApp.swift           # App struct, injects environments
    ├── Models/
    │   ├── WineEnvironment.swift          # Wine detection, Rosetta check
    │   ├── Bottle.swift                   # WINEPREFIX struct, launchEnvironment()
    │   ├── Game.swift                     # Game metadata, path resolution
    │   ├── GameStore.swift                # @Observable persistence (store.json)
    │   └── InstallerJob.swift             # @Observable install progress tracker
    ├── Services/
    │   ├── WineService.swift              # Process launch, wineboot, wineserver
    │   ├── BottleService.swift            # Create/delete/repair bottles
    │   ├── SteamService.swift             # Install, scan ACF manifests, launch
    │   ├── EpicService.swift              # Install MSI, scan .item manifests, launch
    │   ├── ArtworkService.swift           # Steam CDN fetch, memory + disk cache
    │   └── ProcessMonitor.swift           # @MainActor — tracks running Wine processes
    └── Views/
        ├── ContentView.swift              # NavigationSplitView root
        ├── SidebarView.swift              # Bottle list + context menus
        ├── GameLibraryView.swift          # LazyVGrid + search + launcher toolbar
        ├── GameCardView.swift             # 160×240pt portrait card + hover
        ├── GameDetailView.swift           # Hero banner, play button, stats
        ├── BottleDetailView.swift         # Config toggles + Wine tools
        ├── CreateBottleSheet.swift        # New bottle wizard
        ├── AddGameSheet.swift             # Manual game entry + file picker
        ├── InstallerProgressView.swift    # Download/install progress + log
        └── SettingsView.swift             # Wine path override, cache controls
```

**Key design decisions:**

| Topic | Decision |
|---|---|
| State management | `@Observable` (Swift 5.9) — `@State` for owned objects in App/Views |
| Bottle editing in Forms | Local `@State var editingBottle: Bottle` copy, `store.updateBottle` on `onChange` |
| Graphics backend | D3DMetal (DXMT env vars) — DirectX → Metal, native Apple Silicon path |
| Wine priority | Whisky → GPTK → Homebrew (Whisky has best M4 GPTK integration) |
| Sandboxing | Disabled — required to spawn Wine `Process` instances freely |
| No external dependencies | Pure Foundation + AppKit + SwiftUI; no WhiskyKit or other packages |
| `@MainActor` isolation | Only `ProcessMonitor` is `@MainActor`; Wine process callbacks use `Task { @MainActor in }` |

---

## Troubleshooting

**"Wine not found" on launch**
Install [Whisky](https://getwhisky.app) or run `brew install wine-stable`. Then use **Settings → Re-detect Wine**.

**Rosetta 2 warning**
Run `softwareupdate --install-rosetta --agree-to-license` in Terminal and relaunch.

**Game crashes immediately**
- Try disabling DXVK in Bottle settings (D3DMetal is the correct path for M4)
- Try enabling Metal HUD to verify GPU is being used
- Run `winecfg` from Bottle tools to check Wine configuration

**Steam/Epic installer hangs**
The installer runs as a Wine process — it may show a Windows UI dialog. Check Dock for a Wine/Windows application icon.
