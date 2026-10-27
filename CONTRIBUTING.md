# Contributing

Thanks for your interest in Boto. It is a personal project, so small and focused changes are easiest to review.

## Before you start

- Open an issue for anything larger than a bug fix, so the direction is agreed before you write code.
- Report security problems privately, as described in [SECURITY.md](SECURITY.md). Never in an issue.
- Never put real board data, client names, tokens or personal information in an issue, pull request or test. Use placeholders such as `Jane Doe` and `user@example.com`.

## Setup

```sh
git clone https://github.com/paulo-amaral/boto.git
cd boto
git config core.hooksPath .githooks
swift test
```

The hooks block commits that contain secrets or local data files, and reject a commit subject that does not follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/): `type(scope): description`, at most 72 characters, for example `fix(calendar): remove the event when a card is archived`. Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`. Use `!` after the type for a breaking change. Merge, revert, fixup and squash subjects made by git pass. The rule is in `Scripts/check-commit-subject.sh`; CI runs it on every pull request, so a branch with a bad subject fails the `commits` job.

## Pull requests

- Keep one change per pull request, with tests for new logic in `Tests/`.
- Match the surrounding code: naming, comment density, no comments that repeat the code.
- Core logic goes in `KanbanCore` and must not depend on SwiftUI. Views go in `KanbanUI`.
- `swift test` must pass. For interface changes, run the app and say what you checked.
- Commits are signed when possible. Do not use `--no-verify`.

By contributing you agree that your work is licensed under the [GNU AGPL-3.0](LICENSE).
