# Recruiting the first macOS testers

## English post draft

**Title:** Looking for Mac testers: Miras, an experimental SwiftUI launcher for Windows games through Wine

Hi! I'm building Miras, a native SwiftUI game library and Wine bottle manager for macOS. I develop on Windows and don't currently have access to a Mac, so I'm looking for a few people to help check the basics on real hardware.

The universal Mac build passes compilation and 24 automated tests. The GUI, Wine sessions, and real games still need testing. Miras is experimental and doesn't bundle Wine, GPTK, or games.

The most useful first test is small: open the app, check the interface, and report what happened. If you already have working Wine on macOS, I'd also appreciate a fresh-bottle and simple-executable test. Please include your Mac model, RAM, macOS version, and exact Wine engine. Successful results are welcome too!

The download is ad-hoc signed and not Apple-notarized, so a first-launch block is also useful feedback. There are no promises of AAA compatibility or higher FPS.

Repository: https://github.com/Erkosh-IT/miras

Tester builds: https://github.com/Erkosh-IT/miras/releases

Testing guide: https://github.com/Erkosh-IT/miras/blob/main/docs/TESTING.md

Report a result: https://github.com/Erkosh-IT/miras/issues/new?template=macos-test.yml

Thanks for helping me find the bugs I can't reproduce without a Mac.

## Before posting

- Publish the tester prerelease first and replace the general Releases link with its exact URL.
- Prefer a genuine tester screenshot when one is available; do not present a mockup as proof that the app runs.
- The repository currently has no project license. Describe it as an experimental project with source available on GitHub, rather than making an open-source licensing claim, until a license is chosen.
- Recheck each community's current rules. The r/macgaming rules inspected on October 23, 2026 allow self-promotion at most once daily and ask for meaningful information. This is a ceiling, not a recommended posting frequency: start with one useful post and follow up in its comments. [Community rules](https://www.reddit.com/r/macgaming/about/rules/)
- For Wine-related Discord/Telegram groups, use their designated project/showcase/testing channel if one exists; ask moderators when unclear.
- Ask for reproducible results, not stars. Respond to reports, fix a small set of issues, and share an update when there is a concrete new build to test.

## First milestone

Aim for three independent reports covering app launch, one successful fresh bottle, and one failed case with a reproducible log. These are targets, not claims that tests have happened. Expand to Steam and graphics testing after the basic workflow is confirmed.
