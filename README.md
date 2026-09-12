# Schelm Compiler

Schelm is an independent compiler based on
[Lamdera 1.4.1](https://github.com/lamdera/compiler) and Elm 0.19.1. It retains
Lamdera workflow commands and adds Git-native packages, including packages from
any author that contain kernel JavaScript or effect managers.

An ordinary project that does not use Schelm extensions keeps its standard
`elm.json` and compiles with official Elm 0.19.1 as well as Schelm. A project
that uses Git-only packages, package kernel JavaScript, or custom effect
managers requires Schelm and is not promised to compile with official Elm.
Applications cannot contain or directly import kernel modules.

Schelm is distinct from and not endorsed by Evan Czaplicki, Mario Rogic, Elm,
or Lamdera. Upstream copyright notices and the BSD-3-Clause license are retained
in [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Build and use

Building requires Stack, Node.js with npm, and `esbuild@0.25.9`.

```sh
git submodule update --init --recursive
npm install --global esbuild@0.25.9
./scripts/build-schelm.sh
dist/schelm/bin/schelm --version-full
```

The default cache uses the platform application-data directory named `schelm`.
Set `SCHELM_HOME` to override it. `ELM_HOME` remains an explicit compatibility
override.

```sh
schelm make src/Main.elm
schelm install elm/http
schelm install author/project --from https://example.com/author/project.git
```

See [SCHELM.md](SCHELM.md) for identity and maintenance, and
[Git packages](docs/schelm-packages.md) for package resolution and publication.

## Install and verify

Install the current prerelease on Linux or macOS:

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/sjalq/schelm-elm-compiler/main/scripts/install.sh | bash
```

Install it from PowerShell on 64-bit Windows:

```powershell
irm https://raw.githubusercontent.com/sjalq/schelm-elm-compiler/main/scripts/install.ps1 | iex
```

The installers download the matching release archive, verify its SHA-256
checksum, and install `schelm` on your user PATH. Set `SCHELM_VERSION` and
`SCHELM_INSTALL_DIR` to select another release or location.

Release tags have the form `v0.1.0-alpha.1`. Download the archive for your OS
and architecture plus its matching `.sha256` file from the GitHub release.
Verify it with `sha256sum --check FILE.sha256` on Linux or
`shasum -a 256 --check FILE.sha256` on macOS. On Windows, compare
`(Get-FileHash FILE.zip -Algorithm SHA256).Hash` with the first field in the
`.sha256` file. `SHA256SUMS` is available when verifying every archive together.
GitHub also publishes a keyless build-provenance attestation for each archive.
Extract the archive, place `schelm` or `schelm.exe` on `PATH`, and run
`schelm --version-full`. With GitHub CLI installed, verify provenance with
`gh attestation verify ARCHIVE --repo sjalq/schelm-elm-compiler`.

The inherited `installers/`, `distribution/`, and npm installer sources are
historical upstream material. They are not supported Schelm distribution paths.
Source builds and GitHub release archives are the supported paths.

## Trust model

Git tags resolve to immutable commit and content pins in `schelm.json`; Schelm
has no package registry or mandatory lockfile. Review repository, tag, and pin
changes before accepting them. Kernel JavaScript and effect managers execute
with the generated program's authority, outside Elm's usual package safety
boundary, so install them only from authors you trust.

Elm and Lamdera remain their own upstream projects. Their documentation is
useful for the compatible language and retained workflows, but Schelm support
and contributions belong in this repository.
