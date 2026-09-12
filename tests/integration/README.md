# Schelm integration tests

`run.sh` creates all Git remotes and projects under a temporary directory. It
tests the released CLI rather than importing compiler internals. Network access
is used only for the official Elm registry packages needed to compile a normal
Elm 0.19.1 application and to obtain the upstream `elm/time` fixture. Every Git
package under test is served from a local bare repository.

Run after building Schelm:

```sh
SCHELM_BIN="$PWD/dist/schelm/bin/schelm" ELM_BIN=elm ./tests/integration/run.sh
```

`ELM_BIN` is required for the official-compiler compatibility assertions.
