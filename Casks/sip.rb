# Copy this file into the tap repo's Casks/ folder. scripts/release.sh fills in version and sha256.
cask "sip" do
  version "0.1.2"
  sha256 "240ea7e32f40b193bf74377cb7ce623b3dfbac045474fccfdf05fb55ed4f9fda"

  url "https://github.com/jessejwatson/sip/releases/download/v#{version}/Sip-#{version}.zip"
  name "Sip"
  desc "Menu bar reminders to drink water during work hours"
  homepage "https://github.com/jessejwatson/sip"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Sip.app"

  # Sip isn't notarised yet, so Gatekeeper would refuse to open it. Clear the quarantine flag the
  # download picked up. Remove this once releases are signed with a Developer ID and notarised.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/Sip.app"], must_succeed: false
  end

  uninstall quit: "com.jessejwatson.sip"

  zap trash: [
    "~/Library/Application Support/com.jessejwatson.sip",
    "~/Library/Preferences/com.jessejwatson.sip.plist",
  ]
end
