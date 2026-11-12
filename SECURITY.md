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

That proves the files are the ones the build uploaded, not that an upstream installer is what its vendor meant to ship. When they're collected, the Claude Code binaries are checked against Anthropic's release manifest, the Node.js zip against Node's `SHASUMS256.txt`, and Python's NuGet package against the SHA-512 nuget.org records for it. For Node.js, Ubuntu and T3 Code, their own checksum files ship next to the installers (`windows/SHASUMS256-node-*.txt`, `wsl/ubuntu-noble-SHA256SUMS`, `windows/SHA256SUMS`) so you can check them yourself.

## What the install changes

`install-windows.ps1` needs no admin rights and asks for none, and it changes nothing outside the account that runs it:

- It unpacks Node.js, the portable Git for Windows, the GitHub CLI, PowerShell 7 and Python into the install root (`%LOCALAPPDATA%\Programs\agent-toolkit`, or the folder `-Root` names), copies the Claude Code CLI, the MCP servers, the plugin marketplaces and the caches there too, and runs T3 Code's own installer in per-user mode.
- It adds the root's folders to your user PATH (`HKCU\Environment`).
- It sets user environment variables that record the root, turn off the T3 Code, Claude Code, GitHub CLI and PowerShell updaters and telemetry, and point npm, pip and Playwright at the root's caches ([config/env-vars.md](config/env-vars.md)).
- It copies T3 Code's tool cache into `~\.t3`, and skills and plugins into `~\.claude`, where those tools look for them.
- It seeds config files only where none exist, and the Claude Code seed carries no account data. Endpoint settings and keys are yours to add.

If you run it elevated, it warns you and still installs only into the elevated account. `setup-wsl.ps1` is the one script that does anything machine-wide, and only when run elevated on a machine without WSL: it then enables the WSL features and installs WSL from the bundled MSI.

## Out of scope

The bundled tools themselves. Report those to their projects: [T3 Code](https://github.com/pingdotgg/t3code), [Claude Code](https://github.com/anthropics/claude-code), and the vendors of the MCP servers and plugins listed in [VERSIONS.md](VERSIONS.md).
