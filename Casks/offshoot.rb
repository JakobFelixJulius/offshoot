cask "offshoot" do
  version "0.2.0"
  sha256 "c42bacf99bb8bf45f583d364d90f3edba11cdc9728197a71d1b697bfb67f30b4"

  url "https://github.com/JakobFelixJulius/offshoot/releases/download/v#{version}/Offshoot-#{version}.zip"
  name "Offshoot"
  desc "Menu bar app to switch branches and pull local git repositories"
  homepage "https://github.com/JakobFelixJulius/offshoot"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Offshoot.app"

  uninstall quit: "io.github.jakobfelixjulius.offshoot"

  zap trash: "~/Library/Preferences/io.github.jakobfelixjulius.offshoot.plist"
end
