#!/bin/bash
# Checks one commit subject against Conventional Commits 1.0.0: "type(scope): description", at most 72 characters.
# Used by the commit-msg hook and by the CI job, so the rule lives in one place.
# Subjects git generates for merges, reverts, fixups and squashes pass as they are.
subject=$1

case "$subject" in "Merge "*|"Revert "*|"fixup! "*|"squash! "*) exit 0 ;; esac

types='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
if ! printf '%s' "$subject" | grep -Eq "^($types)(\([a-z0-9._-]+\))?!?: .+"; then
  echo "commit subject must follow Conventional Commits: type(scope): description" >&2
  echo "  types: ${types//|/, }" >&2
  echo "  got:   $subject" >&2
  exit 1
fi
if [ "${#subject}" -gt 72 ]; then
  echo "commit subject has ${#subject} characters; keep it at 72 or fewer" >&2
  echo "  got:   $subject" >&2
  exit 1
fi
