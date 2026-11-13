# Contributing to Offshoot

Thanks for helping. Offshoot aims to stay small, native and safe, so the bar for new features is "does this help someone keep their local checkouts current?" If you plan something larger than a fix, open an issue first so we can agree on the shape.

## Development setup

You need macOS 14 or later and Xcode 16 or later (Swift 6). There are no third-party dependencies.

```bash
git clone https://github.com/JakobFelixJulius/offshoot.git
cd offshoot
swift build                      # debug build
swift test                       # git integration tests against throwaway repositories
scripts/build-app.sh --install   # build Offshoot.app, copy to ~/Applications, launch
```

`swift run` starts the binary without an app bundle, which works for quick checks, but launch at login and the app icon need the bundle from `scripts/build-app.sh`.

You can also open `Package.swift` in Xcode.

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/Offshoot/Git.swift` | Runs git (and other tools) non-interactively with a timeout |
| `Sources/Offshoot/GitHubCLI.swift` | Optional pull request lookups through `gh` |
| `Sources/Offshoot/Snapshot.swift` | Reads branch, upstream, changes, branch lists and worktrees in one pass |
| `Sources/Offshoot/Cleanup.swift` | The rules for which branches and worktrees are merged, as pure functions |
| `Sources/Offshoot/Repo.swift` | Per-repository actions: switch, pull, update default branch, sync, cleanups |
| `Sources/Offshoot/RepoStore.swift` | Repository list, Fetch All, background fetch, launch at login |
| `Sources/Offshoot/AppDelegate.swift` | Entry point; menu bar app without a Dock icon |
| `Sources/Offshoot/StatusController.swift` | The menu bar item and its `NSMenu`, updated in place while open |
| `Sources/Offshoot/MenuItems.swift` | Closure-based menu items and the keep-open row (Fetch All, cleanups) |
| `Sources/Offshoot/RepoPresentation.swift` | Menu titles, status and branch ordering |
| `Sources/Offshoot/SettingsWindowController.swift`, `SettingsView.swift` | The Settings window and its SwiftUI panes |
| `Sources/Offshoot/MenuBarIcon.swift`, `StatusIcon.swift` | Menu bar icon and colored status badges |
| `Tests/OffshootTests` | Integration tests that drive real git against temporary repositories, and cleanup rule tests |
| `scripts/` | App bundle build, icon and social card rendering, demo repositories |
| `Casks/offshoot.rb` | Homebrew cask, updated by the release workflow |

## Guidelines

- **Safety first.** Offshoot must never lose work: no resets, no merges that are not fast-forwards, nothing on a dirty checkout without the user asking, and no `--force` on worktrees. The one force operation, `git branch -D` in Delete Merged Branches, is only allowed after the checks in `Cleanup.swift` and the commit re-check in `Repo.deleteMergedBranches`. Destructive actions list what they will do before the confirming click. Changes to git behavior need a test in `Tests/OffshootTests`.
- **Native first.** Prefer standard AppKit/SwiftUI controls over custom drawing, and keep the menu a real `NSMenu`.
- **Swift 6 strict concurrency**, no warnings.
- **Format** with the bundled formatter before committing; CI runs the same lint:

  ```bash
  swift format format --in-place --recursive Sources Tests scripts Package.swift
  swift format lint --strict --recursive Sources Tests scripts Package.swift
  ```

- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:` …).
- **Changelog**: add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.

## Pull requests

1. Fork and create a branch from `main`.
2. Make your change with tests, run `swift test` and the lint above.
3. Open a pull request and fill in the template. CI must be green.

## Demo repositories

`scripts/demo-repos.sh` creates five repositories with local remotes in `~/OffshootDemo` (or a folder you pass) that show every state: behind, ahead, uncommitted changes, a stale default branch, worktrees, and branches for each cleanup rule. Use them to try changes by hand and for README screenshots, so no real repository or branch names end up in them. Add them in Settings → Repositories, and delete the folder when you are done.

## Releasing (maintainers)

1. Move the `[Unreleased]` entries in `CHANGELOG.md` under a new version heading and commit.
2. Tag and push: `git tag v1.2.3 && git push origin v1.2.3`.
3. The release workflow tests, builds a universal app, publishes the GitHub release with the changelog section as notes, and updates `Casks/offshoot.rb`.

### Signing and notarization

Releases are ad-hoc signed until a Developer ID is configured. To notarize, add these repository secrets; the release workflow picks them up automatically:

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | Base64 of the exported *Developer ID Application* certificate (`base64 -i cert.p12`) |
| `DEVELOPER_ID_CERT_PASSWORD` | Password of that `.p12` |
| `DEVELOPER_ID_IDENTITY` | Signing identity, e.g. `Developer ID Application: Name (TEAMID)` |
| `NOTARY_APPLE_ID` | Apple ID used for notarization |
| `NOTARY_TEAM_ID` | Team ID |
| `NOTARY_PASSWORD` | App-specific password for that Apple ID |

Once releases are notarized, drop the "First launch" section from the README.
