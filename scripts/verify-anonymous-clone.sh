#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  printf 'usage: %s HTTPS_REPOSITORY_URL [REF]\n' "$0" >&2
  exit 64
fi

url=$1
ref=${2:-HEAD}
case $url in
  https://*) ;;
  *) printf 'repository URL must use anonymous HTTPS\n' >&2; exit 64 ;;
esac
authority=${url#https://}
authority=${authority%%/*}
case $authority in
  *@*) printf 'repository URL must not contain credentials\n' >&2; exit 64 ;;
esac

temp=$(mktemp -d "${TMPDIR:-/tmp}/schelm-clone.XXXXXX")
trap 'rm -rf "$temp"' EXIT HUP INT TERM

# Apply the empty helper through the environment so recursive submodule Git
# processes inherit it too. A successful run must not depend on local helpers,
# an askpass program, or an interactive credential prompt.
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=credential.helper
export GIT_CONFIG_VALUE_0=

git clone --quiet --no-checkout "$url" "$temp/repository"
git -C "$temp/repository" checkout --quiet "$ref"
git -C "$temp/repository" submodule update --init --recursive
git -C "$temp/repository" submodule status --recursive | grep -E '^[ +]' >/dev/null
printf 'Anonymous recursive clone verified at %s.\n' "$ref"
