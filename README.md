# MacGameLauncher

A personal macOS game launcher for playing Windows-only games (Steam, Epic Games, etc.) on Apple Silicon Macs using Wine/GPTK.

> Built for Mac mini M4 — macOS 15 Sequoia, Apple Silicon (ARM64).

---

## Features

- **Bottle management** — create isolated Wine prefixes per game library
- **Steam launcher** — one-click install + auto-scan installed games
- **Epic Games** — install Epic Games Launcher + scan manifests
- **Game library** — grid view with Steam artwork (fetched automatically)
- **D3DMetal** — Apple's DirectX → Metal translation for best M4 performance
- **Play time tracking** — last played date and total hours

---

## Requirements

**On your Mac before building:**

1. **Rosetta 2** (required for Wine x86-64 on Apple Silicon):
   ```bash
   softwareupdate --install-rosetta --agree-to-license
   ```

2. **Wine** — install one of:
   - [Whisky](https://getwhisky.app) *(recommended — GPTK-based, best M4 compatibility)*
   - Homebrew: `brew install wine-stable`

3. **Xcode 15** or **Swift 5.9+** toolchain

---

## Build

```bash
# Clone
git clone <repo-url>
cd MacGameLauncher

# Build with Swift Package Manager
swift build -c release

# Run
.build/release/MacGameLauncher
```

**Or open in Xcode:**
```bash
open Package.swift
```
Then press `Cmd+R` to build and run.

---

## Getting Started

1. Launch the app
2. Click **+** in the sidebar to create a Wine bottle
3. In the game library, click the **Launchers** menu → **Install Steam**
4. Steam Setup will download and run in Wine — follow the installer
5. After Steam installs, use **Scan for Games** to discover your library
6. Click any game tile to play

---

## Data Locations

| Item | Path |
|------|------|
| Bottles | `~/Library/Application Support/MacGameLauncher/Bottles/` |
| Store | `~/Library/Application Support/MacGameLauncher/store.json` |
| Artwork cache | `~/Library/Caches/MacGameLauncher/Artwork/` |

---

## Architecture

- **SwiftUI** — native macOS 15 UI, `NavigationSplitView`
- **`@Observable`** — Swift 5.9 Observation framework
- **No external dependencies** — self-contained Swift Package
- **Wine detection priority**: Whisky → GPTK (`/usr/local/bin`) → Homebrew
- **Graphics**: D3DMetal by default (DirectX → Metal, optimal for M4)
