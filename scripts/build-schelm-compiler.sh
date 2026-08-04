#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$ROOT/toolchain.env"
export PATH="$HOME/.ghcup/bin:$PATH"

[[ $(ghc --numeric-version) == "$GHC_VERSION" ]] || {
  printf 'expected GHC %s, got %s\n' "$GHC_VERSION" "$(ghc --numeric-version)" >&2
  exit 1
}
[[ $(cabal --numeric-version) == "$CABAL_INSTALL_VERSION" ]] || {
  printf 'expected cabal-install %s, got %s\n' "$CABAL_INSTALL_VERSION" "$(cabal --numeric-version)" >&2
  exit 1
}
[[ $(git -C "$ROOT" rev-parse "$KERNEL_AUTHORIZATION_COMMIT") == "$KERNEL_AUTHORIZATION_COMMIT" ]]
git -C "$ROOT" diff --quiet "$KERNEL_AUTHORIZATION_COMMIT" -- \
  elm.cabal cabal.config compiler builder src terminal || {
  printf 'compiler source differs from pinned authorization commit %s\n' "$KERNEL_AUTHORIZATION_COMMIT" >&2
  exit 1
}

cd "$ROOT"
cabal build --offline
binary=$(cabal list-bin exe:elm)
mkdir -p result/bin
cp "$binary" result/bin/elm
actual=$(sha256sum result/bin/elm | cut -d' ' -f1)
printf '%s  result/bin/elm\n' "$actual" > result/elm.sha256
[[ $actual == "$LINUX_X86_64_COMPILER_SHA256" ]] || {
  printf 'compiler SHA-256 %s != pinned %s\n' "$actual" "$LINUX_X86_64_COMPILER_SHA256" >&2
  exit 1
}
printf 'built Schelm compiler %s (%s)\n' "$actual" "$(result/bin/elm --version)"
