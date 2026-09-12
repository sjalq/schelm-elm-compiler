#!/usr/bin/env bash
set -euo pipefail

version=${SCHELM_VERSION:-0.1.0-alpha.1}
install_dir=${SCHELM_INSTALL_DIR:-"$HOME/.local/bin"}

while [[ $# -gt 0 ]]; do
  case $1 in
    --version) version=${2:?missing version}; shift 2 ;;
    --install-dir) install_dir=${2:?missing install directory}; shift 2 ;;
    -h|--help)
      printf 'usage: install.sh [--version VERSION] [--install-dir DIRECTORY]\n'
      exit 0
      ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 64 ;;
  esac
done

case $(uname -s) in
  Linux) os=linux ;;
  Darwin) os=macos ;;
  *) printf 'Schelm supports Linux and macOS through this installer.\n' >&2; exit 1 ;;
esac

case $(uname -m) in
  x86_64|amd64) arch=x86_64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) printf 'unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

if [[ $os == macos && $arch != arm64 ]]; then
  printf 'Schelm supports macOS on Apple Silicon.\n' >&2
  exit 1
fi

for command_name in curl tar; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf '%s is required.\n' "$command_name" >&2
    exit 127
  }
done

asset="schelm-${version}-${os}-${arch}.tar.gz"
base="https://github.com/sjalq/schelm-elm-compiler/releases/download/v${version}"
work=$(mktemp -d "${TMPDIR:-/tmp}/schelm-install.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

curl --fail --location --proto '=https' --tlsv1.2 --output "$work/$asset" "$base/$asset"
curl --fail --location --proto '=https' --tlsv1.2 --output "$work/$asset.sha256" "$base/$asset.sha256"

expected=$(awk 'NR == 1 { print tolower($1) }' "$work/$asset.sha256")
case $expected in
  [0-9a-f][0-9a-f]*) ;;
  *) printf 'invalid checksum file\n' >&2; exit 1 ;;
esac
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$work/$asset" | awk '{ print tolower($1) }')
else
  actual=$(shasum -a 256 "$work/$asset" | awk '{ print tolower($1) }')
fi
[[ $actual == "$expected" ]] || { printf 'checksum verification failed\n' >&2; exit 1; }

tar -C "$work" -xzf "$work/$asset"
mkdir -p "$install_dir"
install -m 755 "$work/schelm/bin/schelm" "$install_dir/schelm"

printf 'Installed Schelm %s at %s\n' "$version" "$install_dir/schelm"
case :$PATH: in
  *:"$install_dir":*) ;;
  *) printf 'Add %s to PATH to run schelm from any directory.\n' "$install_dir" ;;
esac
"$install_dir/schelm" --version-full
