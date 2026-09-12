#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'usage: %s VERSION PLATFORM\n' "$0" >&2
  exit 64
fi

version=$1
platform=$2
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
archive="$root/dist/schelm-${version}-${platform}.tar.gz"
exe=schelm

if [[ $platform == windows-* ]]; then
  archive="$root/dist/schelm-${version}-${platform}.zip"
  exe=schelm.exe
fi

test -f "$archive"
test -f "$archive.sha256"
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$(dirname "$archive")" && sha256sum --check "$(basename "$archive").sha256")
else
  (cd "$(dirname "$archive")" && shasum -a 256 --check "$(basename "$archive").sha256")
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/schelm-release.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
if [[ $archive == *.zip ]]; then
  7z x -o"$work" "$archive" >/dev/null
else
  tar -C "$work" -xzf "$archive"
fi

packaged="$work/schelm/bin/$exe"
test "$($packaged --version)" = "$version"
test "$($packaged --elm-version)" = 0.19.1
test -f "$work/schelm/LICENSE"
test -f "$work/schelm/NOTICE"

mkdir -p "$work/project/src"
cat >"$work/project/elm.json" <<'JSON'
{"type":"application","source-directories":["src"],"elm-version":"0.19.1","dependencies":{"direct":{"elm/core":"1.0.5","elm/json":"1.1.3"},"indirect":{}},"test-dependencies":{"direct":{},"indirect":{}}}
JSON
cat >"$work/project/src/Main.elm" <<'ELM'
module Main exposing (main)
import Platform
main : Program () () Never
main = Platform.worker { init = \_ -> ((), Cmd.none), update = \_ model -> (model, Cmd.none), subscriptions = \_ -> Sub.none }
ELM
schelm_home="$work/schelm-home"
if [[ $platform == windows-* ]]; then
  schelm_home=$(cygpath -w "$schelm_home")
fi
(cd "$work/project" && SCHELM_HOME="$schelm_home" "$packaged" make src/Main.elm --output=app.js)
test -s "$work/project/app.js"

printf 'Verified release archive %s.\n' "$(basename "$archive")"
