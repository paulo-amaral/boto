#!/bin/bash
# Every version in CHANGELOG.md must also be in CHANGELOG.pt-BR.md, so a release never goes out with notes in only one
# language. The release workflow reads both files.
missing=0
for version in $(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'); do
  if ! grep -qF "## [$version]" CHANGELOG.pt-BR.md; then
    echo "CHANGELOG.pt-BR.md has no section for $version" >&2
    missing=1
  fi
done
exit "$missing"
