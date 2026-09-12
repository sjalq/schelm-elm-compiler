#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

if grep -Eq 'git@github\.com:' .gitmodules; then
  printf 'SSH submodule URL found\n' >&2
  exit 1
fi

if grep -RIEq 'apps\.lamdera\.com|GH_USER_SCP_KEY|KNOWN_HOSTS|sftp[[:space:]]' .github/workflows; then
  printf 'inherited deployment endpoint or secret found in active automation\n' >&2
  exit 1
fi

base=${1:-63f640f0d1ea916ba92c9440bdfd21a165247e60}
git diff --check "$base" --

if git diff "$base" -- . ':!*.lock' | grep -Ei '^\+.*(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})'; then
  printf 'possible credential in Schelm changes\n' >&2
  exit 1
fi

printf 'Public-surface checks passed.\n'
