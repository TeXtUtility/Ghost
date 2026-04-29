# Contributing

Thanks for considering a contribution to Ghost. A few conventions to keep
patches easy to review:

## Quick start

```
git clone https://github.com/TeXtUtility/Ghost.git
cd Ghost
./scripts/setup_dev_cert.sh    # one-time
swift test                      # 27 tests, all green
swift run                       # iterate
./scripts/build_app.sh          # install to ~/Applications/Ghost.app
```

## Code style

- Swift 6, strict concurrency. Most state is `@MainActor`-isolated since
  the app is GUI-bound; preserve that.
- The typing engine in `Sources/Ghost/Model/TypingEngine.swift` is
  pure-data and unit-tested. Keep it that way: AppKit / SwiftUI imports
  belong in the overlay or popover layers.
- New behavior that affects engine semantics (resync, backspace,
  word-skip) needs unit tests in `Tests/GhostTests/TypingEngineTests.swift`.
  We use `swift-testing` (not XCTest), so tests are `@Test` functions
  with `#expect`.

## Pull requests

- One concern per PR. Small and focused beats large and sweeping.
- Run `swift build` and `swift test` before opening; CI is light.
- If the change touches the build script, the install path, or the
  bundle id, please flag it in the PR description so reviewers can spot
  TCC-grant implications.

## Reporting bugs

When opening an issue, please include:

- macOS version (`sw_vers`).
- The output of `codesign -dvv ~/Applications/Ghost.app` if the bug is
  install / permission related.
- Whether the bug reproduces with `swift run` or only with the installed
  `.app`.
