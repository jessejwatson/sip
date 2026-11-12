# Template only. The real cask lives in the tap repo; fill in version/sha256 from scripts/release.sh.
cask "sip" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE_SH"

  url "https://example.com/releases/download/v#{version}/Sip-#{version}.zip"
  name "Sip"
  desc "Menu bar reminders to drink water during work hours"
  homepage "https://example.com/sip"

  depends_on macos: ">= :sonoma"

  app "Sip.app"

  zap trash: [
    "~/Library/Application Support/com.jessejwatson.sip",
    "~/Library/Preferences/com.jessejwatson.sip.plist",
  ]
end
