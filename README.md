<p align="center">
  <img src="Resources/AppIcon.png" width="128" height="128" alt="Offshoot icon">
</p>

<h1 align="center">Offshoot</h1>

<p align="center">
  Switch branches and pull your everyday git repositories from the macOS menu bar.
</p>

<p align="center">
  <a href="https://github.com/JakobFelixJulius/offshoot/actions/workflows/ci.yml"><img src="https://github.com/JakobFelixJulius/offshoot/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/JakobFelixJulius/offshoot/releases/latest"><img src="https://img.shields.io/github/v/release/JakobFelixJulius/offshoot" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/JakobFelixJulius/offshoot" alt="MIT License"></a>
</p>

Offshoot is a small, native menu bar app for the handful of local checkouts you work in every day. It shows which branch each one is on and whether it is behind, and gets you to the latest code in one or two clicks. It is not a GitHub dashboard: no issues, stars or activity feeds, just your working copies.

## Features

- **At a glance**: one menu item per repository with its branch, ↓ behind / ↑ ahead counts, uncommitted changes, and a colored status badge.
- **Switch branches**: hover a repository and pick a branch. The default branch is listed first; remote-only branches are one level deeper and get a tracking branch when you pick them.
- **Pull**: appears when the branch can fast-forward and runs `git pull --ff-only`.
- **Stale default branch**: on a feature branch, Offshoot shows when `main` (or `dev`) is behind and fast-forwards it without checking it out.
- **Fetch All** (⌘F): fetches every repository, then fast-forwards what can move safely.
- **Background fetch**: keeps the counts current every 5–60 minutes (or never).
- **Native**: a standard macOS menu with keyboard navigation and VoiceOver support, light and dark mode, launch at login.

### Safe by design

Offshoot never discards work. It only fast-forwards (`--ff-only`), never merges, rebases or resets, and skips any branch with uncommitted changes or its own unpushed commits. Background fetches only update remote-tracking refs and never touch your checkouts, so it is safe to run next to an IDE or a coding agent working in the same repository. When git refuses something, Offshoot shows git's own message in that repository's menu.

## Install

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

### Homebrew

```bash
brew tap JakobFelixJulius/offshoot https://github.com/JakobFelixJulius/offshoot
brew install --cask offshoot
```

### Download

Download `Offshoot-<version>.zip` from the [latest release](https://github.com/JakobFelixJulius/offshoot/releases/latest), unzip it and move `Offshoot.app` to `/Applications`.

### First launch

Release builds are not notarized by Apple yet, so macOS blocks the first launch. Open it once like this:

1. Open Offshoot. macOS says it cannot verify the developer; click **Done**.
2. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Offshoot.

Alternatively, remove the quarantine flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Offshoot.app
```

### Build from source

```bash
git clone https://github.com/JakobFelixJulius/offshoot.git
cd offshoot
scripts/build-app.sh --install
```

This builds with your local toolchain (Xcode 16 or later), signs ad hoc, copies the app to `~/Applications` and launches it.

## Usage

1. Click the Offshoot icon in the menu bar and choose **Settings…** (⌘,).
2. Under **Repositories**, click **+** and pick one or more git checkouts. Drag to reorder.
3. Under **General**, turn on **Launch at login** and choose a background fetch interval and menu bar icon.

The number next to the menu bar icon is how many repositories have something to pull.

| Status | Meaning |
| --- | --- |
| 🟢 ✓ | Up to date with its upstream |
| 🔵 ↓ | Behind: the branch or the default branch can be updated |
| 🟠 ✎ | Uncommitted changes |
| 🟠 ⇅ | Diverged from its upstream; resolve it in your usual git tool |
| ⚪ ↑ | Only ahead: you have commits to push |
| 🔴 ! | git reported an error; details at the top of the repository's menu |

Offshoot runs `/usr/bin/git` with your normal git configuration, SSH keys and credential helpers. It never prompts for credentials; a repository that needs them shows an error instead.

## FAQ

**Why not just use a git GUI?** Offshoot is for the moment between tasks: check where every checkout stands and update it, without opening a window.

**Does it work with worktrees?** Add any worktree folder as its own repository.

**Where are settings stored?** In `~/Library/Preferences/io.github.jakobfelixjulius.offshoot.plist`. Offshoot has no network access of its own beyond the git commands it runs.

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to get started, and please follow the [Code of Conduct](CODE_OF_CONDUCT.md). Report security issues privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © Jakob Felix Julius Sudau
