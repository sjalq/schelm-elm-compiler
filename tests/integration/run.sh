#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }
expect_fail() {
  label=$1
  pattern=$2
  shift 2
  if "$@" >"$work/failure.out" 2>&1; then
    fail "$label unexpectedly succeeded"
  fi
  grep -Eiq "$pattern" "$work/failure.out" || {
    sed -n '1,100p' "$work/failure.out" >&2
    fail "$label failed for the wrong reason"
  }
  pass "$label"
}

: "${SCHELM_BIN:?set SCHELM_BIN to the built Schelm executable}"
: "${ELM_BIN:?set ELM_BIN to an official Elm 0.19.1 executable}"
SCHELM_BIN=$(cd "$(dirname "$SCHELM_BIN")" && pwd)/$(basename "$SCHELM_BIN")
command -v "$ELM_BIN" >/dev/null 2>&1 || fail "ELM_BIN is not executable"
test "$($SCHELM_BIN --version)" = 0.1.0-alpha.1 || fail "unexpected Schelm version"
test "$($ELM_BIN --version)" = 0.19.1 || fail "ELM_BIN must be Elm 0.19.1"

work=$(mktemp -d "${TMPDIR:-/tmp}/schelm-integration.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
export SCHELM_HOME="$work/schelm-home"
export ELM_HOME="$work/elm-home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME='Schelm Tests'
export GIT_AUTHOR_EMAIL='tests@invalid.example'
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME
export GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
export GIT_AUTHOR_DATE='2000-01-01T00:00:00Z'
export GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE

write_app() {
  root=$1
  mkdir -p "$root/src"
  cat >"$root/elm.json" <<'JSON'
{"type":"application","source-directories":["src"],"elm-version":"0.19.1","dependencies":{"direct":{"elm/core":"1.0.5","elm/json":"1.1.3"},"indirect":{}},"test-dependencies":{"direct":{},"indirect":{}}}
JSON
  cat >"$root/src/Main.elm" <<'ELM'
module Main exposing (main)
import Platform
main : Program () () Never
main = Platform.worker { init = \_ -> ((), Cmd.none), update = \msg model -> (model, Cmd.none), subscriptions = \_ -> Sub.none }
ELM
}

write_package() {
  root=$1 name=$2 version=$3 module=$4 body=$5 deps=${6:-}
  mkdir -p "$root/src"
  cat >"$root/elm.json" <<JSON
{"type":"package","name":"$name","summary":"Deterministic Schelm integration fixture","license":"BSD-3-Clause","version":"$version","exposed-modules":["$module"],"elm-version":"0.19.0 <= v < 0.20.0","dependencies":{"elm/core":"1.0.0 <= v < 2.0.0"$deps},"test-dependencies":{}}
JSON
  printf '%b\n' "$body" >"$root/src/$module.elm"
}

publish_repo() {
  source=$1 remote=$2 tag=$3
  git -C "$source" init -q
  git -C "$source" add .
  git -C "$source" commit -qm fixture
  git -C "$source" tag "$tag"
  git init -q --bare "$remote"
  git -C "$source" remote add origin "$remote"
  git -C "$source" push -q origin HEAD "$tag"
}

install_from() {
  project=$1 package=$2 remote=$3
  (cd "$project" && printf 'y\n' | "$SCHELM_BIN" install "$package" --from "$remote")
}

# An ordinary application and an extension-free package remain accepted by both compilers.
write_app "$work/ordinary"
(cd "$work/ordinary" && "$SCHELM_BIN" make src/Main.elm --output=schelm.js)
(cd "$work/ordinary" && "$ELM_BIN" make src/Main.elm --output=elm.js)
pass 'ordinary Elm 0.19.1 application compatibility'

write_package "$work/plain-package" acme/plain 1.0.0 Plain 'module Plain exposing (answer)\n{-| @docs answer -}\nanswer : Int\nanswer = 42'
(cd "$work/plain-package" && "$SCHELM_BIN" make src/Plain.elm --output=/dev/null)
(cd "$work/plain-package" && "$ELM_BIN" make src/Plain.elm --output=/dev/null)
pass 'extension-free package compatibility'

# Install an official effect-manager package so its public source can be copied
# into a local Git fixture below. This is the only non-local fixture acquisition.
(cd "$work/ordinary" && printf 'y\n' | "$SCHELM_BIN" install elm/time)

# Transitive routing and bare semantic-version tag discovery.
write_package "$work/transitive-src" acme/transitive 1.0.0 Transitive 'module Transitive exposing (value)\n{-| @docs value -}\nvalue : Int\nvalue = 40'
publish_repo "$work/transitive-src" "$work/transitive.git" 1.0.0
write_package "$work/router-src" acme/router 1.0.0 Router 'module Router exposing (answer)\n{-| @docs answer -}\nimport Transitive\nanswer : Int\nanswer = Transitive.value + 2' ',"acme/transitive":"1.0.0 <= v < 2.0.0"'
cat >"$work/router-src/schelm.json" <<JSON
{"format":1,"sources":{"acme/transitive":"$work/transitive.git"},"resolved":{}}
JSON
publish_repo "$work/router-src" "$work/router.git" 1.0.0
write_app "$work/git-app"
install_from "$work/git-app" acme/router "$work/router.git"
grep -q '"commit"' "$work/git-app/schelm.json"
grep -q '"sha256"' "$work/git-app/schelm.json"
cat >"$work/git-app/src/Main.elm" <<'ELM'
module Main exposing (main)
import Platform
import Router
main : Program () Int Never
main = Platform.worker { init = \_ -> (Router.answer, Cmd.none), update = \msg model -> (model, Cmd.none), subscriptions = \_ -> Sub.none }
ELM
(cd "$work/git-app" && "$SCHELM_BIN" make src/Main.elm --output=app.js)
pass 'Git install, bare tags, and transitive routing'

# A modified cache is rejected by the content pin.
cached=$(find "$SCHELM_HOME/0.19.1/packages/acme/router/1.0.0/src" -name Router.elm -print -quit)
printf '\n-- tampered\n' >>"$cached"
expect_fail 'modified cached package content rejection' 'hash changed|source hash' bash -c "cd '$work/git-app' && '$SCHELM_BIN' make src/Main.elm --output=app.js"
rm -rf "$SCHELM_HOME/0.19.1/packages/acme/router/1.0.0"

# Moving a previously pinned tag is rejected even with an empty package cache.
printf '\n-- moved tag\n' >>"$work/router-src/src/Router.elm"
git -C "$work/router-src" add .
git -C "$work/router-src" commit -qm moved
git -C "$work/router-src" tag -f 1.0.0 >/dev/null
git -C "$work/router-src" push -q --force origin 1.0.0
expect_fail 'moved immutable Git tag rejection' 'locked Git release changed' bash -c "cd '$work/git-app' && '$SCHELM_BIN' make src/Main.elm --output=app.js"

# Tag, package name, and elm.json version must agree.
write_package "$work/wrong-name-src" wrong/name 1.0.0 Wrong 'module Wrong exposing (x)\n{-| @docs x -}\nx = 1'
publish_repo "$work/wrong-name-src" "$work/wrong-name.git" 1.0.0
write_app "$work/wrong-name-app"
expect_fail 'package name mismatch rejection' 'package name.*wrong/name.*expected acme/expected' install_from "$work/wrong-name-app" acme/expected "$work/wrong-name.git"
write_package "$work/wrong-version-src" acme/wrongversion 1.0.1 WrongVersion 'module WrongVersion exposing (x)\n{-| @docs x -}\nx = 1'
publish_repo "$work/wrong-version-src" "$work/wrong-version.git" 1.0.0
write_app "$work/wrong-version-app"
expect_fail 'tag and version mismatch rejection' 'tag 1.0.0.*version 1.0.1' install_from "$work/wrong-version-app" acme/wrongversion "$work/wrong-version.git"

# A non-Elm author package can provide kernel JavaScript.
write_package "$work/kernel-src" acme/kernel-proof 1.0.0 KernelProof 'module KernelProof exposing (answer)\n{-| @docs answer -}\nimport Elm.Kernel.SchelmProof\nanswer : Int\nanswer = Elm.Kernel.SchelmProof.answer'
mkdir -p "$work/kernel-src/src/Elm/Kernel"
cat >"$work/kernel-src/src/Elm/Kernel/SchelmProof.js" <<'JS'
/*
*/
var _SchelmProof_answer = 42;
JS
publish_repo "$work/kernel-src" "$work/kernel.git" 1.0.0
write_app "$work/kernel-app"
install_from "$work/kernel-app" acme/kernel-proof "$work/kernel.git"
cat >"$work/kernel-app/src/Main.elm" <<'ELM'
module Main exposing (main)
import KernelProof
import Platform
main : Program () Int Never
main = Platform.worker { init = \_ -> (KernelProof.answer, Cmd.none), update = \_ model -> (model, Cmd.none), subscriptions = \_ -> Sub.none }
ELM
(cd "$work/kernel-app" && "$SCHELM_BIN" make src/Main.elm --output=app.js)
pass 'arbitrary-author kernel package'

# The same kernel path in an application remains forbidden.
mkdir -p "$work/kernel-app/src/Elm/Kernel"
cp "$work/kernel-src/src/Elm/Kernel/SchelmProof.js" "$work/kernel-app/src/Elm/Kernel/SchelmProof.js"
cat >"$work/kernel-app/src/Main.elm" <<'ELM'
module Main exposing (main)
import Elm.Kernel.SchelmProof
main = Elm.Kernel.SchelmProof.answer
ELM
expect_fail 'application-level kernel code rejection' 'kernel|module' bash -c "cd '$work/kernel-app' && '$SCHELM_BIN' make src/Main.elm --output=app.js"

# Re-publish the official elm/time source under another author. Its effect module
# and kernel implementation must compile when installed as a Git package.
time_cache="$SCHELM_HOME/0.19.1/packages/elm/time/1.0.0"
test -d "$time_cache/src" || fail 'elm/time source was not cached'
cp -R "$time_cache" "$work/effect-src"
rm -f "$work/effect-src/.schelm-origin.json"
sed -i.bak 's/"name": "elm\/time"/"name": "acme\/effect-proof"/' "$work/effect-src/elm.json"
rm -f "$work/effect-src/elm.json.bak"
publish_repo "$work/effect-src" "$work/effect.git" 1.0.0
write_app "$work/effect-app"
install_from "$work/effect-app" acme/effect-proof "$work/effect.git"
cat >"$work/effect-app/src/Main.elm" <<'ELM'
module Main exposing (main)
import Platform
import Time
main : Program () () ()
main = Platform.worker { init = \_ -> ((), Cmd.none), update = \_ model -> (model, Cmd.none), subscriptions = \_ -> Time.every 1000 (\_ -> ()) }
ELM
(cd "$work/effect-app" && "$SCHELM_BIN" make src/Main.elm --output=app.js)
pass 'arbitrary-author effect-manager package'

printf 'All Schelm integration tests passed.\n'
