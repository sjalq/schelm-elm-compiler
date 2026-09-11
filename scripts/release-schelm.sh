#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s VERSION\n' "$0" >&2
  exit 64
fi

version=$1
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

if [[ -n $(git status --porcelain) ]]; then
  printf 'refusing to release from a dirty working tree\n' >&2
  exit 1
fi

./scripts/build-schelm.sh

actual=$(dist/schelm/bin/schelm --version)
if [[ $actual != "$version" ]]; then
  printf 'requested version %s, compiler reports %s\n' "$version" "$actual" >&2
  exit 1
fi

platform=$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)
archive="dist/schelm-${version}-${platform}.tar.gz"
tar -C dist -czf "$archive" schelm

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$archive" > "$archive.sha256"
else
  shasum -a 256 "$archive" > "$archive.sha256"
fi

if [[ -n ${SCHELM_MINISIGN_SECRET_KEY:-} ]]; then
  minisign -S -s "$SCHELM_MINISIGN_SECRET_KEY" -m "$archive"
elif [[ -n ${SCHELM_GPG_KEY:-} ]]; then
  gpg --batch --yes --local-user "$SCHELM_GPG_KEY" --armor --detach-sign "$archive"
else
  printf 'set SCHELM_MINISIGN_SECRET_KEY or SCHELM_GPG_KEY to sign this release\n' >&2
  exit 1
fi

printf 'Created private release artifacts under %s/dist\n' "$root"
