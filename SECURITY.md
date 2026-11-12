# Security Policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through [GitHub's private vulnerability reporting](https://github.com/JakobFelixJulius/offshoot/security/advisories/new) with steps to reproduce and the Offshoot and macOS versions. You will get an answer within a week.

## Scope

Offshoot runs `/usr/bin/git` in folders you add, with your git configuration and credentials. Relevant reports include anything that makes Offshoot run git in a folder you did not add, pass untrusted input to git as options, or lose local work. Behavior of git itself, its hooks or its configuration is out of scope.
