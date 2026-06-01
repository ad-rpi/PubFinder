# Releasing PubFinder as a Homebrew cask

PubFinder is a GUI app, so it ships as a **cask** (not a formula). The plan is
two-phase:

1. **Now — your own tap, ad-hoc signed.** Works immediately; first launch needs
   a one-time Gatekeeper bypass.
2. **Later — official `homebrew-cask`, notarized.** Once you have an Apple
   Developer ID, notarize and (optionally) submit upstream so no tap is needed.

---

## One-time setup

### Identifiers — already wired
These are set for the `ad-rpi/PubFinder` repo:
- Cask URLs/homepage → `github.com/ad-rpi/PubFinder`.
- App bundle id → `io.github.ad-rpi.PubFinder` (and the cask `zap` path matches).
- `CategoryService.remoteURL` → `raw.githubusercontent.com/ad-rpi/PubFinder/main/categories.json`,
  so category updates ship without an app build (just push a new `categories.json`).

### Create the tap repo
A tap is just a GitHub repo named `homebrew-<something>`:

```sh
# github.com/ad-rpi/homebrew-tap
mkdir -p Casks && cp /path/to/PubFinder/Casks/pubfinder.rb Casks/
git init && git add . && git commit -m "Add pubfinder cask" && git push
```

Users then install with:

```sh
brew tap ad-rpi/tap
brew install --cask pubfinder
```

---

## Cutting a release (current: ad-hoc)

1. **Bump the version** — set `MARKETING_VERSION` in the Xcode target (currently
   `0.2.0`).
2. **Build the artifact:**
   ```sh
   ./scripts/build_release.sh
   ```
   This builds Release, ad-hoc signs, zips to `dist/PubFinder-<version>.zip`,
   and prints the **SHA-256**.
3. **Publish:** create a GitHub release tagged `v<version>` and upload the zip.
4. **Update the cask:** set `version` and `sha256` in `Casks/pubfinder.rb`,
   copy it into the tap repo, commit, push.
5. **Verify locally:**
   ```sh
   brew install --cask --no-quarantine ad-rpi/tap/pubfinder
   brew audit --cask --new pubfinder   # catches most issues before others install
   ```

### Gatekeeper note (ad-hoc only)
Because the app isn't notarized yet, users either right-click → Open once, or
install with `--no-quarantine`. The cask's `caveats` block tells them this. For
people who'd rather build it themselves, the source path is in the README.

---

## Later: notarized release

Once you have a paid Apple Developer account:

1. **Store notary credentials once:**
   ```sh
   xcrun notarytool store-credentials "PubFinderNotary" \
     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
   ```
2. **Enable the NOTARIZATION block** at the bottom of `scripts/build_release.sh`
   (Developer ID sign with `--options runtime`, `notarytool submit --wait`,
   `stapler staple`, re-zip). Remove the ad-hoc sign step.
3. **Drop the Gatekeeper caveat** from the cask — notarized apps install clean.

### Submitting to official homebrew-cask
After a notarized, reasonably stable, reasonably notable release:
- Fork `Homebrew/homebrew-cask`, add `Casks/p/pubfinder.rb`.
- Must pass `brew audit --cask --online --new pubfinder` and `brew style`.
- Requirements: app must be **notarized**, have a stable versioned download URL,
  and meet their [notability criteria](https://docs.brew.sh/Acceptable-Casks).
- Open a PR. Once merged, `brew install --cask pubfinder` works with no tap.
