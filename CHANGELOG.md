# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- The ... menu in the board header holds only board options (show archived, add dated cards to Apple Calendar). The project options live in the project menu in the sidebar, so nothing is offered twice.

### Security
- Boto and `boto-mcp` refuse to open a database that holds data from a newer version, instead of migrating it and dropping that data.

### Added
- Links in a card description are clickable. Boto finds web addresses, `www.` addresses, addresses with a path and e-mail addresses, and reads Markdown links as `[title](https://...)`. File names such as `README.md` stay plain text, and only web and mail links are ever opened. Click the text to edit it again.
- Pasting into a description or a note keeps links copied from an e-mail or a web page, where the address is hidden behind a title: it is pasted as `[title](address)`, which shows as a link. Web pages are only read for their links and never loaded.
- Notes use a small face, show their links as links, and can be found with search (⌘K). With Group by importance they sit in a row above the lanes.
- MCP: `list_notes` and `create_note`, and `search` also finds notes.
- Note text can be small or medium, from the Aa menu in the Notes header.
- Notes: each project has a space of sticky notes, free text on coloured squares for annotations that are not tasks. Add one with Note in the board header: they sit in a Notes column before the lists. A deleted note comes back from Recently deleted, and Duplicate project copies the notes.

## [0.2.0] - 2026-10-27

### Added
- Duplicate project, in the project menu: a copy with the same boards, lists, labels, checklists and cards, or Duplicate without cards for an empty template. Hours, activity and Apple Calendar links stay with the original.
- `boto-mcp`, an MCP server inside the app for AI assistants: read boards, cards and hours, and create, edit, move and archive cards, duplicate projects, tick checklist items and log time. It only reads unless started with `--allow-writes`, and it has no delete tool.
- Project icons: pick one from the Lucide set (about 1,900, ISC licence) with search by name or topic, or leave it to Boto. In the sidebar, right-click a project and choose Change icon.
- Recently deleted: a sidebar entry that lists deleted projects, lists and cards and restores each one. A list comes back with its cards.

### Changed
- Hours report: period chips with the chosen range marked, a bar for each day and card, entries grouped by day with a subtotal, and delete on hover.
- The "Add time" form opens on demand in the report, and takes a typed time ("1:30", "1.5", "90m", "2h30") instead of steppers. Return adds the entry.
- Commit subjects follow Conventional Commits, checked by a hook and by CI on pull requests.
- README grouped by topic, with new screenshots of the full Hours window and report.
- Status colours (done, in progress, warning, danger) live in the theme, and progress and a running timer use one blue.
- The card title is smaller (20 pt, semibold), in proportion to the text around it.
- Help has an AI assistants topic with the command that connects the MCP server and a button that copies it. Help text can now be selected and copied.
- Deleting a list or a card asks first, and the list prompt says how many cards go with it.

### Fixed
- Colour could not be set on a new card. It is now a button of its own beside Labels and Dates.
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
