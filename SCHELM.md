# Schelm compiler

Schelm is an independent Elm-compatible compiler distribution based on
Lamdera. It adds Git-native package resolution and permits kernel JavaScript
inside packages while retaining the application boundary.

Schelm is not an official Elm or Lamdera release and is not endorsed by either
project. The upstream copyright notices and BSD-3-Clause terms are retained in
`LICENSE` and `NOTICE`.

## Identity

The product version is `0.1.0-dev`. The initial upstream Lamdera base is commit
`63f640f0d1ea916ba92c9440bdfd21a165247e60` from `lamdera-next`.

Run `schelm --version` for the Schelm product version, `schelm --elm-version`
for the accepted Elm application version, and `schelm --version-full` for the
Schelm, Elm, Lamdera, platform, source commit, and upstream-base identity.

## Cache

Schelm uses the platform application-data directory named `schelm`, so its
packages and artifacts do not contaminate Elm or Lamdera caches. Set
`SCHELM_HOME` to override it. `ELM_HOME` remains an explicit
compatibility override for existing build and test automation.

## Commands

Schelm exposes the standard compiler commands, including `make`, `install`,
`repl`, `init`, `reactor`, `bump`, `diff`, and `publish`. It also retains the
Lamdera workflow commands for projects that use the Lamdera platform. The
`update` command is omitted because Schelm releases must not replace themselves
with an upstream Lamdera binary.

Git package publication consists of pushing a version tag. See
`docs/schelm-packages.md` for the package format and release rules.

## Upstream maintenance

`upstream-lamdera` records the clean Lamdera base. Schelm changes live on
`main`. Update the tracking branch from `lamdera/compiler`, merge it into a
topic branch, run the compiler and package checks, and then merge that topic
branch into `main`. Preserve the upstream commit in `Schelm.Version` for every
release.

## Private releases

Run `scripts/build-schelm.sh` for a local binary. Run
`scripts/release-schelm.sh VERSION` to produce a compressed binary, SHA-256
checksum, license bundle, and detached signature. Release creation never
uploads artifacts or changes repository visibility.
