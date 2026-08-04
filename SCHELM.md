# Schelm compiler fork

This branch starts from the official Elm `0.19.2` tag (`48befde1`) and extends
kernel-package authorization to packages owned by the dedicated Schelm package
author, `sjalq`.

The normal Elm safety boundaries remain in force:

- applications cannot contain or directly import kernel modules;
- non-authorized package authors cannot contain kernel modules;
- kernel JavaScript remains behind annotated Elm package APIs;
- public package resolution is not changed by this commit.

Private package distribution is intentionally handled by the Schelm project's
pinned, isolated package overlay. Do not use a stock Elm cache for Schelm builds.

This is an unofficial compiler fork and is not endorsed by the Elm project.
