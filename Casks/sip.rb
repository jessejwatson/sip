# Copy this file into the tap repo's Casks/ folder. scripts/release.sh fills in version and sha256.
cask "sip" do
  version "0.1.3"
  sha256 "2252e997fc04f52c45807b1eb21e64cf1765685a6baef9fb741f12687f04a22c"

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
