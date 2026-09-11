# Schelm Git packages

Schelm projects remain ordinary Elm projects. Package names, versions, constraints,
and dependency groups stay in `elm.json`. A project only needs `schelm.json` when a
package comes from somewhere other than the Elm package registry.

Install a package from any Git remote with:

```sh
schelm install author/project --from https://example.com/author/project.git
```

The command discovers bare semantic version tags such as `1.2.3`, runs the normal
Elm constraint solver, and checks that the selected tag contains a package whose
`name` and `version` match the requested package and tag. It records the resolved
commit and a hash of the package inputs in `schelm.json`. Commit both JSON files.

The generated file has this shape:

```json
{
  "format": 1,
  "sources": {
    "author/project": "https://example.com/author/project.git"
  },
  "resolved": {
    "author/project": {
      "source": "https://example.com/author/project.git",
      "version": "1.2.3",
      "commit": "0123456789abcdef",
      "sha256": "0123456789abcdef"
    }
  }
}
```

`sources` is authored configuration. `resolved` is generated. Dependencies can
carry their own `schelm.json` to route their direct dependencies. Resolution fails
when two paths route the same Elm package name to different origins.

Publishing is Git-native. Keep the package as a valid Elm package, update its
`version`, commit the release, create a bare tag with that exact version, and push
the commit and tag to its Git remote:

```sh
git tag 1.2.3
git push origin HEAD 1.2.3
```

The tag is the published release. There is no required Schelm registry or upload.
Moving a published tag is rejected for projects that already resolved it, including
on a fresh machine, because the commit and content hash no longer match.

Package projects may include `src/Elm/Kernel/*.js` and effect manager modules.
Applications remain unable to include kernel code. Custom infix declarations stay
restricted to the official core package authors.

Packages without `schelm.json` remain publishable and compilable with Elm 0.19.1.
Elm registry packages and Git packages share the same solver, cache layout, build,
and import behavior.
