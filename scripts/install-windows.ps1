<#
.SYNOPSIS
  Installs the toolkit on a Windows machine with no internet access.
  Run from an elevated PowerShell in the repo root after the release assets
  have been placed in windows\ and caches\.

.PARAMETER SkipApps
  Skip the MSI/EXE installers (Node, Git, gh, T3 Code) and only restore caches and env.
#>
[CmdletBinding()]
param(
  [switch]$SkipApps,
  [switch]$SkipCaches,
  [switch]$SkipEnv
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$win  = Join-Path $root 'windows'
$caches = Join-Path $root 'caches'
$home_ = $env:USERPROFILE

function Pick($dir, $pattern) {
  $f = Get-ChildItem -Path $dir -Filter $pattern -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { throw "Missing $pattern in $dir" }
  return $f.FullName
}

if (-not $SkipApps) {
  Write-Host '== Installing Node.js'
  Start-Process msiexec.exe -Wait -ArgumentList @('/i', "`"$(Pick $win 'node-v*-x64.msi')`"", '/qn', '/norestart')

  Write-Host '== Installing Git for Windows'
  Start-Process (Pick $win 'Git-*-64-bit.exe') -Wait -ArgumentList @('/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh')

  Write-Host '== Installing GitHub CLI'
  Start-Process msiexec.exe -Wait -ArgumentList @('/i', "`"$(Pick $win 'gh_*_windows_amd64.msi')`"", '/qn', '/norestart')

  Write-Host '== Installing T3 Code (per-user, silent)'
  Start-Process (Pick $win 'T3-Code-*-x64.exe') -Wait -ArgumentList @('/S', '/currentuser')

  Write-Host '== Installing Claude Code CLI'
  $claudeDir = Join-Path $home_ '.local\bin'
  New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
  $src = Pick (Join-Path $win 'claude-code') 'claude-*-win32-x64.exe'
  Copy-Item $src (Join-Path $claudeDir 'claude.exe') -Force
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if ($userPath -notlike "*$claudeDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$claudeDir;$userPath", 'User')
  }
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

  Write-Host '== Installing npm tarballs globally'
  $npm = Join-Path $env:ProgramFiles 'nodejs\npm.cmd'
  if (Test-Path $npm) {
    Get-ChildItem (Join-Path $caches 'npm') -Filter '*.tgz' | ForEach-Object {
      & $npm install -g --no-audit --no-fund --offline $_.FullName 2>$null
      if ($LASTEXITCODE -ne 0) { Write-Warning "npm install failed for $($_.Name); install manually later" }
    }
  }
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
  }
  foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $vars[$k], 'User') }
}

Write-Host ''
Write-Host 'Done. Open a NEW terminal, then launch T3 Code.'
Write-Host 'In Settings > Providers > Claude set Binary path to:'
Write-Host "  $home_\.local\bin\claude.exe"
Write-Host 'and add the endpoint variables from config\claude-provider-env.example.'
