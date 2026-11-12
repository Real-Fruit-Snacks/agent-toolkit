# Environment variables

Set these as **user** environment variables on the Windows machine before the
first launch of T3 Code. `install-windows.ps1` sets them for you, in your own
user environment (`HKCU\Environment`), so no admin rights are needed. Inside WSL
the baked distro sets the same values in `/etc/profile.d/agent-toolkit.sh`.

## Where the install is

| Variable | Value | Effect |
|---|---|---|
| `AGENT_TOOLKIT_HOME` | the install root, `%LOCALAPPDATA%\Programs\agent-toolkit` unless `-Root` picked another | Where the apps, binaries and caches are; `check-install.ps1` and a re-run of the install scripts read it. |
| `PLAYWRIGHT_BROWSERS_PATH` | `<root>\cache\ms-playwright` | Where the restored browser cache lives, so `playwright install` is never needed. |
| `KILLER_SKILLS_CACHE` | `<root>\cache` | Where killer-design and killer-repo find their runtime and font pack. |

These three are set even with `-SkipEnv`, because the tools can't find the root
without them.

## PATH

`install-windows.ps1` adds these folders in the install root to the front of
your **user** PATH, and only there. Windows puts the machine PATH first, so a
copy of the same tool that IT installed for all users still runs ahead of these
in a new terminal; `check-install.ps1` says when that happens.

| Folder | Holds |
|---|---|
| `<root>\node` | `node`, `npm`, `npx` |
| `<root>\npm` | Global npm packages, such as the language servers |
| `<root>\git\cmd` | `git` (the portable Git for Windows; Git Bash is in `..\bin`) |
| `<root>\gh\bin` | `gh` |
| `<root>\pwsh` | `pwsh` |
| `<root>\python` and its `Scripts` | `python`, `pip` |
| `<root>\bin` | `claude`, and the MCP and language-server binaries |

## T3 Code

| Variable | Value | Effect |
|---|---|---|
| `T3CODE_DISABLE_AUTO_UPDATE` | `1` | Stops the GitHub-based updater from polling or downloading. |
| `T3CODE_TELEMETRY_ENABLED` | `0` | Disables PostHog and Statsig reporting. |
| `T3CODE_OTEL_SDK_DISABLED` | `1` | Disables OpenTelemetry export. |

## Claude Code CLI

| Variable | Value | Effect |
|---|---|---|
| `DISABLE_AUTOUPDATER` | `1` | No version checks or self-update downloads. |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | Turns off telemetry, feature-flag fetches, and changelog/docs fetches. |
| `DISABLE_TELEMETRY` | `1` | Belt and braces for the above. |
| `DISABLE_ERROR_REPORTING` | `1` | No crash uploads. |

Endpoint variables go per-instance in T3 Code (Settings > Providers > Claude >
Environment variables) rather than globally, so different instances can target
different servers. See `claude-provider-env.example`.

## GitHub CLI and PowerShell 7

| Variable | Value | Effect |
|---|---|---|
| `GH_NO_UPDATE_NOTIFIER` | `1` | Stops `gh` checking GitHub for a newer release. |
| `POWERSHELL_UPDATECHECK` | `Off` | Stops `pwsh` checking for a newer release at startup. |
| `POWERSHELL_TELEMETRY_OPTOUT` | `1` | Turns off PowerShell 7's startup telemetry. |

## Playwright

| Variable | Value | Effect |
|---|---|---|
| `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` | `1` | Prevents npm installs of Playwright from attempting a download. |

`PLAYWRIGHT_BROWSERS_PATH` is under "Where the install is", above.

## npm and pip

| Variable | Value | Effect |
|---|---|---|
| `npm_config_cache` | `<root>\cache\npm` | The seeded npm cache the install restored. |
| `npm_config_offline` | `true` | npm installs from that cache and never asks the registry. |
| `PIP_NO_INDEX` | `1` | pip never asks PyPI. |
| `PIP_FIND_LINKS` | `<root>\cache\pip-wheelhouse` | pip installs from the bundled wheels instead, copied into the root so the download can be deleted. |

To install something that isn't in the caches, turn offline mode off for that
window and point npm at an internal registry if one exists; otherwise installs
will hang on the public registry:

```
$env:npm_config_offline = 'false'
npm config set registry https://<internal-registry>/
npm config set fetch-retries 0
```

If there is no internal registry, install packages from the tarballs in
`caches/npm` with `npm install -g <file>.tgz`.
