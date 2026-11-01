<#
.SYNOPSIS
  Refreshes the toolkit from a machine WITH internet. Downloads the latest T3 Code
  nightly (or a pinned tag), Node, Git, gh, WSL, Ubuntu rootfs, Claude Code for
  Windows and Linux, headless Chrome for Linux, Playwright browsers, and npm
  tarballs. Copies this machine's warmed T3 tool cache. Writes VERSIONS.md.

  Requires: gh (authenticated), curl, npm, npx.

.PARAMETER T3Tag
  Release tag to fetch. Default: newest release in pingdotgg/t3code (nightly).
.PARAMETER ClaudeVersion
  Claude Code version. Default: whatever downloads.claude.ai reports as "latest".
#>
[CmdletBinding()]
param(
  [string]$T3Tag,
  [string]$ClaudeVersion,
  [string]$NodeMajor = '24',
  [switch]$SkipPlaywright
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
foreach ($d in 'windows','linux','wsl','caches\npm','caches\t3-tools-win','caches\t3-tools-linux\chrome-headless-shell\linux64','caches\t3-userdata','caches\playwright-browsers','windows\claude-code','linux\claude-code') {
  New-Item -ItemType Directory -Force -Path (Join-Path $root $d) | Out-Null
}

function Dl($url, $dest) { Write-Host "  $url"; curl.exe -fsSL --retry 3 -o $dest $url; if ($LASTEXITCODE -ne 0) { throw "download failed: $url" } }

# ---- T3 Code ----
if (-not $T3Tag) { $T3Tag = (gh release list -R pingdotgg/t3code --limit 1 --json tagName -q '.[0].tagName') }
Write-Host "== T3 Code $T3Tag"
Get-ChildItem windows -Filter 'T3-Code-*' | Remove-Item -Force
Get-ChildItem windows -Filter 't3-*-win32-*' | Remove-Item -Force
Get-ChildItem linux   -Filter 'T3-Code-*' | Remove-Item -Force
Get-ChildItem linux   -Filter 't3-*-linux-*' | Remove-Item -Force
gh release download $T3Tag -R pingdotgg/t3code -D windows -p 'T3-Code-*-x64.exe' -p 'T3-Code-*-x64.zip' -p 't3-*-win32-x64.zip' -p '*.yml' -p 'SHA256SUMS' --clobber
gh release download $T3Tag -R pingdotgg/t3code -D linux -p 'T3-Code-*-amd64.deb' -p 'T3-Code-*-x86_64.AppImage' -p 't3-*-linux-x64.tar.gz' --clobber

# ---- Node ----
$nodeIndex = (curl.exe -fsSL https://nodejs.org/dist/index.json | ConvertFrom-Json)
$nodeVer = ($nodeIndex | Where-Object { $_.version -like "v$NodeMajor.*" } | Select-Object -First 1).version
Write-Host "== Node $nodeVer"
Get-ChildItem windows,linux -Filter 'node-v*' | Remove-Item -Force
Get-ChildItem windows -Filter 'SHASUMS256-node-*' | Remove-Item -Force
Dl "https://nodejs.org/dist/$nodeVer/node-$nodeVer-x64.msi" "windows\node-$nodeVer-x64.msi"
Dl "https://nodejs.org/dist/$nodeVer/node-$nodeVer-linux-x64.tar.xz" "linux\node-$nodeVer-linux-x64.tar.xz"
Dl "https://nodejs.org/dist/$nodeVer/SHASUMS256.txt" "windows\SHASUMS256-node-$nodeVer.txt"

# ---- Git for Windows ----
$gitTag = gh release view -R git-for-windows/git --json tagName -q .tagName
Write-Host "== Git $gitTag"
Get-ChildItem windows -Filter 'Git-*-64-bit.exe' | Remove-Item -Force
gh release download $gitTag -R git-for-windows/git -D windows -p 'Git-*-64-bit.exe' --clobber

# ---- PowerShell 7 ----
$psTag = gh release view -R PowerShell/PowerShell --json tagName -q .tagName
Write-Host "== PowerShell $psTag"
Get-ChildItem windows -Filter 'PowerShell-*-win-x64.msi' | Remove-Item -Force
gh release download $psTag -R PowerShell/PowerShell -D windows -p '*-win-x64.msi' --clobber

# ---- Python ----
$pyVer = ((curl.exe -fsSL https://www.python.org/ftp/python/) | Select-String -Pattern '3\.14\.\d+' -AllMatches).Matches.Value | Sort-Object { [version]$_ } -Unique | Select-Object -Last 1
Write-Host "== Python $pyVer"
Get-ChildItem windows -Filter 'python-*-amd64.exe' | Remove-Item -Force
Dl "https://www.python.org/ftp/python/$pyVer/python-$pyVer-amd64.exe" "windows\python-$pyVer-amd64.exe"

# ---- gh ----
$ghTag = gh release view -R cli/cli --json tagName -q .tagName
Write-Host "== gh $ghTag"
Get-ChildItem windows,linux -Filter 'gh_*' | Remove-Item -Force
gh release download $ghTag -R cli/cli -D windows -p '*_windows_amd64.msi' --clobber
gh release download $ghTag -R cli/cli -D linux   -p '*_linux_amd64.deb' --clobber

# ---- WSL + Ubuntu ----
$wslTag = gh release view -R microsoft/WSL --json tagName -q .tagName
Write-Host "== WSL $wslTag"
Get-ChildItem wsl -Filter 'wsl.*.msi' | Remove-Item -Force
gh release download $wslTag -R microsoft/WSL -D wsl -p '*x64.msi' --clobber
Write-Host '== Ubuntu noble rootfs'
Dl 'https://cloud-images.ubuntu.com/wsl/releases/noble/current/ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz' 'wsl\ubuntu-noble-wsl-amd64-wsl.rootfs.tar.gz'
Dl 'https://cloud-images.ubuntu.com/wsl/releases/noble/current/SHA256SUMS' 'wsl\ubuntu-noble-SHA256SUMS'

# ---- Claude Code ----
$base = 'https://downloads.claude.ai/claude-code-releases'
if (-not $ClaudeVersion) { $ClaudeVersion = (curl.exe -fsSL "$base/latest").Trim() }
Write-Host "== Claude Code $ClaudeVersion"
Get-ChildItem windows\claude-code,linux\claude-code -Filter 'claude-*' | Remove-Item -Force
Dl "$base/$ClaudeVersion/manifest.json"        "windows\claude-code\manifest.json"
Dl "$base/$ClaudeVersion/win32-x64/claude.exe" "windows\claude-code\claude-$ClaudeVersion-win32-x64.exe"
Dl "$base/$ClaudeVersion/linux-x64/claude"     "linux\claude-code\claude-$ClaudeVersion-linux-x64"
Dl "$base/$ClaudeVersion/linux-x64-musl/claude" "linux\claude-code\claude-$ClaudeVersion-linux-x64-musl"
Dl 'https://claude.ai/install.ps1' 'windows\claude-code\install.ps1'
Dl 'https://claude.ai/install.sh'  'linux\claude-code\install.sh'
Set-Content windows\claude-code\VERSION $ClaudeVersion -NoNewline
Copy-Item windows\claude-code\VERSION linux\claude-code\VERSION -Force

# ---- T3 tool cache from this machine ----
$t3tools = Join-Path $env:USERPROFILE '.t3\tools'
Write-Host "== T3 tool cache from $t3tools"
Remove-Item caches\t3-tools-win\* -Recurse -Force -ErrorAction SilentlyContinue
foreach ($t in 'agent-device','chrome-headless-shell','expo-device-hub') {
  if (Test-Path "$t3tools\$t") { Copy-Item "$t3tools\$t" "caches\t3-tools-win\$t" -Recurse -Force } else { Write-Warning "$t not in local cache; open the matching panel in T3 Code once and re-run" }
}
Copy-Item (Join-Path $env:USERPROFILE '.t3\userdata\model-manifest.json') caches\t3-userdata\ -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $env:USERPROFILE '.t3\userdata\usage-model-rates.json') caches\t3-userdata\ -Force -ErrorAction SilentlyContinue

# Linux headless chrome matching the Windows cache version
$chsVer = (Get-ChildItem "$t3tools\chrome-headless-shell\win64" -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
if ($chsVer) {
  Write-Host "== chrome-headless-shell linux64 $chsVer"
  Get-ChildItem caches\t3-tools-linux\chrome-headless-shell\linux64 | Remove-Item -Force
  Dl "https://storage.googleapis.com/chrome-for-testing-public/$chsVer/linux64/chrome-headless-shell-linux64.zip" "caches\t3-tools-linux\chrome-headless-shell\linux64\chrome-headless-shell-linux64-$chsVer.zip"
}

# ---- npm tarballs ----
Write-Host '== npm tarballs'
Push-Location caches\npm
Get-ChildItem -Filter '*.tgz' | Remove-Item -Force
$adVer  = (Get-ChildItem "$t3tools\agent-device" -Directory | Select-Object -First 1).Name
$edhVer = (Get-ChildItem "$t3tools\expo-device-hub" -Directory | Select-Object -First 1).Name
$pkgs = @('playwright@latest','@playwright/test@latest','@playwright/cli@latest')
if ($adVer)  { $pkgs += "agent-device@$adVer" }
if ($edhVer) { $pkgs += "expo-device-hub@$edhVer" }
npm pack @pkgs | Out-Null
Pop-Location

# ---- Seeded npm cache, skills, docs, wheelhouse ----
Write-Host '== npm cache seed'
Remove-Item caches\npm-cache -Recurse -Force -ErrorAction SilentlyContinue
$seed = Join-Path $env:TEMP 'npmseed'; Remove-Item $seed -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Path $seed | Out-Null
Push-Location $seed; npm init -y | Out-Null
$skillPkgs = @()
if (Test-Path "$root\caches\claude-skills") { $skillPkgs = (Get-ChildItem "$root\caches\claude-skills" -Recurse -Include *.md | Select-String -Pattern 'npm (install|i)( -g)? ([a-zA-Z0-9@/._ -]+)' -AllMatches).Matches | ForEach-Object { $_.Groups[3].Value -split ' ' } | Where-Object { $_ -match '^[a-z@]' } | Sort-Object -Unique }
npm install --cache "$root\caches\npm-cache" --no-audit --no-fund @('playwright@latest','@playwright/test@latest','@playwright/cli@latest',"agent-device@$adVer","expo-device-hub@$edhVer") $skillPkgs | Out-Null
Pop-Location
Write-Host '== Claude Code skills (anthropics/skills)'
Remove-Item caches\claude-skills -Recurse -Force -ErrorAction SilentlyContinue
$sk = Join-Path $env:TEMP 'askills'; Remove-Item $sk -Recurse -Force -ErrorAction SilentlyContinue
git clone -q --depth 1 https://github.com/anthropics/skills.git $sk
New-Item -ItemType Directory -Force -Path caches\claude-skills | Out-Null
Copy-Item "$sk\skills\*" caches\claude-skills -Recurse -Force
Write-Host '== Claude Code docs'
Remove-Item caches\claude-code-docs -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path caches\claude-code-docs | Out-Null
Dl 'https://code.claude.com/docs/llms.txt' 'caches\claude-code-docs\llms.txt'
(Select-String -Path caches\claude-code-docs\llms.txt -Pattern 'https://code\.claude\.com/docs/en/[A-Za-z0-9_/.-]+\.md' -AllMatches).Matches.Value | Sort-Object -Unique | ForEach-Object {
  $rel = $_ -replace '^https://code\.claude\.com/docs/en/', ''
  $dst = Join-Path 'caches\claude-code-docs' $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  curl.exe -fsSL --retry 2 -o $dst $_
}
Write-Host '== T3 Code user docs'
Remove-Item docseference	3code -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path docseference	3code | Out-Null
gh api 'repos/pingdotgg/t3code/git/trees/main?recursive=1' -q '.tree[] | select(.path|startswith("docs/user/")) | select(.type=="blob") | .path' | ForEach-Object {
  gh api "repos/pingdotgg/t3code/contents/$_" -q .content | ForEach-Object { [IO.File]::WriteAllBytes((Join-Path 'docseference	3code' (Split-Path $_ -Leaf)), [Convert]::FromBase64String($_)) }
}
Write-Host '== Python wheelhouse'
Remove-Item caches\pip-wheelhouse\win, caches\pip-wheelhouse\linux -Recurse -Force -ErrorAction SilentlyContinue
py -3 -m pip download --quiet -d caches\pip-wheelhouse\win -r caches\pip-wheelhouse\requirements.txt
py -3 -m pip download --quiet -d caches\pip-wheelhouse\linux -r caches\pip-wheelhouse\requirements.txt --platform manylinux2014_x86_64 --platform manylinux_2_17_x86_64 --platform manylinux_2_28_x86_64 --platform any --python-version 3.12 --only-binary=:all:

# ---- Playwright browsers ----
if (-not $SkipPlaywright) {
  Write-Host '== Playwright browsers'
  $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $root 'caches\playwright-browsers'
  npx -y playwright@latest install chromium chromium-headless-shell | Out-Null
}

# ---- Reconcile tool pins with the downloaded T3 build ----
Write-Host '== Checking tool pins against the T3 bundle'
& (Join-Path $PSScriptRoot 'check-pins.ps1') -Fix

# ---- VERSIONS.md ----
& (Join-Path $PSScriptRoot 'write-versions.ps1')
Write-Host 'Done. If the Claude Code version changed, re-run scripts\bake-wsl.ps1.'
