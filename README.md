<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Resources/Brand/boto-logo-dark-mode.png">
  <img src="Resources/Brand/boto-logo-transparent.png" alt="Boto logo" width="160">
</picture>

# Boto

**A personal Kanban app for macOS, with flow metrics, a timesheet and Apple Calendar built in.**

Local-first. Native. Built with Swift, SwiftUI and SwiftData.

[![CI](https://github.com/paulo-amaral/boto/actions/workflows/ci.yml/badge.svg)](https://github.com/paulo-amaral/boto/actions/workflows/ci.yml)
[![CodeQL](https://github.com/paulo-amaral/boto/actions/workflows/codeql.yml/badge.svg)](https://github.com/paulo-amaral/boto/actions/workflows/codeql.yml)
[![Release](https://img.shields.io/github/v/release/paulo-amaral/boto?include_prereleases)](https://github.com/paulo-amaral/boto/releases)
[![License: AGPL v3](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/paulo-amaral/boto)](https://github.com/paulo-amaral/boto/commits/main)
[![Issues](https://img.shields.io/github/issues/paulo-amaral/boto)](https://github.com/paulo-amaral/boto/issues)
[![Stars](https://img.shields.io/github/stars/paulo-amaral/boto)](https://github.com/paulo-amaral/boto/stargazers)

![Platform](https://img.shields.io/badge/macOS-14%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.10%2B-orange)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)
![Top language](https://img.shields.io/github/languages/top/paulo-amaral/boto)
![Repo size](https://img.shields.io/github/repo-size/paulo-amaral/boto)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)
[![Dependabot](https://img.shields.io/badge/Dependabot-enabled-025e8c?logo=dependabot)](https://github.com/paulo-amaral/boto/blob/main/.github/dependabot.yml)
[![Keep a Changelog](https://img.shields.io/badge/changelog-Keep%20a%20Changelog-E05735)](CHANGELOG.md)
[![SemVer](https://img.shields.io/badge/SemVer-2.0.0-3F4551)](https://semver.org/)

[Download](https://github.com/paulo-amaral/boto/releases) · [Build from source](#build-from-source) · [Security](SECURITY.md) · [Português](README.pt-BR.md)

</div>

Boto is a Kanban board for one person. Projects hold boards, boards hold lists, and lists hold cards. Your data stays on your Mac in a file you own, with daily backups. It was made for consultants who need to see what is in progress, how long work really takes, and how many hours went into which task.

## Screenshots

All screenshots use made-up sample data.

### Board

<p align="center">
  <img src="docs/images/board.png" alt="Boto Kanban board with four lists, labels, due dates, a blocked card and a WIP limit" width="100%">
  <br><sub>Lists with labels, due dates, a blocked card and a WIP limit.</sub>
</p>

### Card and flow

<table align="center">
  <tr>
    <td align="center" width="50%">
      <img src="docs/images/card.png" alt="Boto card with importance, label, due date, description and a checklist at 50 percent">
      <br><sub>A card: importance, label, due date, description and steps.</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/images/flow.png" alt="Boto flow metrics: cycle time, Kaizen experiment, throughput and cumulative flow">
      <br><sub>Flow: cycle time, a Kaizen experiment, throughput and cumulative flow.</sub>
    </td>
  </tr>
</table>

### Hours

<p align="center">
  <img src="docs/images/hours-timesheet.png" alt="Boto weekly timesheet by task and day with totals" width="90%">
  <br><sub>Weekly timesheet by task and day.</sub>
</p>

<p align="center">
  <img src="docs/images/hours-report.png" alt="Boto hours report by day and by card, with every entry listed" width="55%">
  <br><sub>Report by period, by day, by card and by entry.</sub>
</p>

## Features

**Boards**
- Projects, boards, lists and cards with labels, colours, checklists, due dates and a Markdown description.
- Drag and drop between lists. Command-click to select several cards. Archive instead of delete.
- Group by importance (High, Medium, Low), filter by label, list or due date, search, and a command palette.
- References on a card: local files and folders, Obsidian notes, GitHub issues and pull requests, and Mail messages. Boto stores pointers and never copies or edits your files.
- Import from Trello and GitHub.

**Flow and Kaizen**
- WIP limits and a policy note per list, and a Blocked flag with a reason.
- Throughput, work item age, cycle time, a service level expectation (85th percentile) and a cumulative flow chart, following the Kanban Guide.
- A Kaizen log: write a problem, an experiment and what you expect, then review it on a date.

**Hours**
- A timer on every card, or log time by hand.
- A weekly timesheet by task and day with totals, editable in place, plus a report by period.
- Export to CSV. Formula-looking text is neutralised so spreadsheets do not run it.

**Apple Calendar**
- Put a card's due date on a calendar named Boto, as an all-day event or at a set time, with an alert you choose.
- Completing or archiving the card removes the event. One way: the board is the source of truth.

**Your data**
- Boards live in `~/Library/Application Support/Boto/`, with daily backups in `Backups/`.
- The only network code is the GitHub integration, and it runs when you use it.

## Install

1. Download `Boto-<version>.zip` from [Releases](https://github.com/paulo-amaral/boto/releases) and unzip it.
2. Move `Boto.app` to `/Applications`.
3. Boto is signed ad hoc and not notarized. On first launch, right-click the app and choose Open. If macOS still refuses, run `xattr -dr com.apple.quarantine /Applications/Boto.app`.

Each release lists a SHA-256 checksum and a build provenance attestation. Verify the download with `gh attestation verify Boto-<version>.zip --repo paulo-amaral/boto`.

Requires macOS 14 or later.

## Build from source

```sh
git clone https://github.com/paulo-amaral/boto.git
cd boto
git config core.hooksPath .githooks   # secret scan and Conventional Commits check
swift test                            # run the tests
./Scripts/make-app.sh                 # build/Boto.app
open build/Boto.app
```

You need Xcode or a Swift 5.10+ toolchain.

## Project layout

| Path | What it holds |
| --- | --- |
| `Sources/KanbanCore` | Models, flow metrics, timesheet, importers and calendar sync. No UI. |
| `Sources/KanbanUI` | SwiftUI views. |
| `Sources/Boto` | The app entry point. |
| `Tests/` | XCTest suites for the core and the UI helpers. |
| `Scripts/` | App bundling and the secret scan. |

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) first. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Credits and licence

Boto is licensed under the [GNU AGPL-3.0](LICENSE). It takes ideas from Trello and Kanbana. The interface font is Plus Jakarta Sans, under the SIL Open Font License 1.1 (`Resources/Fonts/OFL.txt`).
