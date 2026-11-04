<#
.SYNOPSIS
  Installs the toolkit on a Windows machine that fetches nothing at run time.
  Run from an elevated PowerShell in the repo root after unpack-release.ps1.

.PARAMETER SkipApps    Skip the installers (Node, Git, gh, PowerShell 7, Python, T3 Code, Claude Code).
.PARAMETER SkipCaches  Skip restoring caches, npm packages, skills, docs.
.PARAMETER SkipConfig  Skip seeding T3 Code and Claude Code config files.
.PARAMETER SkipEnv     Skip setting user environment variables.
#>
[CmdletBinding()]
param(
  [switch]$SkipApps,
  [switch]$SkipCaches,
  [switch]$SkipConfig,
  [switch]$SkipEnv
)
$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $PSScriptRoot
$win    = Join-Path $root 'windows'
$caches = Join-Path $root 'caches'
$config = Join-Path $root 'config'
$home_  = $env:USERPROFILE

function Pick($dir, $pattern) {
  $f = Get-ChildItem -Path $dir -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { throw "Missing $pattern in $dir" }
  return $f.FullName
}
function Msi($path, $extra) { Start-Process msiexec.exe -Wait -ArgumentList (@('/i', "`"$path`"", '/qn', '/norestart') + $extra) }

if (-not $SkipApps) {
  Write-Host '== Installing Node.js'
  Msi (Pick $win 'node-v*-x64.msi') @()

  Write-Host '== Installing Git for Windows'
  Start-Process (Pick $win 'Git-*-64-bit.exe') -Wait -ArgumentList @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh')

  Write-Host '== Installing GitHub CLI'
  Msi (Pick $win 'gh_*_windows_amd64.msi') @()

  Write-Host '== Installing PowerShell 7'
  Msi (Pick $win 'PowerShell-*-win-x64.msi') @('ADD_PATH=1', 'REGISTER_MANIFEST=1', 'ENABLE_PSREMOTING=0')

  Write-Host '== Installing Python (per-user, on PATH)'
  Start-Process (Pick $win 'python-*-amd64.exe') -Wait -ArgumentList @('/quiet', 'InstallAllUsers=0', 'PrependPath=1', 'Include_launcher=1', 'Include_test=0')

  Write-Host '== Installing T3 Code (per-user, silent)'
  Start-Process (Pick $win 'T3-Code-*-x64.exe') -Wait -ArgumentList @('/S', '/currentuser')

  Write-Host '== Installing Claude Code CLI'
  $claudeDir = Join-Path $home_ '.local\bin'
  New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
  Copy-Item (Pick (Join-Path $win 'claude-code') 'claude-*-win32-x64.exe') (Join-Path $claudeDir 'claude.exe') -Force
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($userPath -notlike "*$claudeDir*") { [Environment]::SetEnvironmentVariable('Path', "$claudeDir;$userPath", 'User') }
}

if (-not $SkipCaches) {
  Write-Host '== Restoring T3 tool cache'
  $t3tools = Join-Path $home_ '.t3\tools'
  New-Item -ItemType Directory -Force -Path $t3tools | Out-Null
  Copy-Item (Join-Path $caches 't3-tools-win\*') $t3tools -Recurse -Force

  Write-Host '== Restoring T3 manifest snapshots'
  $t3user = Join-Path $home_ '.t3\userdata'
  New-Item -ItemType Directory -Force -Path $t3user | Out-Null
  Copy-Item (Join-Path $caches 't3-userdata\*') $t3user -Force

  Write-Host '== Restoring Playwright browsers'
  $pw = Join-Path $home_ '.cache\ms-playwright'
  New-Item -ItemType Directory -Force -Path $pw | Out-Null
  Copy-Item (Join-Path $caches 'playwright-browsers\*') $pw -Recurse -Force

  Write-Host '== Installing npm packages from the seeded cache'
  $npmCache = Join-Path $home_ '.npm-toolkit-cache'
  if (Test-Path (Join-Path $caches 'npm-cache')) {
    New-Item -ItemType Directory -Force -Path $npmCache | Out-Null
    Copy-Item (Join-Path $caches 'npm-cache\*') $npmCache -Recurse -Force
    $npm = Join-Path $env:ProgramFiles 'nodejs\npm.cmd'
    if (Test-Path $npm) {
      foreach ($pkg in 'playwright', '@playwright/cli', 'agent-device', 'expo-device-hub') {
        & $npm install -g --offline --cache "$npmCache" --no-audit --no-fund $pkg 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning "global npm install of $pkg from the cache failed; T3 still works from its own tool cache" }
      }
    }
  }

  Write-Host '== Installing Claude Code skills'
  if (Test-Path (Join-Path $caches 'claude-skills')) {
    $skills = Join-Path $home_ '.claude\skills'
    New-Item -ItemType Directory -Force -Path $skills | Out-Null
    Get-ChildItem (Join-Path $caches 'claude-skills') -Directory | ForEach-Object { Copy-Item $_.FullName (Join-Path $skills $_.Name) -Recurse -Force }
  }

  Write-Host '== Installing Python packages for the document skills'
  $wheels = Join-Path $caches 'pip-wheelhouse\win'
  if (Test-Path $wheels) {
    $req = Join-Path $caches 'pip-wheelhouse\requirements.txt'
    $py = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $py) { foreach ($c in 'python.exe','python3.exe') { $g = Get-Command $c -ErrorAction SilentlyContinue; if ($g) { $v = & $g.Source --version 2>&1; if ($LASTEXITCODE -eq 0 -and "$v" -match '^Python 3') { $py = Get-Item $g.Source; break } } } }
    if ($py) { & $py.FullName -m pip install --quiet --no-index --find-links "$wheels" -r $req; if ($LASTEXITCODE -ne 0) { Write-Warning 'pip install from wheelhouse had errors' } }
    else { Write-Warning 'python.exe not found; open a new terminal and run: pip install --no-index --find-links caches\pip-wheelhouse\win -r caches\pip-wheelhouse\requirements.txt' }
  }

  Write-Host '== MCP servers'
  & (Join-Path $PSScriptRoot 'install-mcp.ps1')

  Write-Host '== Claude Code plugin marketplaces and language servers'
  $claudeExe = Join-Path $home_ '.local\bin\claude.exe'
  $pyP = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
  if (-not $pyP) { foreach ($c in 'python.exe','python3.exe') { $g = Get-Command $c -ErrorAction SilentlyContinue; if ($g) { $v = & $g.Source --version 2>&1; if ($LASTEXITCODE -eq 0 -and "$v" -match '^Python 3') { $pyP = Get-Item $g.Source; break } } } }
  if ($pyP -and (Test-Path $claudeExe) -and (Test-Path (Join-Path $caches 'claude-plugins\index.json'))) {
    & $pyP.FullName (Join-Path $PSScriptRoot 'install-plugins.py') --repo $root --claude $claudeExe
    if ($LASTEXITCODE -ne 0) { Write-Warning 'plugin install reported problems; re-run: python scripts\install-plugins.py' }
  } else { Write-Warning 'skipping plugins: needs Python, the Claude Code CLI, and caches\claude-plugins' }

  Write-Host '== Placing offline docs'
  $docs = Join-Path $home_ 'agent-toolkit-docs'
  New-Item -ItemType Directory -Force -Path $docs | Out-Null
  if (Test-Path (Join-Path $caches 'claude-code-docs')) { Copy-Item (Join-Path $caches 'claude-code-docs') (Join-Path $docs 'claude-code') -Recurse -Force }
  if (Test-Path (Join-Path $root 'docs\reference\t3code')) { Copy-Item (Join-Path $root 'docs\reference\t3code') (Join-Path $docs 't3code') -Recurse -Force }
}

if (-not $SkipConfig) {
  Write-Host '== Seeding T3 Code settings (only files that do not exist yet)'
  $t3user = Join-Path $home_ '.t3\userdata'
  New-Item -ItemType Directory -Force -Path $t3user | Out-Null
  foreach ($f in 'settings.json', 'client-settings.json', 'keybindings.json') {
    $dst = Join-Path $t3user $f
    if (-not (Test-Path $dst)) { Copy-Item (Join-Path $config "t3-userdata\$f") $dst }
  }

  Write-Host '== Seeding Claude Code config (skips onboarding; no account data)'
  # Merge, don't skip: the MCP and plugin steps may already have created these files,
  # so add each seed key that is missing and leave existing values alone.
  function Merge-Seed($path, $seedFile) {
    $seed = Get-Content $seedFile -Raw | ConvertFrom-Json
    $cur = if (Test-Path $path) { Get-Content $path -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
    foreach ($p in $seed.PSObject.Properties) {
      if ($p.Name -eq '$comment') { continue }
      if (-not $cur.PSObject.Properties[$p.Name]) { $cur | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value }
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    $cur | ConvertTo-Json -Depth 20 | Set-Content $path -Encoding utf8
  }
  $cfgDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $home_ '.claude' }
  $cj = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $cfgDir '.claude.json' } else { Join-Path $home_ '.claude.json' }
  Merge-Seed $cj (Join-Path $config 'claude-home\claude.json.example')
  Merge-Seed (Join-Path $cfgDir 'settings.json') (Join-Path $config 'claude-home\settings.json.example')
}

if (-not $SkipEnv) {
  Write-Host '== Setting user environment variables'
  $vars = @{
    T3CODE_DISABLE_AUTO_UPDATE               = '1'
    T3CODE_TELEMETRY_ENABLED                 = '0'
    T3CODE_OTEL_SDK_DISABLED                 = '1'
    DISABLE_AUTOUPDATER                      = '1'
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
    DISABLE_TELEMETRY                        = '1'
    DISABLE_ERROR_REPORTING                  = '1'
    PLAYWRIGHT_BROWSERS_PATH                 = (Join-Path $home_ '.cache\ms-playwright')
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD         = '1'
    npm_config_cache                         = (Join-Path $home_ '.npm-toolkit-cache')
    npm_config_offline                       = 'true'
    PIP_NO_INDEX                             = '1'
    PIP_FIND_LINKS                           = (Join-Path $caches 'pip-wheelhouse\win')
  }
  foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $vars[$k], 'User') }
}

Write-Host ''
Write-Host 'Done. Open a NEW terminal, then launch T3 Code.'
Write-Host 'In Settings > Providers > Claude set Binary path to:'
Write-Host "  $home_\.local\bin\claude.exe"
Write-Host 'and add the endpoint variables from config\claude-provider-env.example.'
Write-Host "Offline docs: $home_\agent-toolkit-docs"
