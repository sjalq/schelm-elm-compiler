# Schelm compiler fork

This repository contains the **unofficial Schelm compiler fork**. It starts
from official Elm `0.19.2` tag commit
`48befde196cbcbdf459114e36c02b52c49b58050` and extends kernel-package
authorization to packages owned by the dedicated Schelm package author,
`sjalq`.

The executable deliberately continues to report semantic version `0.19.2`.
Elm uses that value for package constraints and cache layout, so changing it
would break compatibility without providing a reliable fork identity. Identify
a Schelm compiler by its pinned source commit and artifact SHA-256 below, not
by `elm --version`. This fork is not endorsed by the Elm project.

## Boundary

The normal Elm safety boundaries remain in force:

- `sjalq/*` packages may contain and import `Elm.Kernel.*` modules;
- applications cannot contain or directly import kernel modules;
- package authors other than `elm`, `elm-explorations`, and `sjalq` cannot
  contain or directly import kernel modules;
- official `elm/core` kernel modules still compile and execute alongside an
  authorized Schelm package;
- kernel JavaScript remains behind annotated Elm package APIs;
- public package resolution is unchanged.

Private package resolution is intentionally outside this compiler change. The
Schelm project provides a pinned, isolated package overlay; this repository
does not add general Git dependencies or teach the compiler a second package
resolver.

## Pinned build

Pins are machine-readable in [`toolchain.env`](toolchain.env):

- GHC `9.10.3`;
- cabal-install `3.10.3.0`;
- exact package versions and Hackage index state in
  [`cabal.project.freeze`](cabal.project.freeze);
- authorization source commit
  `76bbe44424106c96f915cb24cd7f50d69f5cee0e`;
- Linux x86-64 compiler SHA-256
  `69987adf7062562b6e6dfd60b6709be3a06feeb90b096b9c84f673f2b97d8654`.

Install/select the pinned tools with GHCup, then build from a checkout that
contains the pinned authorization commit:

```sh
ghcup install ghc 9.10.3
ghcup install cabal 3.10.3.0
ghcup set ghc 9.10.3
ghcup set cabal 3.10.3.0
./scripts/build-schelm-compiler.sh
```

The script builds offline from the frozen dependency plan, copies the binary to
`result/bin/elm`, and requires its hash to match the pin. `result/` is ignored
and must not be committed unless the project first adopts an explicit release
artifact policy. Build reproducibility assumes the same Linux x86-64 system
ABI and already-populated Cabal store; use the SHA-256 as the artifact gate.

## Compiler evidence

Run the hermetic fixture matrix with a public package seed in `~/.elm` (or set
`SCHELM_PUBLIC_ELM_HOME`) and the local compiler in `result/bin/elm` (or set
`SCHELM_ELM`):

```sh
./scripts/verify-kernel-authorization.sh
```

The script copies the public cache to a temporary `ELM_HOME`, installs only the
positive `sjalq/kernel-authorization-fixture` into that temporary overlay, and
then proves:

1. the authorized package compiles in debug and optimize modes;
2. both generated programs execute and report
   `authorized-sjalq-kernel:elm-core:42`;
3. the `elm-core:42` suffix came through official `elm/core` code, so the
   existing official kernel authorization still works;
4. an `example/*` package importing its own kernel is rejected;
5. an application importing a local kernel is rejected.

Temporary outputs are removed on exit. The fixtures are compiler boundary
evidence only; they are not a private package distribution mechanism.
