# Changelog

All notable changes to Offshoot are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A Worktrees submenu per repository lists every worktree with its branch and ahead/behind counts, with Open in Terminal, Reveal in Finder and Add to Offshoot for each. Merged and missing worktrees are marked.
- Clean Up Worktrees in each repository's menu removes worktrees whose branch was deleted on the remote and clears records of worktrees whose folder is gone. It confirms with a second click, keeps the menu open and shows progress and the result in place. Worktrees with uncommitted changes and all branches are kept.
- Remove Worktree… on any worktree other than the main checkout.
- Delete Merged Branches in each repository's menu deletes local branches whose remote branch was deleted, including squash-merged ones. The default branch and branches checked out in any worktree are kept, and each branch's last commit is logged so it can be restored. Same click-twice, keep-open behavior as Clean Up Worktrees.
- The repository menu shows the result of the last action, not only errors.

### Fixed

- Branches checked out in another worktree are marked "in worktree" and disabled, since git refuses to switch to them.
- The default branch is no longer offered for updating when another worktree has it checked out.

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

[Unreleased]: https://github.com/JakobFelixJulius/offshoot/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/JakobFelixJulius/offshoot/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/JakobFelixJulius/offshoot/releases/tag/v0.1.0
