# CLAUDE.md — MacGameLauncher Maintenance Guide

This file documents the project structure and conventions for AI-assisted maintenance.

---

## Project Overview

**MacGameLauncher** is a personal macOS SwiftUI app that lets you run Windows-only games (Steam, Epic) on Apple Silicon Macs via Wine/GPTK. It is not sandboxed and not for App Store distribution.

- **Target**: Mac mini M4, macOS 15 Sequoia, ARM64
- **Language**: Swift 5.9, SwiftUI, AppKit
- **Build**: Swift Package Manager (`swift build -c release`)
- **No external dependencies** — pure Apple frameworks only

---

## Repository Layout

```
Package.swift                              # SPM manifest — do not add external deps
Sources/MacGameLauncher/
  main.swift                               # Top-level entry: MacGameLauncherApp.main()
  MacGameLauncherApp.swift                 # App struct (no @main — SPM conflict)
  Models/         Pure data types (structs) and observable state
  Services/       Business logic — Wine process management, file I/O
  Views/          SwiftUI views only — no business logic here
  Info.plist      Bundle config — sandboxing disabled, ATS disabled
```

---

## Architectural Rules

### State management
- `GameStore`, `ProcessMonitor`, `ArtworkService` are `@Observable` classes
- Injected via `.environment()` in `MacGameLauncherApp`
- Consumed in views via `@Environment(Type.self)`
- Owned instances in App use `@State` (correct for `@Observable` per Swift 5.9 docs)

### Actor isolation
- `ProcessMonitor` is `@MainActor` — all calls must use `Task { @MainActor in ... }`
- `GameStore` and `ArtworkService` are NOT `@MainActor` — they are accessed from views (main thread) and from async `Task {}` blocks created inside button actions (which inherit `@MainActor` context from SwiftUI)
- Wine process callbacks (`terminationHandler`) run on a background thread — always dispatch back to main via `Task { @MainActor in }` before mutating observable state

### Models are structs
- `Bottle` and `Game` are `Codable Hashable` structs — NOT classes
- To edit in a SwiftUI Form: copy to `@State var editingBottle: Bottle`, call `store.updateBottle(new)` in `.onChange`
- Do NOT use `@Bindable` on struct types

### Services are static
- `WineService`, `BottleService`, `SteamService`, `EpicService` are `struct` with `static` methods
- No actor isolation on services — they use `async throws` with `withCheckedThrowingContinuation`
- `ArtworkService` is `@Observable` class (owns `NSCache` + disk cache state)

---

## Wine / Process Conventions

### Launching executables
All Wine process launching goes through `WineService.launch()`:
```swift
let process = try WineService.launch(
    executable: url,          // macOS URL to .exe
    args: [],                 // extra Windows args
    workingDirectory: url,    // optional; defaults to exe's parent dir
    bottle: bottle,
    wine: wine
)
```

### Environment variables
`Bottle.launchEnvironment(wine:)` builds the full env dict:
- `WINEPREFIX`, `WINEARCH`, `WINEESYNC`, `WINEMSYNC`
- `DXMT_ENABLE_METAL=1`, `D3DM_ENABLE_METAL=1` — D3DMetal for M4
- `MVK_ALLOW_METAL_FENCES=1` — MoltenVK fallback
- `MTL_HUD_ENABLED`, `DXMT_HUD` — Metal HUD overlay
- `PATH` prepended with Wine's `bin/` directory

### Bottle initialization
New bottles are initialized via `wineboot --init` (run as `wine64 wineboot --init`).
`Bottle.isInitialized` checks for existence of `drive_c/` inside the bottle path.

### Wine binary detection order
1. `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/Wine/bin/wine64` (Whisky)
2. `/usr/local/bin/wine64` (GPTK)
3. `/opt/homebrew/bin/wine64` (Homebrew)
4. Custom path from `@AppStorage("winePathOverride")`

---

## Adding Features

### New Wine tool button (e.g. in BottleDetailView)
1. Add a `Button` in `BottleDetailView.swift` under the "Tools" `Section`
2. Call the relevant `WineService` static method
3. Handle errors via the existing `errorMessage` `@State`

### New game source (e.g. GOG)
1. Add `.gog` case to `Game.GameSource` enum in `Game.swift`
2. Create `GOGService.swift` in `Services/` following `SteamService` pattern:
   - `installGOG(into:wine:job:) async throws`
   - `scanLibrary(in:) throws -> [Game]`
   - `launchGOGGame(...) throws -> Process`
3. Add a button in `GameLibraryView.launchers` menu
4. Update `GameCardView.contextMenuItems` if needed

### New bottle setting (toggle)
1. Add `var myFlag: Bool` to `Bottle.swift`
2. Add default in `Bottle.init()` and update `launchEnvironment()` if it maps to an env var
3. Add `Toggle("My Setting", isOn: $editingBottle.myFlag)` in `BottleDetailView.swift`
4. `Codable` synthesis handles persistence automatically

---

## Common Pitfalls

| Mistake | Correct pattern |
|---|---|
| Calling `monitor.register()` from nonisolated function | `Task { @MainActor in monitor.register(...) }` |
| Using `@Bindable` on `Bottle` or `Game` (structs) | Use `@State var editingBottle: Bottle` copy |
| Adding `@main` to `MacGameLauncherApp` | Keep `@main` removed; `main.swift` calls `.main()` |
| Adding external Swift packages | Project is intentionally dependency-free |
| Running Wine commands synchronously (blocking main thread) | Always use `async throws` + `withCheckedThrowingContinuation` |
| Mutating `@Observable` state from `terminationHandler` directly | Wrap in `Task { @MainActor in ... }` first |

---

## Build & Test

```bash
# Build (requires macOS with Xcode)
swift build -c release

# Run
.build/release/MacGameLauncher

# Verify toolchain
xcode-select -p
```

There are no automated tests. Manual test checklist:
- [ ] App launches, auto-detects Wine, no crash
- [ ] Create bottle → `~/Library/Application Support/MacGameLauncher/Bottles/<name>/` appears
- [ ] Install Steam → download progress shown → Wine installer dialog appears
- [ ] Scan for games → game tiles appear in grid
- [ ] Click Play → game launches, "Playing" badge appears on card
- [ ] Force Quit → process terminates, badge disappears
- [ ] Settings → Wine path and Rosetta status shown correctly

---

## Epic Games Launcher — Known Limitations (GPTK Wine)

### CEF Black Screen (unresolved)

Epic Games Launcher uses Chromium Embedded Framework (CEF) v90 with forced GPU acceleration. GPTK Wine lacks the proprietary `winemetal.dll` bridge that CrossOver ships — this means the CEF GPU process cannot initialize ANGLE/D3D11 and crashes three times, causing the renderer to time out and the launcher UI to remain a black window.

**Flags that do NOT help** (Epic overrides CEF GPU settings internally):
- `--disable-gpu`, `--use-gl=swiftshader`, `--use-angle=gl`, `--in-process-gpu`

**Workaround**: Use `legendary` CLI client to launch Epic games directly — see Legendary CLI Integration below.

### msvproc.dll Stub

`DXVAVDA fatal error: could not LoadLibrary: msvproc.dll: Module not found (0x7E)` crashes the CEF GPU process on startup. Fixed by placing a copy of `lz32.dll` as `drive_c/windows/system32/msvproc.dll` — this stub satisfies the LoadLibrary call and prevents the immediate crash (though GPU process still fails at command buffer creation due to missing winemetal).

### Epic Online Services (EOS)

EOS "needs to install" error fixed by:
1. Copying EOS files from a CrossOver bottle's `drive_c/Program Files (x86)/Epic Games/` into the GPTK bottle
2. Importing ~224 EOS registry blocks from CrossOver's `system.reg` into the GPTK bottle's `system.reg`

---

## Legendary CLI Integration

[legendary](https://github.com/legendary-gl/legendary) is an open-source Epic Games Store client that can install, update, and launch Epic games without the Epic Games Launcher UI.

### Binary location
`~/Library/Application Support/MacGameLauncher/Tools/legendary`

Managed by `LegendaryService.swift`. Stored separately from legendary's own config (in `~/.config/legendary/`) so uninstalling MacGameLauncher's Tools/ directory does not affect user's legendary auth/library data.

### Uninstall behavior
- `LegendaryService.uninstall()` removes only `MacGameLauncher/Tools/` (the binary)
- legendary config (`~/.config/legendary/`) is **not** deleted — user retains their login and library data

### Game launch routing
When legendary is installed AND authenticated, all Epic games launch via:
```
legendary launch <appName> --wine <wine64> --wine-prefix <bottle.path> --no-wine-setup --skip-version-check
```
Otherwise falls back to `EpicService.launchEpicGame()` (via Wine virtual desktop).

### Auth flow
`LegendaryService.openAuthInTerminal()` opens Terminal and runs `legendary auth`. User follows the URL → copies SID → pastes into Terminal. After auth, `isAuthenticated` returns true (checks `~/.config/legendary/user.json` for `access_token`).

---

## Wine Virtual Desktop (Epic)

Epic's bootstrap launcher calls `LaunchNonElevatedProcess` when handing off to the full UI, which requires an active Windows shell. Without a virtual desktop, this silently fails.

`EpicService.launchWithDesktop()` runs:
```
wine64 explorer /desktop=epic,1920x1080 EpicGamesLauncher.exe ...
```

`EpicService.configureManagedDesktop()` writes registry keys:
- `HKCU\Software\Wine\Explorer\Desktop = Default`
- `HKCU\Software\Wine\Explorer\Desktops\Default = 1920x1080`

This ensures child processes spawned by EpicGamesUpdater (self-updater restarts) also run inside the virtual desktop.

---

## Files NOT to modify without care

| File | Reason |
|---|---|
| `Package.swift` | Changing platforms or adding deps affects build compat |
| `Info.plist` | Sandboxing is OFF intentionally — do not enable |
| `WineEnvironment.swift` | Detection order matters for M4 (Whisky must be first) |
| `Bottle.launchEnvironment()` | D3DMetal env vars are required for M4 graphics |
| `main.swift` | Must call `.main()` at top level — do not use `@main` on the App struct |
| `LegendaryService.uninstall()` | Must only remove Tools/ — never touch `~/.config/legendary/` |
