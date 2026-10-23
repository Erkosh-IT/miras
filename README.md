# Miras

A native macOS game library and Wine bottle manager, inspired by the workflow of CrossOver. Built with SwiftUI, Foundation, and no third-party app dependencies. This is an initial implementation, not a replacement for CrossOver's compatibility engine or support service.

**Status: experimental.** The initial macOS CI build passed compilation, unit tests, and app packaging. Real games and individual Mac models still need testing. Wine and graphics runtimes are supplied separately.

## Features

- Native SwiftUI game library with saved executable paths and launch arguments.
- Isolated Wine bottles, including automatic bottle creation for new installations.
- Windows `.exe` and `.msi` installers and a built-in shortcut to Wine configuration.
- GPTK D3DMetal import into a private copy of a compatible Wine engine.
- Per-game DXVK or D3DMetal selection, with DXVK DLL backups.
- Optional ESync, MSync, and x86_64/Rosetta launch settings.
- Selected Winetricks dependencies installed before a game launches.
- Per-operation logs and bottle-scoped process controls.
- Persistent per-bottle Steam sessions with optional Steam launch URLs.
- Custom mod DLL overrides and `.exe`, `.bat`, or `.cmd` launcher targets.

## Launcher optimizations

- DXVK preparation runs off the UI thread. Byte-for-byte comparisons use 64 KB chunks; unchanged DLLs are not rewritten, while updated packages or damaged destination files are detected. Each preparation records copied/skipped file counts and bytes written in its log.
- Windows executable architecture checks read only the 64-byte DOS header and six bytes of the PE header, rather than loading the entire executable.
- Games and Steam default to error-only Wine debug output. Enable **Extra Wine diagnostics** in Game settings to include warning and fixme messages when troubleshooting. This does not suppress output written directly by the game.
- Process logs include exit codes and elapsed times. Background Steam sessions unlock their runtime settings when the Steam loader and all Windows programs in the prefix exit, without periodic process polling.

These changes reduce unnecessary launcher I/O and keep graphics preparation off the UI thread. They do not establish an in-game FPS improvement; game performance still needs measurement on the target Mac. Dependencies continue to use Winetricks' own installed-package checks.

## Project structure

```text
Sources/Miras/              SwiftUI interface and process orchestration
Sources/MirasCore/          Models, Wine commands, runtime imports, persistence
Tests/MirasCoreTests/       Core behavior and runtime integration unit tests
packaging/Info.plist        macOS application metadata
scripts/build-app.sh        Test, build, and package Miras.app on a Mac
.github/workflows/macos.yml macOS CI build and downloadable app artifact
```

## Requirements

- macOS 13 or newer.
- Xcode Command Line Tools with Swift 5.9 or newer to build (`xcode-select --install`).
- A separately installed, macOS-compatible Wine engine with a `wine` or `wine64` executable. An engine built for Intel may require Rosetta on Apple silicon; follow that engine publisher's instructions.
- Legally acquired Windows games or installers that work with your chosen engine.

## Build and open on your Mac

Copy this project folder to your Mac, open Terminal in the folder, and run:

```bash
bash scripts/build-app.sh
open dist/Miras.app
```

The script runs unit tests on the build host and compiles a universal `arm64` / `x86_64`, ad-hoc signed `.app`. Its Apple silicon binary targets M1, M2, M3, and M4 Macs running macOS 13 or newer. A selected Wine engine or GPTK release can require a newer macOS version. This architecture support does not certify any game's compatibility or frame rate. A distributable release would additionally need a Developer ID signature and Apple notarization. The [GitHub workflow](https://github.com/Erkosh-IT/miras/actions/workflows/macos.yml) runs the build and produces a zipped app artifact.

For development, use `swift run Miras`. To run just the tests, use `swift test`.

## Install and play

1. Open **Engine settings → Find installed Wine**, or **Choose binary…** to select your engine's `wine` / `wine64` executable. In the file picker, Command–Shift–G lets you enter a directory inside an `.app` bundle.
2. Choose **New bottle**, name it, and wait for Wine to initialize its Windows environment. Wine may show its own setup dialogs.
3. Choose **Install new game…** to automatically create and initialize a separate bottle for an `.exe` or `.msi` installer. To deliberately install into the selected existing bottle, use **Run installer**. Complete the Windows installer normally.
4. Choose **Add game**, browse the bottle's `drive_c`, and select the game or mod's `.exe`, `.bat`, or `.cmd`. You can also select an existing portable game's executable outside the bottle.
5. Click **Play**. Use the game's menu to edit its name, executable path, or arguments (one argument per line, without shell quotes).

The bottle's **…** menu opens its files, launches `winecfg`, opens its latest log, or stops all Windows programs in that bottle. Stopping a bottle asks for confirmation because it can discard unsaved game progress. Removing a game removes only its library shortcut.

## Engine setup and compatibility

Miras ships no Wine binaries, Windows files, DXVK, D3DMetal, or games. It imports locally supplied runtime files and can invoke your installed Winetricks to download selected dependencies. Start with the [Wine macOS documentation](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS) and your engine publisher's installation instructions. The WineHQ macOS package maintainer also documents [macOS builds](https://github.com/Gcenx/macOS_Wine_builds).

Do not assume `brew install --cask wine-stable` is available: the [Homebrew wine-stable cask](https://formulae.brew.sh/cask/wine-stable) was listed as disabled when checked on October 23, 2026. Choose a currently available build from its publisher. Miras accepts an existing engine rather than relying on a specific download or installing one automatically.

Game support depends on macOS, CPU architecture, Wine version, graphics support, DRM, and anti-cheat requirements. Some games and kernel anti-cheat systems will not work. No individual game has been verified in this Windows development environment.

### Graphics and CPU settings

Open **Engine settings** before configuring a game's **Edit game & arguments** dialog.

- **D3DMetal:** obtain Apple's [GPTK evaluation environment](https://developer.apple.com/games/game-porting-toolkit/) under its applicable terms and use a compatible, relocatable macOS Wine distribution. Choose **Import GPTK D3DMetal libraries…** and select its `redist/lib` folder. Miras copies the selected engine into its own `Engines/<UUID>` directory, merges the libraries, and selects that copy only after import succeeds. The supported layout contains `wine/x86_64-windows/d3d11.dll`, `d3d12.dll`, and `D3DMetal.framework`. Other package layouts are rejected. This follows the distribution maintainer's [library integration approach](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/9.6); matching Wine/GPTK versions remain essential. Importing files does not prove ABI or OS compatibility. For an engine already configured by its publisher, enable **Engine already includes compatible D3DMetal** instead. Apple silicon and the selected GPTK release's macOS requirements apply.
- **DXVK:** select an extracted [macOS-compatible DXVK package](https://github.com/Gcenx/DXVK-macOS) with `x64` and, for 32-bit games, `x32` directories. Your Wine engine must already provide compatible Vulkan support and MoltenVK; Miras does not install MoltenVK. Before launch, Miras installs changed DLLs into the bottle's `system32` and `syswow64` and preserves replaced originals under `.miras-dll-backups`. Source paths and readability are checked before replacement; an I/O failure or cancellation can still leave a partial installation, in which case launch is aborted. Re-run after resolving the error. The game executable's PE architecture selects native DLL overrides; missing architecture files fail before launch. D3D9 support is available only if that package provides `d3d9.dll`; it is not promised by every macOS DXVK build. D3D12 remains an engine built-in in DXVK mode.
- **Per-game graphics:** choose engine built-ins, D3DMetal, or DXVK. Built-in overrides bypass installed native DXVK files. On a D3DMetal-patched engine, **Engine built-ins** also uses that engine's D3DMetal components; it does not restore stock WineD3D. Games with DLLs alongside their executables may override the bottle's copies and require game-specific configuration.
- **Synchronization:** declare ESync/MSync support only if the selected engine includes the corresponding patches. Each game selects Off, ESync, or MSync; Miras enables exactly one and explicitly disables the others. This avoids conflicting inherited settings but does not guarantee a performance improvement.
- **Rosetta:** the per-game x86_64 option launches Wine using `/usr/bin/arch -x86_64`. It requires an x86_64-capable engine and Rosetta on Apple silicon. Miras does not install Rosetta. macOS also automatically translates Intel-only engines during normal launches.

### Windows dependencies

Select your installed executable **Winetricks** script in Engine settings, then select `vcrun2022`, `dotnet48`, and/or `d3dcompiler_47` in Game settings. Miras runs `winetricks -q` with the selected engine and bottle before launching, waits for completion, and aborts launch on failure. Winetricks manages its own installed-verb records and download cache. Its prerequisite tools (such as cabextract) must be installed separately; see the [Winetricks project](https://github.com/Winetricks/winetricks). Unattended mode may still require publisher dialogs or manual downloads for some packages.

Dependencies are user-selected because an arbitrary executable does not reliably identify all required runtimes. No runtime is installed merely by browsing to an executable. Different games in one bottle share installed dependencies; use **Install new game…** for isolation.

One engine selection is shared across the library. Back up your bottles before switching engines or importing GPTK: Wine can upgrade a prefix, and downgrading it may not work. Choose engines with compatible macOS support; arbitrary Linux Wine binaries cannot be used. Switching the selected engine clears capability declarations so they must be configured again.

## Steam and mod launchers

1. Install Windows Steam inside the game's bottle and configure the game's graphics, synchronization, and dependencies.
2. In **Edit game & arguments**, leave the Steam path blank for `C:\Program Files (x86)\Steam\steam.exe`, or enter another `steam.exe` path inside the same bottle.
3. Optionally enter `steam://run/<AppID>` or `steam://rungameid/<AppID>`. With no URL, Miras requests the Steam client with `-silent`. URLs are passed directly to that Windows Steam client, never macOS Steam.
4. Save and choose **Start Steam / open Steam URL** in the game's menu. Miras prepares dependencies and graphics before starting Steam. Sign in and wait for Steam to be ready, then click **Play**. Starting a process does not confirm Steam login or network readiness.
5. Steam stays running when the game launcher exits. Use **Stop bottle programs** to close the session. Stop before changing graphics, synchronization, dependencies, or the selected engine. Session tracking is in memory; after restarting Miras, close existing bottle programs or use Stop before preparing another session.

The session locks its runtime profile while allowing different executable targets, mod DLL overrides, and per-game diagnostic settings. During a Steam session, Miras tracks the launched game's loader process rather than waiting for the entire wineserver to exit. Detached games may outlive that loader; session settings remain locked until all Windows programs exit or the bottle is stopped. Log files capture process errors, but Steam login and game readiness are not automatically detected.

The DLL override editor accepts one entry per line:

```text
winmm=n
version=n,b
```

Modes are `n` (native), `b` (built-in), `n,b`, `b,n`, or an empty value to disable a DLL. Names omit `.dll`. Other mod-specific names can be entered as needed; Miras neither supplies those DLLs nor enables them by default. Overrides apply to the game and its children, not the Steam client. Graphics DLL overrides remain controlled by the graphics picker.

For Mod Engine 2, target `modengine2_launcher.exe` with its documented arguments, or its supplied batch file. Miras uses the launcher's directory as the working directory and preserves the bottle. Batch launchers run through Wine's `cmd /d /s /c`; select their target game's architecture explicitly. To prevent unintended command expansion, batch paths and arguments containing quotes, `%`, `!`, `&`, `|`, `<`, `>`, or `^` are rejected. Use the executable launcher when such arguments are necessary. See the [Mod Engine 2 launcher example](https://github.com/soulsmods/ModEngine2/blob/main/installer/dist/launchmod_eldenring.bat).

Valve documents [Spacewar as a Steamworks sample application](https://partner.steamgames.com/doc/sdk/api/example). Opening AppID 480 is not a general co-op or anti-cheat fix. [Seamless Co-op's installation guide](https://ersc-docs.github.io/) requires each player to own the game on Steam. No AppID spoofing, anti-cheat modification, or networking patch is automatically installed by Miras. Elden Ring / Seamless Co-op and Dark Souls III / Archthrones have not been gameplay-tested here; choose D3DMetal or DXVK according to the actual engine and mod behavior rather than a guaranteed preset.

## Data and operation behavior

Everything is stored at `~/Library/Application Support/Miras/`:

| Path | Contents |
| --- | --- |
| `library.json` | Engine path, bottle names, game paths, arguments |
| `Bottles/<UUID>/` | Each bottle's Wine prefix and Windows C: drive |
| `Logs/<bottle UUID>-<operation UUID>.log` | Standard output and error for each operation |

Use **Data folder** to inspect or back up these files. Library saves use atomic replacement. If the library is unreadable, Miras leaves it intact and disables edits until you repair it and restart. A failed bottle creation keeps its unfinished prefix for troubleshooting; it is not added to the library. You may remove that unused UUID directory manually after checking its log and ensuring no Wine processes use it.

Each bottle runs one tracked operation at a time; separate bottles can run concurrently. Outside prepared Steam sessions, launch and installation workflows wait for the prefix's `wineserver -w`, keeping the bottle busy until detached child programs close. Before dependency or DLL changes, launch workflows also wait for previous bottle programs, including those left after restarting Miras. An open launcher can keep a bottle busy; close it or use **Stop bottle programs**, which uses `wineserver -k` and cancels remaining steps in the active launch workflow. The engine must have a sibling `wineserver`. Closing Miras does not shut down Wine or running games. Latest-log links reset when Miras restarts; all log files remain in the data folder. Logs are not automatically pruned.

Wine is a compatibility layer, not a security sandbox. Windows programs run with your macOS user's file access. Run software you trust.

## Validation status

Core tests cover library persistence, old-library migration, corruption handling, prefix isolation, argument handling, batch quoting, Steam client scoping, DLL override validation, renderer architecture checks, DXVK backups, GPTK import isolation, synchronization settings, and Winetricks commands. The initial macOS CI run passed compilation, tests, and packaging; consult the latest workflow for subsequent changes. GUI interactions, Steam sessions, real Wine/game execution, and individual M1/M2/M3/M4 hardware remain unverified.
