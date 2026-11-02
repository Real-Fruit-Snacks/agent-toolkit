# agent-toolkit

Pinned installers and config for my coding setup

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/cover-dark.svg">
  <img alt="agent-toolkit: a terminal running the Windows install script" src="docs/assets/cover-light.svg" width="100%">
</picture>

Download the release assets, verify and restore the folder layout, then install:

```powershell
.\scripts\download-release.ps1 -To C:\toolkit-assets   # or download the assets by hand
.\scripts\unpack-release.ps1 -From C:\toolkit-assets
.\scripts\install-windows.ps1
```

This installs T3 Code, the Claude Code CLI, Node, Git, the GitHub CLI, PowerShell 7, and Python, restores the caches those tools would otherwise fetch on first use, seeds a working config, and sets the environment variables that turn off their updaters and telemetry. It pins one tested version of every piece, so two machines built from the same release are identical. The binaries live on the GitHub release as separate assets, since GitHub caps each one at 2 GB; a `repo--*.zip` asset carries the repo itself for machines without a clone. The repo holds the scripts, config, and a manifest of what is pinned.

## What's in it

| Command | Does |
|---|---|
| `scripts/install-windows.ps1` | Installs the apps, restores caches, sets environment variables |
| `scripts/setup-wsl.ps1` | Installs the WSL platform and imports the baked Ubuntu distro |
| `scripts/install-linux.sh` | Installs on a standalone Debian or Ubuntu machine |
| `scripts/collect.ps1` | Rebuilds the assets from a connected machine and reconciles versions |
| `scripts/check-pins.ps1` | Checks the tool cache against the versions the T3 build expects |
| `scripts/bake-wsl.ps1` | Provisions and exports the Ubuntu distro as one importable tarball |
| `scripts/package-release.ps1` | Bundles the folders into release assets and prints the publish command |
| `scripts/download-release.ps1` | Fetches every asset of a release into one folder, with or without the GitHub CLI |
| `scripts/unpack-release.ps1` | Verifies downloaded assets against SHA256SUMS.txt and restores the folder layout |
| `scripts/verify-release.ps1` | Checks a published release's asset digests against its own SHA256SUMS.txt |

Also in the release, restored by the install scripts:

- The public Claude Code skills set (docx, pdf, pptx, xlsx, and others), with a Python wheelhouse for their dependencies
- A seeded npm cache so `playwright`, `agent-device`, `expo-device-hub`, and the packages the skills call for install with `--offline`
- Claude Code documentation as markdown, and the T3 Code user docs under `docs/reference/t3code`
- Linux copies of the T3 tool cache and Playwright browsers for standalone Linux installs

## Tested on

- Windows 11 Pro 26300 · Windows PowerShell 5.1 · the bake, collect, and pin checks run here
- Ubuntu 24.04 noble under WSL 2 · the distro is baked and its contents verified here
- *Not* tested: a full install from release assets on a second machine, end to end

## Known issues

- The app installers run with silent flags that are correct for the pinned versions; a newer installer may change them.
- Restoring Playwright browsers into WSL relies on the baked distro. Importing the raw Ubuntu rootfs instead needs a network to fetch them.
- T3 Code pins its on-demand tool versions per build. After bumping T3, run `scripts/check-pins.ps1 -Fix` or the cache will be ignored and a download attempted.

## Configuration

The install script seeds T3 Code settings, keybindings, and a Claude Code config that skips first-run onboarding, but only where those files do not already exist. Templates are in `config/`. Endpoint settings for the Claude Code provider go per instance in T3 Code, under Settings, Providers, Claude, in the Environment variables list. Templates for an Anthropic-compatible gateway, Bedrock, and Vertex are in `config/claude-provider-env.example`. The environment variables that disable updaters and telemetry are listed in `config/env-vars.md` and set by the install script.

## License

MIT, for the scripts and config in this repo. The installers, runtime binaries, and distro image distributed as release assets keep their own licenses.
