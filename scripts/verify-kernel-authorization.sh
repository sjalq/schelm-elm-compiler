#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ELM=${SCHELM_ELM:-"$ROOT/result/bin/elm"}
PUBLIC_ELM_HOME=${SCHELM_PUBLIC_ELM_HOME:-"$HOME/.elm"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}
expect_failure() {
  local label=$1
  shift
  if "$@" >"$WORK/$label.stdout" 2>"$WORK/$label.stderr"; then
    fail "$label unexpectedly compiled"
  fi
  printf 'PASS expected rejection: %s\n' "$label"
}

[[ -x "$ELM" ]] || fail "compiler not executable: $ELM"
[[ -f "$PUBLIC_ELM_HOME/0.19.2/packages/registry.dat" ]] ||
  fail "SCHELM_PUBLIC_ELM_HOME must contain the public 0.19.2 registry and packages"

cp -a "$PUBLIC_ELM_HOME/." "$WORK/elm-home/"
PACKAGE_DEST="$WORK/elm-home/0.19.2/packages/sjalq/kernel-authorization-fixture/1.0.0"
mkdir -p "$PACKAGE_DEST"
cp -a "$ROOT/fixtures/kernel-authorization/authorized-package/." "$PACKAGE_DEST/"
cp -a "$ROOT/fixtures/kernel-authorization/application" "$WORK/application"
cp -a "$ROOT/fixtures/kernel-authorization/unauthorized-author" "$WORK/unauthorized-author"
cp -a "$ROOT/fixtures/kernel-authorization/application-direct-kernel" "$WORK/application-direct-kernel"
find "$WORK" -type d -name elm-stuff -prune -exec rm -rf {} +
node "$ROOT/scripts/add-private-fixture-to-registry.cjs" \
  "$WORK/elm-home/0.19.2/packages/registry.dat" sjalq kernel-authorization-fixture

for mode in debug optimize; do
  args=()
  [[ $mode == optimize ]] && args+=(--optimize)
  output="$WORK/authorized-$mode.js"
  (
    cd "$WORK/application"
    ELM_HOME="$WORK/elm-home" "$ELM" make src/Main.elm "${args[@]}" --output="$output"
  )
  runtime=$(node "$ROOT/fixtures/kernel-authorization/run-worker.cjs" "$output")
  [[ $runtime == "authorized-sjalq-kernel:elm-core:42" ]] ||
    fail "$mode runtime returned: $runtime"
  printf 'PASS authorized sjalq package + official elm/core: %s compile/runtime\n' "$mode"
done

expect_failure unauthorized-author \
  bash -c 'cd "$1" && ELM_HOME="$2" "$3" make src/Unauthorized/KernelFixture.elm --output=/dev/null' \
  _ "$WORK/unauthorized-author" "$WORK/elm-home" "$ELM"
expect_failure application-direct-kernel \
  bash -c 'cd "$1" && ELM_HOME="$2" "$3" make src/Main.elm --output=/dev/null' \
  _ "$WORK/application-direct-kernel" "$WORK/elm-home" "$ELM"

grep -q 'Elm.Kernel.UnauthorizedFixture' "$WORK/unauthorized-author.stdout" "$WORK/unauthorized-author.stderr" ||
  fail "unauthorized-author rejection did not identify the kernel import"
grep -q 'Elm.Kernel.ApplicationDirectFixture' "$WORK/application-direct-kernel.stdout" "$WORK/application-direct-kernel.stderr" ||
  fail "application-direct-kernel rejection did not identify the kernel import"

printf 'PASS all kernel authorization boundaries\n'
