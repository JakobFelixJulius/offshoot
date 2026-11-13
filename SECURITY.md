# Security Policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through [GitHub's private vulnerability reporting](https://github.com/JakobFelixJulius/offshoot/security/advisories/new) with steps to reproduce and the Offshoot and macOS versions. You will get an answer within a week.

## Scope

Offshoot runs `/usr/bin/git` in folders you add, with your git configuration and credentials, and, when you turn the option on, the GitHub CLI (`gh pr list`) with your `gh` sign-in. Relevant reports include anything that makes Offshoot run git or gh in a folder you did not add, pass untrusted input such as branch names or pull request data to git as options, delete a branch or worktree that still holds unmerged work, or lose local work otherwise. Behavior of git or gh themselves, git hooks or their configuration is out of scope.
