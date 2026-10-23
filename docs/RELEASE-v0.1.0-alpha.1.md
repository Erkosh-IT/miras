# Miras v0.1.0-alpha.1 — macOS tester preview

An experimental SwiftUI launcher and Wine bottle manager looking for its first real-world Mac tests.

## Download

Download the attached `Miras-v0.1.0-alpha.1-macOS.zip`, extract it, and open `Miras.app`. The package contains Apple silicon (`arm64`) and Intel (`x86_64`) binaries. Xcode is not needed to run the prebuilt app.

- Miras requires macOS 13 or newer; your Wine/graphics engine may require a newer version.
- The app is ad-hoc signed, **not Developer ID signed or Apple-notarized**. Report any opening alert; consult [Apple's per-app opening guidance](https://support.apple.com/en-us/102445) if you decide to proceed.
- Wine, GPTK/D3DMetal, DXVK/MoltenVK, Winetricks, and games are not bundled.

## What is verified

- GitHub Actions successfully built and packaged the application.
- 24 automated tests passed with zero failures.
- The downloaded executable was checked for both CPU architectures.
- Binary source commit: `c23dc9863fea0dd8e0acbe0d8e9e247275337650`.
- [Build and test run](https://github.com/Erkosh-IT/miras/actions/runs/39952961630).

The GUI, game compatibility, Steam login, mods, and performance have not been verified on a developer-owned Mac. M1/M2/M3/M4 are architecture targets, not a tested-device list.

## Help test

Start by opening the interface. If you already have a working macOS Wine engine, try a fresh bottle and a simple Windows executable. Please postpone graphics-layer and mod testing until the basic flow works.

[Testing guide](https://github.com/Erkosh-IT/miras/blob/main/docs/TESTING.md) · [Submit a result](https://github.com/Erkosh-IT/miras/issues/new?template=macos-test.yml)

Report successes as well as failures, with Mac model/chip, RAM, macOS, Wine version, and relevant redacted logs.
