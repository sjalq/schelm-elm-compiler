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

temp=$(mktemp -d "${TMPDIR:-/tmp}/schelm-clone.XXXXXX")
trap 'rm -rf "$temp"' EXIT HUP INT TERM
git clone --quiet --recurse-submodules "$url" "$temp/repository"
git -C "$temp/repository" checkout --quiet "$ref"
git -C "$temp/repository" submodule update --init --recursive
git -C "$temp/repository" submodule status --recursive | grep -Eq '^[ +]'
printf 'Anonymous recursive clone verified at %s.\n' "$ref"
