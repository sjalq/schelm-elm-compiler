# Contributing to Schelm

Use this repository's issues for Schelm bugs and proposals; do not route Schelm
support or patches to the Elm or Lamdera maintainers.

Before opening a change, build with `./scripts/build-schelm.sh`, run
`stack test elm:lamdera-tests`, and run the package integration suite documented
in `tests/integration/README.md`. Preserve ordinary Elm 0.19.1 compatibility
unless a change is explicitly confined to a Schelm extension. Explain the
security impact of new dependencies or changes to Git package trust boundaries.

Contributions are licensed under the repository's BSD-3-Clause license and
attributed to Schelm contributors. Keep upstream attribution intact.
