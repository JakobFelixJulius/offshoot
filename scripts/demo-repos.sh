#!/usr/bin/env bash
# Creates demo repositories that show every Offshoot state, for screenshots and manual testing.
# Remotes are local bare repositories, so nothing touches the network.
#
#   scripts/demo-repos.sh [folder]     default: ~/OffshootDemo
#
#   web-app        behind its remote by 3, two worktrees (one merged), branches for every cleanup rule
#   api            on a feature branch with uncommitted changes, while main is 2 behind
#   design-system  up to date
#   mobile-app     2 commits ahead, not pushed yet
#   docs           an uncommitted change
set -euo pipefail

ROOT="${1:-$HOME/OffshootDemo}"
if [ -e "$ROOT" ]; then
    echo "$ROOT already exists. Remove it first: rm -rf \"$ROOT\"" >&2
    exit 1
fi
REMOTES="$ROOT/.remotes"
mkdir -p "$REMOTES"

# A neutral identity and no global config (no signing prompts, hooks or aliases).
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME="Demo" GIT_AUTHOR_EMAIL="demo@example.com"
export GIT_COMMITTER_NAME="Demo" GIT_COMMITTER_EMAIL="demo@example.com"

commit() { # <dir> <file> <message>
    echo "$3" >>"$1/$2"
    git -C "$1" add "$2"
    git -C "$1" commit -qm "$3"
}

new_repo() { # <name>: bare remote, the checkout Offshoot shows, and a teammate clone
    local name=$1
    git init -q --bare -b main "$REMOTES/$name.git"
    git clone -q "$REMOTES/$name.git" "$ROOT/$name" 2>/dev/null
    commit "$ROOT/$name" README.md "# $name"
    commit "$ROOT/$name" app.txt "Initial structure"
    git -C "$ROOT/$name" push -q -u origin main
    git -C "$ROOT/$name" remote set-head origin main
    git clone -q "$REMOTES/$name.git" "$REMOTES/$name-teammate"
}

teammate_pushes() { # <name> <message>...: commits a teammate pushes to main
    local clone="$REMOTES/$1-teammate"
    shift
    git -C "$clone" pull -q
    for message in "$@"; do commit "$clone" team.txt "$message"; done
    git -C "$clone" push -q origin main
}

pushed_branch() { # <name> <branch> <message>: a branch off main with one commit, pushed with upstream
    local dir="$ROOT/$1" current
    current=$(git -C "$dir" branch --show-current)
    git -C "$dir" switch -q -c "$2" main
    commit "$dir" "${2//\//-}.txt" "$3"
    git -C "$dir" push -q -u origin "$2"
    git -C "$dir" switch -q "$current"
}

delete_on_remote() { # <name> <branch>: like GitHub deleting a squash-merged pull request branch
    git -C "$REMOTES/$1.git" branch -q -D "$2"
}

# web-app
new_repo web-app
pushed_branch web-app feat/checkout-redesign "New checkout flow"
pushed_branch web-app fix/login-redirect "Return to the last page after login"
pushed_branch web-app fix/header-typo "Fix typo in header"
git -C "$ROOT/web-app" merge -q --no-ff -m "Merge fix/header-typo" fix/header-typo
git -C "$ROOT/web-app" push -q origin main
pushed_branch web-app feat/dark-mode "Dark mode"
delete_on_remote web-app feat/dark-mode
pushed_branch web-app chore/update-dependencies "Update dependencies"
delete_on_remote web-app chore/update-dependencies
echo ".worktrees/" >>"$ROOT/web-app/.git/info/exclude"
pushed_branch web-app feat/search-filters "Search filters"
git -C "$ROOT/web-app" worktree add -q .worktrees/search-filters feat/search-filters
pushed_branch web-app feat/onboarding-tour "Onboarding tour"
git -C "$ROOT/web-app" worktree add -q .worktrees/onboarding-tour feat/onboarding-tour
delete_on_remote web-app feat/onboarding-tour
teammate_pushes web-app "Add analytics consent" "Speed up image loading" "Fix cart rounding"

# api
new_repo api
pushed_branch api feat/rate-limiting "Rate limiter skeleton"
pushed_branch api fix/timeout-retries "Retry on timeouts"
git -C "$ROOT/api" switch -q feat/rate-limiting
teammate_pushes api "Add health endpoint" "Log request ids"
echo "limit = 100" >>"$ROOT/api/app.txt"
echo "draft" >>"$ROOT/api/feat-rate-limiting.txt"

# design-system
new_repo design-system
pushed_branch design-system feat/button-variants "Button variants"

# mobile-app
new_repo mobile-app
commit "$ROOT/mobile-app" app.txt "Push notification settings"
commit "$ROOT/mobile-app" app.txt "Offline banner"

# docs
new_repo docs
echo "Work in progress" >>"$ROOT/docs/README.md"

for name in web-app api design-system mobile-app docs; do
    git -C "$ROOT/$name" fetch -q --prune
done

echo "Created demo repositories in $ROOT:"
for name in web-app api design-system mobile-app docs; do echo "  $ROOT/$name"; done
