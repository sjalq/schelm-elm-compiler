#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

exe=schelm
stack_args=()
if [[ ${OS:-} == Windows_NT ]]; then
  exe=schelm.exe
  stack_args+=(--ghc-options '-optl"-Wl,-Bstatic,-lstdc++,-lgcc_s,-lwinpthread,-Bdynamic"')
fi
mkdir -p dist/schelm/bin
stack install elm:exe:schelm --local-bin-path "$root/dist/schelm/bin" "${stack_args[@]}"
if [[ ${OS:-} == Windows_NT ]]; then
  cp distribution/dlls/* dist/schelm/bin/
fi
cp LICENSE NOTICE dist/schelm/

printf 'Built %s\n' "$root/dist/schelm/bin/$exe"
"$root/dist/schelm/bin/$exe" --version-full
