# Homebrew cask for BrewBrowser.
#
# This is the canonical source of the cask, kept under version control with the
# app. To publish it, copy this file into the tap repo (ad-rpi/homebrew-tap) at
# Casks/brewbrowser.rb — see RELEASING.md.
cask "brewbrowser" do
  version "0.1.0"
  # SHA-256 of dist/BrewBrowser-0.1.0.zip from build_release.sh. Re-generate and
  # update this whenever you rebuild the artifact you actually upload.
  sha256 "255aa3dbf40a2a65a14139d33eac42198f2758b7ab1b993090daf25afeb6c2f9"

  url "https://github.com/ad-rpi/BrewBrowser/releases/download/v#{version}/BrewBrowser-#{version}.zip",
      verified: "github.com/ad-rpi/BrewBrowser/"
  name "BrewBrowser"
  desc "GUI for browsing and managing Homebrew packages"
  homepage "https://github.com/ad-rpi/BrewBrowser"

  # Matches MACOSX_DEPLOYMENT_TARGET 14.0 (Sonoma).
  depends_on macos: :sonoma

  app "BrewBrowser.app"

  zap trash: [
    "~/Library/Application Support/BrewBrowser",
    "~/Library/Preferences/io.github.ad-rpi.BrewBrowser.plist",
  ]

  # Until the app is notarized, macOS Gatekeeper will block it on first launch.
  caveats <<~EOS
    BrewBrowser is not yet notarized. If macOS blocks it on first launch, either
    right-click the app in /Applications and choose Open, or reinstall with:

      brew install --cask --no-quarantine brewbrowser

    (Notarization is planned once an Apple Developer ID is available, after which
    this step goes away.)
  EOS
end
