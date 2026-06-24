cask "prosciutto" do
  version "0.1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/OWNER/prosciutto/releases/download/v#{version}/Prosciutto.dmg",
      verified: "github.com/OWNER/prosciutto/"
  name "Prosciutto"
  desc "Open-source visual clipboard manager for macOS"
  homepage "https://github.com/OWNER/prosciutto"

  depends_on macos: ">= :sonoma"

  app "Prosciutto.app"

  zap trash: [
    "~/Library/Application Support/Prosciutto",
    "~/Library/Preferences/app.prosciutto.Prosciutto.plist",
    "~/Library/Caches/app.prosciutto.Prosciutto",
  ]
end
