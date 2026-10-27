#!/bin/bash
# Blocks secrets and local data from entering the repository (OWASP A02/A05, CI/CD-SEC-6).
# Default: scans the staged changes (pre-commit hook). With --all: scans every tracked file (CI).
# Plain bash 3.2 syntax so it runs on macOS and on the Linux runner.
set -u

if [ "${1:-}" = "--all" ]; then
    list() { git ls-files; }
    show() { cat -- "$1"; }
else
    list() { git diff --cached --name-only --diff-filter=ACM; }
    show() { git show ":$1"; }
fi

forbidden_names='(^|/)(\.env(\..*)?|id_rsa.*|id_ed25519.*|secrets\..*|credentials.*\.json)$|\.(pem|key|p12|pfx|cer|mobileprovision|provisionprofile|keychain|keychain-db|store|store-shm|store-wal|sqlite|sqlite-shm|sqlite-wal|db)$'
secret_patterns='(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----)'

failed=0
while IFS= read -r file; do
    [ -z "$file" ] && continue
    if [ "$file" != ".env.example" ] && echo "$file" | grep -Eq "$forbidden_names"; then
        echo "blocked file name: $file"; failed=1; continue
    fi
    if show "$file" 2>/dev/null | LC_ALL=C grep -aEq "$secret_patterns"; then
        echo "possible secret in: $file"; failed=1
    fi
done < <(list)

[ "$failed" -eq 1 ] && echo "Secret scan failed. Remove the item, rotate it if it was ever real, and commit again."
exit "$failed"
