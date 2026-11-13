# Changelog

All notable changes to Offshoot are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- The GitHub CLI setting's description matches the actual rule: a pull request must contain every commit of the local branch.

## [0.3.0] - 2026-11-13

### Added

- A Worktrees submenu per repository lists every worktree with its branch and ahead/behind counts, with Open in Terminal, Reveal in Finder and Add to Offshoot for each. Merged and missing worktrees are marked.
- Clean Up Worktrees in each repository's menu removes worktrees whose branch is merged and clears records of worktrees whose folder is gone. Worktrees with uncommitted changes and all branches are kept.
- Delete Merged Branches in each repository's menu deletes merged local branches, including squash-merged ones. The default branch, the current branch and branches checked out in any worktree are kept, and each branch's last commit is logged so it can be restored.
- Both cleanups keep the menu open: the first click lists what will go and why, a second click runs it, and progress and the result show in place.
- A branch counts as merged when it is fully contained in the remote default branch (pushed branches only), when its pull request was merged and holds every local commit (with GitHub CLI), or when its remote branch was deleted (without GitHub CLI).
- Optional GitHub CLI integration (Settings → General) checks pull requests, keeps branches whose pull request was closed unmerged or that have commits the pull request never got, and fetches `refs/pull/<n>/head` to verify when needed.
- Remove Worktree… on any worktree other than the main checkout.
- The repository menu shows the result of the last action, not only errors.
- Switching branches warns when uncommitted changes would move along.

### Fixed

- Branches checked out in another worktree are marked "in worktree" and disabled, since git refuses to switch to them.
- The default branch is no longer offered for updating when another worktree has it checked out.
- Updating the default branch uses its configured upstream instead of assuming `origin/<same name>`.
- Pull no longer follows a `pull.rebase` setting; it always fast-forwards only.
- A branch that gets new commits between the cleanup preview and the confirming click is kept.

## [0.2.0] - 2026-11-13

### Changed

- Fetch All keeps the menu open, and each repository's status updates live while it fetches.
- The Settings window uses standard toolbar tabs.
- The Homebrew install instructions include `brew trust`, which current Homebrew requires for third-party taps.

### Fixed

- Long git error messages are shortened in the menu; the full text appears as a tooltip.
- The Settings window shows the selected tab's name instead of "Untitled".

## [0.1.0] - 2026-11-12

### Added

- Menu bar menu with one item per repository: branch, ahead/behind counts, uncommitted changes and a colored status badge.
- Branch switching for local branches and remote-only branches (creates a tracking branch).
- Fast-forward pull, and updating the default branch without checking it out.
- Fetch All (⌘F), which fast-forwards only clean branches that cannot diverge.
- Background fetch every 5–60 minutes that never changes checkouts.
- Settings window: repository list with drag to reorder, launch at login, fetch interval, menu bar icon style.
- One automatic retry when another git process holds a ref lock.

[Unreleased]: https://github.com/JakobFelixJulius/offshoot/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/JakobFelixJulius/offshoot/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/JakobFelixJulius/offshoot/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/JakobFelixJulius/offshoot/releases/tag/v0.1.0
