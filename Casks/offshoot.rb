cask "offshoot" do
  version "0.3.0"
  sha256 "8d1a33e797e47aec0eb689c2bc7d96d6a72ce5d054b6a2654bc21fcde817a475"

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
