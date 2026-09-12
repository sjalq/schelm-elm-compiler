#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s VERSION [PLATFORM]\n' "$0" >&2
  exit 64
fi

version=$1
platform=${2:-}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

if [[ -n $(git status --porcelain) ]]; then
  printf 'refusing to release from a dirty working tree\n' >&2
  exit 1
fi

./scripts/build-schelm.sh

exe=dist/schelm/bin/schelm
extension=tar.gz
if [[ ${OS:-} == Windows_NT ]]; then
  exe=$exe.exe
  extension=zip
fi

actual=$("$exe" --version)
if [[ $actual != "$version" ]]; then
  printf 'requested version %s, compiler reports %s\n' "$version" "$actual" >&2
  exit 1
fi

if [[ -z $platform ]]; then
  platform=$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)
fi
archive="dist/schelm-${version}-${platform}.${extension}"
if [[ $extension == zip ]]; then
  (cd dist && 7z a -tzip "$(basename "$archive")" schelm >/dev/null)
else
  tar -C dist -czf "$archive" schelm
fi

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$(dirname "$archive")" && sha256sum "$(basename "$archive")") > "$archive.sha256"
else
  (cd "$(dirname "$archive")" && shasum -a 256 "$(basename "$archive")") > "$archive.sha256"
fi

printf 'Created release archive and checksum under %s/dist\n' "$root"
