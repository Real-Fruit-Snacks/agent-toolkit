<#
.SYNOPSIS
  Refreshes the toolkit from a machine WITH internet. Downloads the latest T3 Code
  nightly (or a pinned tag), Node, Git, gh, PowerShell 7, Python, WSL, the Ubuntu
  rootfs, Claude Code for Windows and Linux, the T3 tool caches at the versions
  the T3 build pins, Playwright browsers, a seeded npm cache, the public Claude
  Code skills, offline docs and the Python wheelhouse. Writes VERSIONS.md.

  Runs the same on a workstation or a GitHub Actions windows runner: nothing is
  taken from the local ~/.t3 cache except, when present, the manifest snapshots.

  Requires: gh (authenticated), curl, git, node/npm/npx, python (3.11+) with pip.

.PARAMETER T3Tag          Release tag to fetch. Default: newest release in pingdotgg/t3code (nightly).
.PARAMETER ClaudeVersion  Claude Code version. Default: what downloads.claude.ai reports as "latest".
.PARAMETER NodeMajor      Node major line to pin. Default 24.
.PARAMETER SkipPlaywright Skip the Windows Playwright browser download.
.PARAMETER SkipDistroSources Skip the WSL msi and Ubuntu rootfs (CI builds the distro elsewhere).
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
foreach ($d in 'windows','linux','wsl','caches\npm','caches\t3-tools-win','caches\t3-tools-linux\chrome-headless-shell\linux64','caches\t3-userdata','caches\playwright-browsers','windows\claude-code','linux\claude-code','docs\reference\t3code','caches\claude-skills','caches\claude-code-docs','caches\pip-wheelhouse') {
  New-Item -ItemType Directory -Force -Path (Join-Path $root $d) | Out-Null
}
# prefer the py launcher when present; call the executables by name so the helper can't recurse into itself
# prefer the python on PATH (what actions/setup-python provides); the py launcher may pick a different, pip-less install
# Windows ships a Store stub named python.exe that only prints an error, so pick the first candidate that actually runs.
$pyExe = $null; $pyArgs = @()
foreach ($cand in @(@('python.exe', @()), @('py.exe', @('-3')), @('python3.exe', @()))) {
  if (-not (Get-Command $cand[0] -ErrorAction SilentlyContinue)) { continue }
  $v = & $cand[0] @($cand[1]) --version 2>&1
  if ($LASTEXITCODE -eq 0 -and "$v" -match '^Python 3\.') { $pyExe = $cand[0]; $pyArgs = $cand[1]; break }
}
if (-not $pyExe) { throw 'no working Python 3 on PATH' }
Write-Host "  python: $pyExe $(& $pyExe @pyArgs --version 2>&1)  pip: $(& $pyExe @pyArgs -m pip --version 2>&1)"
function Dl($url, $dest) { Write-Host "  $url"; curl.exe -fsSL --retry 3 -o $dest $url; if ($LASTEXITCODE -ne 0) { throw "download failed: $url" } }

# ---- T3 Code ----
if (-not $T3Tag) { $T3Tag = (gh release list -R pingdotgg/t3code --limit 1 --json tagName -q '.[0].tagName') }
Write-Host "== T3 Code $T3Tag"
Get-ChildItem windows -Filter 'T3-Code-*' | Remove-Item -Force
Get-ChildItem windows -Filter 't3-*-win32-*' | Remove-Item -Force
Get-ChildItem linux   -Filter 'T3-Code-*' | Remove-Item -Force
Get-ChildItem linux   -Filter 't3-*-linux-*' | Remove-Item -Force
Get-ChildItem windows -Filter '*.yml' | Remove-Item -Force
gh release download $T3Tag -R pingdotgg/t3code -D windows -p 'T3-Code-*-x64.exe' -p 'T3-Code-*-x64.zip' -p 't3-*-win32-x64.zip' -p 'nightly.yml' -p 'latest.yml' -p 'SHA256SUMS' --clobber
gh release download $T3Tag -R pingdotgg/t3code -D linux -p 'T3-Code-*-amd64.deb' -p 'T3-Code-*-x86_64.AppImage' -p 't3-*-linux-x64.tar.gz' --clobber

# ---- Tool pins the T3 build expects (headless Chrome, agent-device, expo-device-hub) ----
Write-Host '== Tool pins from the T3 bundle'
& (Join-Path $PSScriptRoot 'check-pins.ps1') -Fix
$adVer  = (Get-ChildItem caches\t3-tools-win\agent-device -Directory | Select-Object -First 1).Name
$edhVer = (Get-ChildItem caches\t3-tools-win\expo-device-hub -Directory | Select-Object -First 1).Name
$chsVer = (Get-ChildItem caches\t3-tools-win\chrome-headless-shell\win64 -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
if (-not ($adVer -and $edhVer -and $chsVer)) { throw "tool pins incomplete: agent-device=$adVer expo-device-hub=$edhVer chrome=$chsVer" }
if (-not (Get-ChildItem caches\t3-tools-linux\chrome-headless-shell\linux64 -Filter "*-$chsVer.zip" -ErrorAction SilentlyContinue)) {
  Get-ChildItem caches\t3-tools-linux\chrome-headless-shell\linux64 -ErrorAction SilentlyContinue | Remove-Item -Force
  Dl "https://storage.googleapis.com/chrome-for-testing-public/$chsVer/linux64/chrome-headless-shell-linux64.zip" "caches\t3-tools-linux\chrome-headless-shell\linux64\chrome-headless-shell-linux64-$chsVer.zip"
}
# manifest snapshots from a local T3 install, if there is one (optional)
foreach ($f in 'model-manifest.json','usage-model-rates.json') {
  $src = Join-Path $env:USERPROFILE ".t3\userdata\$f"
  if (Test-Path $src) { Copy-Item $src caches\t3-userdata\ -Force }
}

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
# newest 3.13.x that actually ships a Windows installer (late security-only releases are source-only)
$pyCandidates = ((curl.exe -fsSL https://www.python.org/ftp/python/) | Select-String -Pattern '3\.13\.\d+' -AllMatches).Matches.Value | Sort-Object { [version]$_ } -Unique -Descending
$pyVer = $null
foreach ($c in $pyCandidates) {
  curl.exe -fsSI -o NUL "https://www.python.org/ftp/python/$c/python-$c-amd64.exe" 2>$null
  if ($LASTEXITCODE -eq 0) { $pyVer = $c; break }
}
if (-not $pyVer) { throw 'no Python 3.13 release with a Windows installer found' }
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
Dl "$base/$ClaudeVersion/manifest.json"         "windows\claude-code\manifest.json"
Dl "$base/$ClaudeVersion/win32-x64/claude.exe"  "windows\claude-code\claude-$ClaudeVersion-win32-x64.exe"
Dl "$base/$ClaudeVersion/linux-x64/claude"      "linux\claude-code\claude-$ClaudeVersion-linux-x64"
Dl "$base/$ClaudeVersion/linux-x64-musl/claude" "linux\claude-code\claude-$ClaudeVersion-linux-x64-musl"
Dl 'https://claude.ai/install.ps1' 'windows\claude-code\install.ps1'
Dl 'https://claude.ai/install.sh'  'linux\claude-code\install.sh'
Set-Content windows\claude-code\VERSION $ClaudeVersion -NoNewline
Copy-Item windows\claude-code\VERSION linux\claude-code\VERSION -Force
# checksums from the vendor manifest
$man = Get-Content windows\claude-code\manifest.json -Raw | ConvertFrom-Json
foreach ($pair in @(@('win32-x64', "windows\claude-code\claude-$ClaudeVersion-win32-x64.exe"), @('linux-x64', "linux\claude-code\claude-$ClaudeVersion-linux-x64"), @('linux-x64-musl', "linux\claude-code\claude-$ClaudeVersion-linux-x64-musl"))) {
  $want = $man.platforms.($pair[0]).checksum
  $got = (Get-FileHash $pair[1] -Algorithm SHA256).Hash.ToLower()
  if ($want -and $got -ne $want) { throw "Claude Code checksum mismatch for $($pair[0])" }
}

# ---- Claude Code skills (anthropics/skills, Apache-2.0) ----
Write-Host '== Claude Code skills'
Remove-Item caches\claude-skills -Recurse -Force -ErrorAction SilentlyContinue
$sk = Join-Path $env:TEMP 'askills'; Remove-Item $sk -Recurse -Force -ErrorAction SilentlyContinue
git clone -q --depth 1 https://github.com/anthropics/skills.git $sk
New-Item -ItemType Directory -Force -Path caches\claude-skills | Out-Null
Copy-Item "$sk\skills\*" caches\claude-skills -Recurse -Force
Get-ChildItem $sk -Filter 'LICENSE*' -File | Copy-Item -Destination caches\claude-skills -Force

# ---- npm tarballs + seeded npm cache ----
Write-Host '== npm tarballs'
Push-Location caches\npm
Get-ChildItem -Filter '*.tgz' | Remove-Item -Force
npm pack @('playwright@latest','@playwright/test@latest','@playwright/cli@latest',"agent-device@$adVer","expo-device-hub@$edhVer") | Out-Null
Pop-Location
Write-Host '== npm cache seed'
Remove-Item caches\npm-cache -Recurse -Force -ErrorAction SilentlyContinue
$seed = Join-Path $env:TEMP 'npmseed'; Remove-Item $seed -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Path $seed | Out-Null
$skillPkgs = (Get-ChildItem caches\claude-skills -Recurse -Include *.md | Select-String -Pattern 'npm (install|i)( -g)?( -D)? ([a-zA-Z0-9@/._ -]+)' -AllMatches).Matches | ForEach-Object { $_.Groups[4].Value -split ' ' } | Where-Object { $_ -match '^[a-z@]' } | Sort-Object -Unique
$mcp = (Get-Content (Join-Path $root 'config\mcp-servers.json') -Raw | ConvertFrom-Json).servers
$mcpNpm = @($mcp | Where-Object kind -eq 'npm' | ForEach-Object { "$($_.package)@latest" })
Write-Host "  MCP npm servers: $($mcpNpm.Count)"
Push-Location $seed
npm init -y | Out-Null
npm install --cache "$root\caches\npm-cache" --no-audit --no-fund @('playwright@latest','@playwright/test@latest','@playwright/cli@latest',"agent-device@$adVer","expo-device-hub@$edhVer") @skillPkgs @mcpNpm | Out-Null
Pop-Location
Set-Content caches\npm-cache\SKILL-PACKAGES.txt ($skillPkgs -join ' ')

# ---- Claude Code docs ----
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

# ---- T3 Code user docs (MIT) ----
Write-Host '== T3 Code user docs'
$t3docs = Join-Path $root 'docs\reference\t3code'
Get-ChildItem $t3docs -File -ErrorAction SilentlyContinue | Remove-Item -Force
gh api 'repos/pingdotgg/t3code/git/trees/main?recursive=1' -q '.tree[] | select(.path|startswith("docs/user/")) | select(.type=="blob") | .path' | ForEach-Object {
  $leaf = Split-Path $_ -Leaf
  $b64 = gh api "repos/pingdotgg/t3code/contents/$_" -q .content
  [IO.File]::WriteAllBytes((Join-Path $t3docs $leaf), [Convert]::FromBase64String(($b64 -join '')))
}

# ---- Python wheelhouse ----
Write-Host '== Python wheelhouse'
Remove-Item caches\pip-wheelhouse\win, caches\pip-wheelhouse\linux -Recurse -Force -ErrorAction SilentlyContinue
& $pyExe @pyArgs -m pip download --disable-pip-version-check --progress-bar off -d 'caches/pip-wheelhouse/win' -r 'caches/pip-wheelhouse/requirements.txt' --python-version 3.13 --platform win_amd64 --platform any --only-binary=:all:
if ($LASTEXITCODE -ne 0) { throw 'pip download (win) failed' }
& $pyExe @pyArgs -m pip download --disable-pip-version-check --progress-bar off -d 'caches/pip-wheelhouse/linux' -r 'caches/pip-wheelhouse/requirements.txt' --platform manylinux2014_x86_64 --platform manylinux_2_17_x86_64 --platform manylinux_2_28_x86_64 --platform any --python-version 3.12 --only-binary=:all:
if ($LASTEXITCODE -ne 0) { throw 'pip download (linux) failed' }

foreach ($side in 'win','linux') {
  $n = (Get-ChildItem "caches\pip-wheelhouse\$side" -File -ErrorAction SilentlyContinue | Measure-Object).Count
  if ($n -lt 10) { throw "wheelhouse $side has only $n files; is caches\pip-wheelhouse\requirements.txt present?" }
  Write-Host "  $side wheels: $n"
}

# ---- Python MCP servers wheelhouse (best effort: a package without a wheel for this Python is skipped, not fatal) ----
Write-Host '== Python MCP servers wheelhouse'
foreach ($side in @(@('win', @('--python-version','3.13','--platform','win_amd64','--platform','any')), @('linux', @('--platform','manylinux2014_x86_64','--platform','manylinux_2_17_x86_64','--platform','manylinux_2_28_x86_64','--platform','any','--python-version','3.12')))) {
  foreach ($pkg in (Get-Content 'caches\pip-wheelhouseequirements-mcp.txt' | Where-Object { $_ -and $_ -notmatch '^\s*#' })) {
    & $pyExe @pyArgs -m pip download --disable-pip-version-check --progress-bar off --only-binary=:all: -d "caches/pip-wheelhouse/$($side[0])" $pkg @($side[1]) 2>&1 | Select-String -Pattern 'ERROR' | ForEach-Object { Write-Warning "  $($side[0]) $pkg : no wheel ($_)" }
  }
}

# ---- GitHub MCP server binaries ----
$ghmTag = gh release view -R github/github-mcp-server --json tagName -q .tagName
Write-Host "== github-mcp-server $ghmTag"
foreach ($side in 'win','linux') { New-Item -ItemType Directory -Force -Path "caches\mcp-bin\$side" | Out-Null; Get-ChildItem "caches\mcp-bin\$side" | Remove-Item -Force }
gh release download $ghmTag -R github/github-mcp-server -D caches\mcp-bin\win   -p 'github-mcp-server_Windows_x86_64.zip' --clobber
gh release download $ghmTag -R github/github-mcp-server -D caches\mcp-bin\linux -p 'github-mcp-server_Linux_x86_64.tar.gz' --clobber

# ---- Playwright browsers (Windows) ----
if (-not $SkipPlaywright) {
  Write-Host '== Playwright browsers'
  Remove-Item caches\playwright-browsers -Recurse -Force -ErrorAction SilentlyContinue
  $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $root 'caches\playwright-browsers'
  npx -y playwright@latest install chromium chromium-headless-shell | Out-Null
}

# ---- VERSIONS.md ----
& (Join-Path $PSScriptRoot 'write-versions.ps1')
Write-Host 'Done. Build the distro next: scripts\bake-wsl.ps1 (WSL) or scripts\build-distro-chroot.sh (Linux/CI).'
