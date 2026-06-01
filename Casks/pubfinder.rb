# Homebrew cask for PubFinder.
#
# Canonical source, kept under version control with the app. To publish, copy
# this file into the tap repo (ad-rpi/homebrew-tap) at Casks/pubfinder.rb —
# see RELEASING.md.
cask "pubfinder" do
  version "0.2.0"
  # SHA-256 of dist/PubFinder-0.2.0.zip from build_release.sh. Re-generate and
  # update this whenever you rebuild the artifact you actually upload.
  sha256 "000fb0666be7bf8dbea2d6daad6b9f15dbf0de7f76d1b324ba93c74047e8bd4b"

  url "https://github.com/ad-rpi/PubFinder/releases/download/v#{version}/PubFinder-#{version}.zip"
  name "PubFinder"
  desc "GUI for browsing and managing Homebrew packages"
  homepage "https://github.com/ad-rpi/PubFinder"

  # Matches MACOSX_DEPLOYMENT_TARGET 14.0 (Sonoma).
  depends_on macos: :sonoma

  app "PubFinder.app"

  zap trash: [
    "~/Library/Application Support/PubFinder",
    "~/Library/Preferences/io.github.ad-rpi.PubFinder.plist",
  ]

  # Until the app is notarized, macOS Gatekeeper will block it on first launch.
  caveats <<~EOS
    PubFinder is not yet notarized. If macOS blocks it on first launch, either
    right-click the app in /Applications and choose Open, or reinstall with:

      brew install --cask --no-quarantine pubfinder

    (Notarization is planned once an Apple Developer ID is available, after which
    this step goes away.)
  EOS
end
