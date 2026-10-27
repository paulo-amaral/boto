#!/bin/zsh
# Blocks secrets and local data from entering the repository (OWASP A02/A05, CI/CD-SEC-6).
# Default: scans the staged changes (pre-commit hook). With --all: scans every tracked file (CI).
set -uo pipefail

if [[ "${1:-}" == "--all" ]]; then
    files=("${(@f)$(git ls-files)}")
    read_file() { cat -- "$1"; }
else
    files=("${(@f)$(git diff --cached --name-only --diff-filter=ACM)}")
    read_file() { git show ":$1"; }
fi

forbidden_names='(^|/)(\.env(\..*)?|id_rsa.*|id_ed25519.*|secrets\..*|credentials.*\.json)$|\.(pem|key|p12|pfx|cer|mobileprovision|provisionprofile|keychain|keychain-db|store|store-shm|store-wal|sqlite|sqlite-shm|sqlite-wal|db)$'
secret_patterns='(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{50,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----)'

failed=0
for file in "${files[@]}"; do
    [[ -z "$file" ]] && continue
    if [[ "$file" =~ $forbidden_names && "$file" != ".env.example" ]]; then
        echo "blocked file name: $file"; failed=1; continue
    fi
    if read_file "$file" 2>/dev/null | LC_ALL=C grep -aEq "$secret_patterns"; then
        echo "possible secret in: $file"; failed=1
    fi
done

(( failed )) && echo "Secret scan failed. Remove the item, rotate it if it was ever real, and commit again."
exit $failed
