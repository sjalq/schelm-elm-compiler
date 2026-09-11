# Schelm Compiler

Schelm is an independent Elm-compatible compiler distribution based on the
[Lamdera compiler](https://github.com/lamdera/compiler). It compiles ordinary
Elm 0.19.1 applications and retains Lamdera workflows for full-stack projects.

Schelm adds Git-native packages and permits packages from any author to contain
kernel JavaScript and effect managers. Applications still cannot contain or
directly import kernel modules. Projects that do not use these extensions keep
the standard `elm.json` format.

Schelm is not an official Elm or Lamdera release and is not endorsed by Evan
Czaplicki, Mario Rogic, the Elm project, or the Lamdera project. The upstream
copyright notices and BSD-3-Clause license are retained in [LICENSE](LICENSE)
and [NOTICE](NOTICE).

## Build

```sh
./scripts/build-schelm.sh
dist/schelm/bin/schelm --version-full
```

The default package cache is isolated under the platform application-data
directory named `schelm`. Set `SCHELM_HOME` to override it. `ELM_HOME` remains
available as an explicit compatibility override.

## Use

```sh
schelm make src/Main.elm
schelm install elm/http
schelm install author/project --from https://example.com/author/project.git
```

See [SCHELM.md](SCHELM.md) for compiler identity, upstream maintenance, and
private release procedures. See
[docs/schelm-packages.md](docs/schelm-packages.md) for Git package resolution
and publication.

## Upstream projects

[Elm](https://elm-lang.org/) is a language for reliable web applications.
[Lamdera](https://lamdera.com/) extends Elm with a type-safe full-stack
platform and supports ordinary Elm frontend projects. Schelm depends on and
credits both projects while remaining separately named and maintained.
