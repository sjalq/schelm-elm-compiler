# Release checklist

1. Confirm the worktree is clean and `Schelm.Version` matches the planned
   `vVERSION` tag.
2. Review the downstream range from `upstreamCommit` and run gitleaks on that
   range plus the worktree. Two credential-like strings may be reported in
   inherited, already-public Lamdera history. Never copy their values into
   issues, logs, or documentation. New Schelm findings block release.
3. Run public-surface checks, the Haskell suite, and the package integration
   suite. After the repository is public, verify a fresh anonymous HTTPS clone
   with recursive submodules.
4. Create and push the annotated `vVERSION` tag from the reviewed commit. The
   release workflow requires the tagged commit to be on `main`, repeats the
   Haskell and integration suites, and builds every supported platform before
   release creation.
5. Verify `SHA256SUMS`, GitHub artifact attestations, and
   `schelm --version-full`; identify the Elm, Lamdera, and upstream-base versions
   in release notes.

Archives are not claimed to be bit-for-bit reproducible across runner images.
Checksums cover the files CI produced; attestations bind them to the workflow
and source revision.
