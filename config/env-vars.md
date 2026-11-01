# Environment variables

Set these as **user** environment variables on the Windows machine before the
first launch of T3 Code. `install-windows.ps1` sets them for you. Inside WSL the
baked distro sets the same values in `/etc/profile.d/agent-toolkit.sh`.

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

## Playwright

| Variable | Value | Effect |
|---|---|---|
| `PLAYWRIGHT_BROWSERS_PATH` | `%USERPROFILE%\.cache\ms-playwright` | Where the restored browser cache lives, so `playwright install` is never needed. |
| `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` | `1` | Prevents npm installs of Playwright from attempting a download. |

## npm

Point npm at an internal registry if one exists, otherwise installs will hang on
the public registry:

```
npm config set registry https://<internal-registry>/
npm config set fetch-retries 0
```

If there is no internal registry, install packages from the tarballs in
`caches/npm` with `npm install -g <file>.tgz`.
