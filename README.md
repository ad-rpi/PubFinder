# PubFinder

A native macOS GUI for [Homebrew](https://brew.sh) — find your "pubs." Browse
installed formulae and casks, see what's outdated, browse the full installable
catalog by category, search, manage taps, and install / uninstall / upgrade —
all driven by the `brew` CLI under the hood.

## Requirements

- macOS 14.0+
- [Homebrew](https://brew.sh) installed (the app locates `brew` in
  `/opt/homebrew/bin` or `/usr/local/bin`).

## Installing

### Via Homebrew (cask)

```sh
brew tap ad-rpi/tap
brew install --cask pubfinder
```

> PubFinder isn't notarized yet (an Apple Developer ID is coming). On first
> launch macOS may block it — right-click the app and choose **Open**, or
> install with `brew install --cask --no-quarantine pubfinder`. See
> [RELEASING.md](RELEASING.md).

### Build from source

Open `PubFinder.xcodeproj` in Xcode and run — it's a plain Xcode project, no
project generator or package manager required. Or from the command line:

```sh
xcodebuild -project PubFinder.xcodeproj -scheme PubFinder -configuration Release build
./scripts/build_release.sh   # produces a signed, zipped .app in dist/
```

> **Note:** PubFinder is **not sandboxed**, because it launches the `brew`
> command-line tool. It's intended for direct/developer distribution (e.g. a
> Homebrew cask), not the Mac App Store.

## Features

- Installed formulae & casks, with outdated flagging and **Upgrade All**.
- **Browse** the full installable catalog with a category drill-down
  (categories derived from Debian/Ubuntu package sections, hosted as
  `categories.json` and refreshed without an app release).
- **Taps**: view installed taps and add/remove them from the GUI.
- Live search, `brew info` detail, and install / uninstall / upgrade with
  streaming console output.

See the source under `PubFinder/`.
