#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

stack build elm:exe:schelm
install_root=$(stack path --local-install-root)
mkdir -p dist/schelm/bin
cp "$install_root/bin/schelm" dist/schelm/bin/schelm
cp LICENSE NOTICE dist/schelm/

printf 'Built %s\n' "$root/dist/schelm/bin/schelm"
"$root/dist/schelm/bin/schelm" --version-full
