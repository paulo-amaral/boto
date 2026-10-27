# Security policy

Boto is a local-first macOS app. Boards, time entries and backups stay on the user's machine; the app has no server.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting (Security tab, "Report a vulnerability"). Do not open a public issue for a vulnerability.

## Safeguards in this repository

| Area | Control | OWASP reference |
| --- | --- | --- |
| Secrets and personal data | `.gitignore` excludes keys, certificates, `.env`, databases, backups and CSV exports. `Scripts/secret-scan.sh` runs as a pre-commit hook (`.githooks/`) and in CI over every tracked file. | Top 10 A02, A05; CI/CD Top 10 CICD-SEC-6 |
| Dependencies | Dependabot checks Swift packages and GitHub Actions weekly. The app has no third-party package today. | Top 10 A06 |
| Pipeline integrity | Actions are pinned to full commit SHAs, workflows run with read-only `contents` permission, checkout does not persist credentials, and no workflow uses `pull_request_target`. | CI/CD Top 10 CICD-SEC-3, 4, 8 |
| Static analysis | CodeQL for Swift runs on push, pull request and weekly. | Top 10 A03, A08 |
| App hardening | The app is signed with the hardened runtime and a single entitlement (calendar access). Credentials go to the macOS Keychain, not to files. | Top 10 A02, A05 |

After cloning, enable the hook once: `git config core.hooksPath .githooks`.

## If a secret is committed

Rotate it first, then remove it from history. Treat any secret that reached a remote as exposed.
