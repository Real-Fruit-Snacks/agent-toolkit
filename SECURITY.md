# Security

## Supported versions

The latest release only. A new one is built every Sunday from `main`; older releases get no fixes.

## Reporting

Please don't put the details of a vulnerability in a public issue. Open an issue that says you have a security report, without the details, and I'll reply with a private way to send it.

Useful to include: the release tag, the script and the platform, and what it did that it shouldn't.

## Checking what you downloaded

The release assets aren't signed. What the scripts do check:

- `unpack-release.ps1` compares every downloaded file with `SHA256SUMS.txt` before it restores anything and stops on a mismatch. Files that were cut into parts are joined and checked against their own `.sha256`.
- `verify-release.ps1 -Tag vX` compares the SHA-256 digest GitHub recorded for each upload with the release's `SHA256SUMS.txt`. The weekly build runs it on the draft and publishes only if every digest matches.
- `download-release.ps1`, without the GitHub CLI, checks each file against GitHub's digest after downloading it, and keeps a file it already has only if the hash matches.

That proves the files are the ones the build uploaded, not that an upstream installer is what its vendor meant to ship. The Claude Code binaries are checked against Anthropic's release manifest when they're collected. For Node.js, Ubuntu and T3 Code, their own checksum files ship next to the installers (`windows/SHASUMS256-node-*.txt`, `wsl/ubuntu-noble-SHA256SUMS`, `windows/SHA256SUMS`) so you can check them yourself.

## What the install changes

`install-windows.ps1` runs the bundled installers silently, copies caches into your profile, and sets user environment variables that turn off the T3 Code and Claude Code updaters and telemetry and point npm, pip and Playwright at the local caches ([config/env-vars.md](config/env-vars.md)). It seeds config files only where none exist, and the Claude Code seed carries no account data. Endpoint settings and keys are yours to add.

## Out of scope

The bundled tools themselves. Report those to their projects: [T3 Code](https://github.com/pingdotgg/t3code), [Claude Code](https://github.com/anthropics/claude-code), and the vendors of the MCP servers and plugins listed in [VERSIONS.md](VERSIONS.md).
