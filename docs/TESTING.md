# Help test Miras on macOS

Thank you for testing. The developer does not currently have a Mac. GitHub Actions builds the universal app and runs unit tests; we still need people to verify the interface and Wine behavior on actual hardware.

## 1. Get the app

- Download a tester ZIP from [Releases](https://github.com/Erkosh-IT/miras/releases), when available. Choose the attached application ZIP, not GitHub's automatically generated source-code ZIP.
- Alternatively, download `Miras-macOS` from the [verified workflow run](https://github.com/Erkosh-IT/miras/actions/runs/39952961630). GitHub may require sign-in. Its artifact ZIP contains another ZIP with `Miras.app`.
- Extract the application and move it to a convenient location such as Applications. Xcode is not needed for this prebuilt app.
- Record the release tag or workflow commit. The initial tester binary was built from `c23dc9863fea0dd8e0acbe0d8e9e247275337650` and includes both `arm64` and `x86_64`.

Miras requires macOS 13 or newer. Wine and graphics runtimes have their own requirements. Apple silicon architecture support does not mean that every M-series Mac or game has been tested.

## 2. First check: interface only

This is intended to be a short check; report a failure at any step instead of spending time fixing it yourself.

1. Open `Miras.app` and record any macOS message verbatim.
2. Check whether the welcome window appears and can be resized without clipping essential controls.
3. Open Engine settings, then close it. With no Wine engine, the app should explain that an engine is required and disable bottle creation.
4. Open **Data folder**. It should open `~/Library/Application Support/Miras/` in Finder.
5. Quit and reopen the app. Report any crash or persistent error.

The app is ad-hoc signed, not signed with an Apple Developer ID or notarized. If Gatekeeper blocks opening it, that is a useful result. If you decide to proceed after reviewing the source, use Apple's documented per-app procedure in [Safely open apps on your Mac](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally or treat a malware/damaged-app alert as a routine approval prompt.

## 3. Second check: a fresh Wine bottle

For this first testing round, please use a **macOS Wine engine that already works on your Mac**. Record its publisher, exact version, installation source, and binary path. No engine/version combination has yet been validated with Miras on real hardware, so this guide does not label one as known-good.

1. In Engine settings, choose the engine's `wine` or `wine64` binary. It must have a sibling `wineserver`.
2. Create a new bottle called `Miras testing`. Avoid using an existing bottle containing valuable saves for this check.
3. Wait for initialization and complete any Wine setup dialogs.
4. Open **Windows configuration** from the bottle menu. Confirm whether `winecfg` opens, then close it.
5. Use **Add game** to choose the bottle's `drive_c/windows/system32/notepad.exe`, if the engine provides it, or a small trusted Windows application you already use. Leave graphics on **Engine built-ins**, synchronization **Off**, and extra dependencies unselected.
6. Press **Play**, check whether a window opens, then close it. Report whether Miras returns to an idle state.
7. Reopen Miras and check whether the bottle and shortcut remain in the library.

If something fails, open the latest bottle log. Reproduce once with **Extra Wine diagnostics** enabled if additional output would help. Stop the bottle before changing its runtime configuration.

## 4. Optional advanced checks

Only after the basic checks work, try one change at a time:

- Install a Windows `.exe` or `.msi` into a new bottle.
- Launch a game you own and record its name, version, and settings.
- Compare D3DMetal and DXVK using compatible, separately obtained runtime components.
- Start Windows Steam in the same bottle, sign in, then launch the game.
- Try a documented mod launcher with its required arguments and DLL overrides.

Do not infer compatibility from a menu opening. If reporting performance, include resolution, quality settings, FPS cap, test scene, and approximately how long the game ran. A repeatable 15-minute result is more useful than a single FPS screenshot.

## 5. Send a result, including successes

[Open a macOS test report](https://github.com/Erkosh-IT/miras/issues/new?template=macos-test.yml).

Include the Mac model/chip, RAM, macOS version, Miras build, Wine engine, steps, actual result, and relevant log excerpt. Attach screenshots when useful. Review logs before posting: redact usernames, personal paths, account information, or tokens. Do not upload game files, save files, or third-party runtime binaries.

If you attach a clear screenshot of the welcome screen or library and want it featured in the README, explicitly say that it may be reused there.

## What this test cannot establish

The 24 passing unit tests cover core behavior; they do not establish Steam login, graphics correctness, anti-cheat support, mod networking, or game performance. There is currently no verified game-compatibility list. A report should describe the exact setup tested rather than claim support for every Mac or engine.
