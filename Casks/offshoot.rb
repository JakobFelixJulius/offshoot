cask "offshoot" do
  version "0.1.0"
  sha256 "5311c1dc2fdc3edbf6f37a0b99158fdd654a24e0a797916291bf1883e6eb8b3d"

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
