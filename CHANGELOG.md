# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-10-27

### Added
- `boto-mcp`, an MCP server inside the app for AI assistants: read boards, cards and hours, and create, edit, move and archive cards, tick checklist items and log time. It has no delete tool and a `--read-only` mode.
- Project icons: pick one from the Lucide set (about 1,900, ISC licence) with search by name or topic, or leave it to Boto. In the sidebar, right-click a project and choose Change icon.
- Recently deleted: a sidebar entry that lists deleted projects, lists and cards and restores each one. A list comes back with its cards.

### Changed
- Hours report: period chips with the chosen range marked, a bar for each day and card, entries grouped by day with a subtotal, and delete on hover.
- The "Add time" form opens on demand in the report, and takes a typed time ("1:30", "1.5", "90m", "2h30") instead of steppers. Return adds the entry.
- Commit subjects follow Conventional Commits, checked by a hook and by CI on pull requests.
- README grouped by topic, with new screenshots of the full Hours window and report.
- Status colours (done, in progress, warning, danger) live in the theme, and progress and a running timer use one blue.
- Deleting a list or a card asks first, and the list prompt says how many cards go with it.

### Fixed
- The Colour entry in a card's Add menu did nothing on a card that had no colour yet.
- A failed CSV export now says so instead of staying silent.
- Icon-only buttons have spoken names, and cards, search results and project rows are announced as buttons.
- The delete button in the hours report also appears with keyboard focus.

### Security
- Releases wait for approval through the `release` environment, which only accepts `v*` tags.

## [0.1.0] - 2026-10-27

### Added
- Projects, boards, lists and cards with labels, colours, checklists, due dates and references to files, Obsidian notes, GitHub items and Mail messages.
- Import from Trello and GitHub, daily backups, search, filters and a command palette.
- Flow metrics, WIP limits, blocked cards and a Kaizen log.
- Time tracking with a card timer, a weekly timesheet, a report and CSV export.
- Apple Calendar sync for due dates, with optional time and alert.
- Plus Jakarta Sans as the interface font.

### Security
- CSV exports neutralise fields that start with `=`, `+`, `-`, `@`, tab or carriage return.

[Unreleased]: https://github.com/paulo-amaral/boto/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/paulo-amaral/boto/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/paulo-amaral/boto/releases/tag/v0.1.0
