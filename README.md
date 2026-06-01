# BrewBrowser

A native macOS GUI for [Homebrew](https://brew.sh). Browse installed formulae and
casks, see what's outdated, search the catalog, and install / uninstall / upgrade —
all driven by the `brew` CLI under the hood.

## Requirements

- macOS 14.0+
- [Homebrew](https://brew.sh) installed (the app locates `brew` in
  `/opt/homebrew/bin` or `/usr/local/bin`).

## Installing

### Via Homebrew (cask)

```sh
brew tap ad-rpi/tap
brew install --cask brewbrowser
```

> BrewBrowser isn't notarized yet (an Apple Developer ID is coming). On first
> launch macOS may block it — right-click the app and choose **Open**, or
> install with `brew install --cask --no-quarantine brewbrowser`. See
> [RELEASING.md](RELEASING.md).

### Build from source

Open `BrewBrowser.xcodeproj` in Xcode and run — it's a plain Xcode project, no
project generator or package manager required. Or from the command line:

```sh
xcodebuild -project BrewBrowser.xcodeproj -scheme BrewBrowser -configuration Release build
./scripts/build_release.sh   # produces a signed, zipped .app in dist/
```

> **Note:** BrewBrowser is **not sandboxed**, because it launches the `brew`
> command-line tool. It's intended for direct/developer distribution (e.g. a
> Homebrew cask), not the Mac App Store.

## Status

Early scaffold. Working: locate brew, list installed formulae/casks, outdated
flagging, search, `brew info` detail, and install/uninstall/upgrade with live
console output. See the source under `BrewBrowser/`.
