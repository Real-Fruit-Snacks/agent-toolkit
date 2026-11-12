# agent-toolkit

T3 Code, the Claude Code CLI and the tools around them on a Windows machine where you aren't an administrator. One GitHub release, rebuilt every Sunday, installs all of it into your own account from its own files: no UAC prompt, no admin password, and nothing downloaded while it runs.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/plan-dark.svg">
  <img alt="The latest release drawn to scale, one column per asset under a dashed line at 2 GiB. The WSL distro grows through the line as one column, is cut into parts that drop into their own slots, then every column top turns green as the digests are checked and the readout says the release is consistent" src="docs/assets/plan-light.svg" width="100%">
</picture>

The latest release, one column per file, to scale. GitHub won't take a file of 2 GiB or more, so the WSL distro ships cut into parts, and every digest is checked before the release is published. The [project page](https://real-fruit-snacks.github.io/agent-toolkit/) reads out each file.

## Install, without admin rights

Open PowerShell the normal way, not with "Run as administrator". Windows PowerShell 5.1, which every Windows 10 and 11 machine has, is enough. From a clone of this repo, or from the `repo--agent-toolkit-*.zip` on the [latest release](https://github.com/Real-Fruit-Snacks/agent-toolkit/releases/latest) extracted anywhere you can write to:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\download-release.ps1
.\scripts\unpack-release.ps1 -From .\assets
.\scripts\install-windows.ps1
```

- The first line lets this one window run the scripts, which Windows blocks by default. It changes nothing for other windows and needs no admin rights.
- `download-release.ps1` fetches what a Windows install uses, about 4 GB, into an `assets` folder there, after checking the drive has room. It goes through the GitHub CLI if that's installed, and plain HTTPS through your system proxy if not. `-Include wsl` adds the WSL distro, `-All` everything.
- `unpack-release.ps1` checks each file against `SHA256SUMS.txt`, joins the distro's parts if you fetched them, and puts everything back into `windows\`, `linux\`, `wsl\` and `caches\`. `-Move` moves rather than copies, for a small disk. The release's project page lands in `page\`, to read offline.
- `install-windows.ps1` installs the apps into one folder in your account and puts them on your own PATH, restores the caches those tools would otherwise fetch on first run, installs the MCP servers, plugins and skills offline, seeds config where none exists, and sets the user variables that turn off their updaters and telemetry.

Open a new terminal afterwards. `.\scripts\check-install.ps1` then checks the whole install from there: each app runs at the pinned version, the MCP servers, plugins and skills are in place, and it says what kind of machine and profile it sees. Nothing points back at the downloaded release by then, so you can delete it.

### Where it all goes

Nothing is written outside your own account, and everything heavy goes in one folder, the install root: `%LOCALAPPDATA%\Programs\agent-toolkit`, or wherever `install-windows.ps1 -Root` puts it.

| What | Where |
|---|---|
| Node.js, Git for Windows (the portable build), the GitHub CLI, PowerShell 7, Python 3.13 (python.org's NuGet build) | `node`, `git`, `gh`, `pwsh` and `python` in the root |
| The Claude Code CLI, and the MCP and language-server binaries | `bin` in the root |
| Global npm packages; the Python MCP servers, one virtual environment each; the vendored plugin marketplaces | `npm`, `venv-mcp` and `plugins` in the root |
| Caches: npm's, Playwright's browsers, killer-skills' packs, the Python wheels | `cache` in the root |
| T3 Code | `%LOCALAPPDATA%\Programs\t3code`, from its own per-user installer; its data and tool cache in `~\.t3`, where T3 keeps them |
| Skills, plugins and Claude Code's config | `~\.claude` and `~\.claude.json` |
| PATH entries, `AGENT_TOOLKIT_HOME` and the variables in [config/env-vars.md](config/env-vars.md) | your user environment, `HKCU\Environment` |

Removing it needs no admin rights either: uninstall T3 Code from Settings, Apps, delete the install root, and take its entries out of your user PATH. If you run the install elevated anyway, it warns you and installs into the elevated account's profile, which is the wrong one if you elevated with someone else's account.

### On a VDI desktop

Citrix, VMware Horizon, Azure Virtual Desktop and Windows 365 desktops are the machines this is most often for, and it's built around what they're like:

- **Small disks.** The default download is the Windows part only, about 4 GB of the 10, with the free space checked first. `unpack-release.ps1 -Move` stops the release taking the space twice, and once the install is done you can delete it.
- **Roaming profiles** copy everything in the profile except `AppData\Local` at every logon and logoff. The install root sits in `AppData\Local`, so the gigabytes stay out of that copy. What's left in the profile is T3 Code's and Claude Code's own folders, and `check-install.ps1` reports their size. Every weekly build fails if they pass 1 GB.
- **Desktops reset at logoff** keep only the profile. FSLogix profile containers keep all of it, `AppData\Local` included, so the default root works. Classic roaming profiles, and some Citrix Profile Management setups, don't keep `AppData\Local`. There, install with `-Root` on a drive that persists between sessions (ask IT which), for example `.\scripts\install-windows.ps1 -Root D:\agent-toolkit`. `check-install.ps1` says which kind of profile it sees.
- **Multi-session hosts** are fine: each person installs into their own account, and each T3 Code takes the next free port from 3773.
- **`AppData\Roaming` redirected to a network share** doesn't matter: the install keeps nothing there.
- **Proxies:** `download-release.ps1` uses the system proxy with your Windows sign-in, as a browser would.
- **WSL 2** needs virtualization that most VDI hosts don't pass through to the desktop. `setup-wsl.ps1` says so when WSL can't start. The Windows install doesn't need WSL.

### WSL and Linux

`.\scripts\setup-wsl.ps1` imports `ubuntu-dev`, a distro with Git, Node, the GitHub CLI and the Claude Code CLI already inside, into your account. With WSL already on the machine, that needs no admin rights. Turning WSL on in the first place needs an administrator once, so without WSL the script stops and says so; from an elevated PowerShell it installs WSL from the bundled MSI. For a standalone Debian or Ubuntu machine, where you do need root: `sudo bash scripts/install-linux.sh`.

### What the install printed
<!-- gen:log -->
What `install-windows.ps1` printed in the v1.0.2 build's smoke test. That build ran it as the runner's administrator, `runneradmin`, with the app installers and the environment skipped (`-SkipApps -SkipEnv`). From the next build on, this is the whole install run as a new account with no admin rights.

```text
== Restoring T3 tool cache
== Restoring T3 manifest snapshots
== Restoring Playwright browsers
== Installing npm packages from the seeded cache
WARNING: global npm install of agent-device from the cache failed; T3 still works from its own tool cache
WARNING: global npm install of expo-device-hub from the cache failed; T3 still works from its own tool cache
== Installing Claude Code skills
== Installing Python packages for the document skills
== MCP servers
== npm MCP servers (19)
  ok  playwright
  ok  chrome-devtools
  ok  filesystem
  (16 more, all ok)
== Python MCP servers -> ~\.venv-mcp\<id>
  ok  git
  ok  fetch
  (15 more, all ok)
== registered 6 default MCP server(s) in C:\Users\runneradmin\.claude.json
== catalog: C:\Users\runneradmin\agent-toolkit-docs\mcp-servers.md
== Claude Code plugin marketplaces and language servers
== Claude Code plugins
  marketplace atk-core-plugins             ok
  marketplace atk-knowledge-work           ok
  (5 more marketplaces and 12 plugins, all ok)
== Language servers for the LSP plugins
  lsp npm     pyright: ok
  lsp npm     typescript-language-server: ok
  lsp npm     typescript: ok
  lsp bin     rust-analyzer: C:\Users\runneradmin\.local\bin\rust-analyzer.exe
  verified    12/12 plugins enabled and loading
== Placing offline docs
== Seeding T3 Code settings (only files that do not exist yet)
== Seeding Claude Code config (skips onboarding; no account data)

Done. Open a NEW terminal, then launch T3 Code.
In Settings > Providers > Claude set Binary path to:
  C:\Users\runneradmin\.local\bin\claude.exe
and add the endpoint variables from config\claude-provider-env.example.
Offline docs: C:\Users\runneradmin\agent-toolkit-docs
```
<!-- /gen:log -->
## What a release holds

Every file and its SHA-256 is in [VERSIONS.md](VERSIONS.md), written by the build that published it. Besides the apps and their caches:

- **Plugins.** Seven Claude Code plugin marketplaces, vendored so they install and load offline: Anthropic's official plugins and knowledge-work plugins, obra/superpowers, wshobson/agents, VoltAgent's subagents, Trail of Bits' security skills, and Anthropic's financial-services plugins. That is 239 plugins of skills, commands, agents, hooks and LSP configs. Twelve are enabled: superpowers, feature-dev, code-review, pr-review-toolkit, commit-commands, code-simplifier, claude-md-management, security-guidance, engineering, and the Python, TypeScript and Rust language servers. Browse and enable the rest with `/plugin`.
- **Language servers** for those LSP plugins: pyright, typescript-language-server and rust-analyzer.
- **Skills,** in `~/.claude/skills`: the public Anthropic skills set (docx, pdf, pptx, xlsx and others) with a Python wheelhouse for their dependencies; t3dotgg/tstack (full-send, full-stop, council, sol-loop, file-pr, takeover, babysit-pr, modernize, leaving-pr-comments), which drive pull requests through the bundled `gh`; and my [killer-skills](https://github.com/Real-Fruit-Snacks/killer-skills): killer-design, killer-repo and killer-council, from killer-skills' latest release. That release's runtime (Playwright, Chromium and Mermaid) and its font pack go into the install root's `cache` folder on Windows (the font pack goes into WSL and Linux too), so killer-design and killer-repo screenshot and set type without the network. Those three skills have their own releases if you want them without the rest of this kit.
- **MCP servers,** 36 of them, listed in [config/mcp-servers.json](config/mcp-servers.json). From npm: Playwright, Chrome DevTools, filesystem, memory, sequential thinking, Desktop Commander, DBHub (Postgres, MySQL, SQL Server, SQLite), MongoDB, Kubernetes, GitLab, Azure DevOps, Sentry, JetBrains, Nx, code runner, PDF, Task Master, mcp-remote and the MCP Inspector. From PyPI: Git, Fetch, Time, MarkItDown, Atlassian, Serena, Redis, DuckDB, Word, PowerPoint, Excel, Jupyter, Prometheus, Docker and Semgrep. As binaries: the official GitHub and Grafana servers. Six are registered by default; every one is listed with its `claude mcp add` line in `~/agent-toolkit-docs/mcp-servers.md`.
- A seeded npm cache, so all of the above and the packages the skills call for install with `--offline`.
- The Claude Code documentation as markdown, and the T3 Code user docs under [docs/reference/t3code](docs/reference/t3code).
- Linux copies of the T3 tool cache and the Playwright browsers, for standalone Linux installs.
- `page--agent-toolkit-<tag>.zip`: the project page as published with that release, to read offline. It's uploaded once the release is published, so it isn't in `SHA256SUMS.txt`; `verify-release.ps1` checks it against the digest GitHub records.

The Windows apps ship in the forms that install without admin rights: zips of Node, the GitHub CLI and PowerShell 7, the portable Git for Windows, Python's NuGet build, and T3 Code's own installer, which installs per user. A release is built from `main` as it stood that Sunday, so a change merged since then ships in the next one.

## How a release is built

[weekly-release.yml](.github/workflows/weekly-release.yml) runs every Sunday at 08:00 UTC, or by hand from the Actions tab with a pinned T3 tag or Claude Code version, and with publishing off to leave a draft for review.

1. **collect**, on a Windows runner: `collect.ps1` downloads the newest T3 nightly, Claude Code, the Windows apps, the plugin marketplaces, the MCP servers and every cache. The Node zip is checked against Node's `SHASUMS256.txt` and the Python package against the hash nuget.org records.
2. **distro**, on an Ubuntu runner: builds the Linux wheelhouse natively and the provisioned Ubuntu image in a chroot with `build-distro-chroot.sh`, then opens the image and checks the MCP servers, plugins, skills and binaries inside it.
3. **publish**, on a Windows runner: runs the T3 and Claude Code binaries and `check-pins.ps1`. Then it creates a new local account with no admin rights and, as that account, in Windows PowerShell 5.1, runs the whole `install-windows.ps1`, apps included, followed by `check-install.ps1 -StandardUser -MaxProfileMB 1024`, which also fails if more than 1 GB lands where a roaming profile would copy it. Next it writes `VERSIONS.md`, packs the assets and cuts any of 1900 MiB or more into parts, uploads them to a draft, and has `verify-release.ps1` compare every digest GitHub recorded with `SHA256SUMS.txt`. Only then does it publish, redraw the plan above, the log and the project page from the published release, and attach that page to the release as a zip.

| Script | Does |
|---|---|
| `scripts/install-windows.ps1` | Installs the apps and caches into your account and sets your user environment, with no admin rights |
| `scripts/check-install.ps1` | Checks an install from your account, as a new terminal sees it |
| `scripts/setup-wsl.ps1` | Imports the baked Ubuntu distro for your account; installs WSL first only when run elevated |
| `scripts/install-linux.sh` | Installs on a standalone Debian or Ubuntu machine |
| `scripts/download-release.ps1` | Fetches a release's Windows assets (or `-All`) into one folder, with or without the GitHub CLI, after checking for disk space |
| `scripts/unpack-release.ps1` | Verifies downloaded assets against `SHA256SUMS.txt` and restores the folder layout; `-Move` for a small disk |
| `scripts/verify-release.ps1` | Checks a published release's asset digests against its own `SHA256SUMS.txt` |
| `scripts/collect.ps1` | Rebuilds the assets from a connected machine and reconciles versions |
| `scripts/check-pins.ps1` | Checks the tool cache against the versions the T3 build expects |
| `scripts/bake-wsl.ps1` | Provisions and exports the Ubuntu distro as one importable tarball |
| `scripts/package-release.ps1` | Bundles the folders into release assets and prints the publish command |
| `scripts/write-versions.ps1` | Writes `VERSIONS.md` from what is in the folders |
| `scripts/write-page.py` | Writes the release facts and the smoke test's log on the project page and in this README |

## Tested on

- A clean GitHub Actions Windows runner, as a standard user: every weekly build installs as a new account with no admin rights, in Windows PowerShell 5.1, and checks the apps, MCP servers, plugins, language servers and skills from that account before it publishes.
- Windows 11 Pro 26300 with Windows PowerShell 5.1: the bake, collect and pin checks run here.
- Ubuntu 24.04 noble under WSL 2: the distro is baked and its contents checked here.
- *Not* tested: a full install from the release assets on a second physical machine, end to end, or on a managed machine with AppLocker or WDAC rules.

## Known issues

- If Group Policy sets PowerShell's execution policy, `Set-ExecutionPolicy -Scope Process` can't override it, and the scripts won't run. Ask IT to allow them.
- On a machine where AppLocker, WDAC or another allow-list stops programs from running out of your profile, the per-user apps won't start. Nothing here works around that, on purpose.
- The scripts need PowerShell's full language mode, which a WDAC policy can take away.
- Windows puts the machine PATH before the user PATH, so if IT has already installed Node, Git, the GitHub CLI, PowerShell 7 or Python for all users, a new terminal runs those copies first. `check-install.ps1` says when it does.
- Turning WSL on needs an administrator, once per machine. Importing the distro after that doesn't. WSL 2 also needs virtualization, which most VDI desktops don't have.
- On a desktop that doesn't keep `AppData\Local` between sessions, the default install root is gone at the next sign-in; install with `-Root` on a drive that persists.
- *Not* tested on a real VDI desktop yet: the weekly build checks what it can on a plain runner (a standard user, the profile footprint), not Citrix, Horizon or FSLogix themselves.
- GitHub takes release assets under 2 GiB, so larger ones, currently the provisioned WSL distro, ship as `.part1`, `.part2` and so on, plus a `.sha256`. `unpack-release.ps1` joins and checks them. On Linux without PowerShell: `cat name.part1 name.part2 name.part3 > name`, then `sha256sum -c name.sha256`.
- T3 Code's installer runs with silent flags that are right for the pinned build; a newer one may change them.
- Restoring the Playwright browsers into WSL relies on the baked distro. Importing the raw Ubuntu rootfs instead needs a network to fetch them.
- Cloud-backed MCP servers (Context7, Brave, Firecrawl, Supabase, Notion, Slack and the like) are left out on purpose; they need the vendor's service.
- Vendored plugins keep their skills, commands, agents and hooks, but their remote MCP connectors are turned off, for the same reason. Each marketplace's `VENDORED.md` lists exactly what changed. Plugins that only pointed at another repository are dropped.
- Three Anthropic marketplaces are renamed with an `atk-` prefix, because Claude Code reserves their upstream names for copies loaded from GitHub.
- The Docker MCP server is Windows-only; its dependencies don't resolve on Ubuntu's Python 3.12.
- T3 Code pins its on-demand tool versions per build. After bumping T3, run `scripts/check-pins.ps1 -Fix`, or the cache is ignored and a download attempted.

## Configuration

The install script seeds T3 Code settings, keybindings and a Claude Code config that skips first-run onboarding, only where those files don't exist yet. The templates are in [config/](config). The Claude Code provider's endpoint is set per instance in T3 Code, under Settings, Providers, Claude, in the Environment variables list; templates for an Anthropic-compatible gateway, Bedrock and Vertex are in `config/claude-provider-env.example`. The variables that turn off updaters and telemetry, and the PATH entries the install adds, are listed in [config/env-vars.md](config/env-vars.md).

The plan at the top is drawn by `docs/art/make-plan.py` from `docs/release.json`, and the log above is written into this README by `scripts/write-page.py` from the same file; CI redraws both and fails if the committed files differ. How the page and the plan are designed is in [docs/DESIGN.md](docs/DESIGN.md).

## License

MIT, for the scripts and config in this repo. The installers, runtime binaries and distro image on the releases keep their own licenses.
