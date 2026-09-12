#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

if ! command -v esbuild >/dev/null 2>&1; then
  printf 'esbuild is required to embed the REPL worker (npm install --global esbuild@0.25.9)\n' >&2
  exit 127
fi

exe=schelm
if [[ ${OS:-} == Windows_NT ]]; then
  exe=schelm.exe
fi
mkdir -p dist/schelm/bin
if [[ ${OS:-} == Windows_NT ]]; then
  stack install elm:exe:schelm --local-bin-path "$root/dist/schelm/bin" \
    --ghc-options '-optl"-Wl,-Bstatic,-lstdc++,-lgcc_s,-lwinpthread,-Bdynamic"'
  cp distribution/dlls/* dist/schelm/bin/
else
  stack install elm:exe:schelm --local-bin-path "$root/dist/schelm/bin"
fi
cp LICENSE NOTICE dist/schelm/

printf 'Built %s\n' "$root/dist/schelm/bin/$exe"
"$root/dist/schelm/bin/$exe" --version-full
