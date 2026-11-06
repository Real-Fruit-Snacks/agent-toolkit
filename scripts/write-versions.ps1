<#
.SYNOPSIS
  Regenerates VERSIONS.md from whatever is currently in windows/, linux/, wsl/, caches/.
  Versions are read from file names; hashes are computed.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function First($dir, $filter) { Get-ChildItem $dir -Filter $filter -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
function Ver($file, $regex) { if ($file -and $file.Name -match $regex) { $Matches[1] } else { '' } }
function Row($label, $file, $regex) {
  if (-not $file) { return $null }
  $h = (Get-FileHash $file.FullName -Algorithm SHA256).Hash.ToLower()
  $mb = [math]::Round($file.Length / 1MB)
  "| $label | $(Ver $file $regex) | ``$($file.Name)`` | $mb | ``$h`` |"
}

$t3exe = First windows 'T3-Code-*-x64.exe'
$lines = @(
  '# Pinned versions', '',
  "Generated $(Get-Date -Format 'yyyy-MM-dd') by scripts/write-versions.ps1.", '',
  '| Component | Version | File | MB | SHA256 |', '|---|---|---|---|---|'
)
$rows = @(
  (Row 'T3 Code (Windows installer)' $t3exe 'T3-Code-(.+)-x64\.exe'),
  (Row 'T3 Code (Windows portable)'  (First windows 'T3-Code-*-x64.zip') 'T3-Code-(.+)-x64\.zip'),
  (Row 'T3 server/CLI (win32)'       (First windows 't3-*-win32-x64.zip') 't3-(.+)-win32-x64\.zip'),
  (Row 'T3 Code (deb)'               (First linux 'T3-Code-*-amd64.deb') 'T3-Code-(.+)-amd64\.deb'),
  (Row 'T3 Code (AppImage)'          (First linux 'T3-Code-*-x86_64.AppImage') 'T3-Code-(.+)-x86_64\.AppImage'),
  (Row 'T3 server/CLI (linux)'       (First linux 't3-*-linux-x64.tar.gz') 't3-(.+)-linux-x64\.tar\.gz'),
  (Row 'Claude Code (Windows)'       (First windows\claude-code 'claude-*-win32-x64.exe') 'claude-(.+)-win32-x64\.exe'),
  (Row 'Claude Code (Linux glibc)'   (First linux\claude-code 'claude-*-linux-x64') 'claude-(.+)-linux-x64$'),
  (Row 'Claude Code (Linux musl)'    (First linux\claude-code 'claude-*-linux-x64-musl') 'claude-(.+)-linux-x64-musl'),
  (Row 'Node.js (msi)'               (First windows 'node-v*-x64.msi') 'node-(v[0-9.]+)-x64\.msi'),
  (Row 'Node.js (linux)'             (First linux 'node-v*-linux-x64.tar.xz') 'node-(v[0-9.]+)-linux-x64'),
  (Row 'PowerShell 7 (msi)'          (First windows 'PowerShell-*-win-x64.msi') 'PowerShell-([0-9.]+)-win'),
  (Row 'Python (Windows)'            (First windows 'python-*-amd64.exe') 'python-([0-9.]+)-amd64'),
  (Row 'Git for Windows'             (First windows 'Git-*-64-bit.exe') 'Git-([0-9.]+)-64-bit'),
  (Row 'GitHub CLI (msi)'            (First windows 'gh_*_windows_amd64.msi') 'gh_([0-9.]+)_windows'),
  (Row 'GitHub CLI (deb)'            (First linux 'gh_*_linux_amd64.deb') 'gh_([0-9.]+)_linux'),
  (Row 'WSL platform'                (First wsl 'wsl.*.x64.msi') 'wsl\.([0-9.]+)\.x64'),
  (Row 'Ubuntu WSL rootfs'           (First wsl 'ubuntu-*-wsl-amd64-*.rootfs.tar.gz') 'ubuntu-([a-z]+)-wsl'),
  (Row 'Baked distro export'         (First wsl 'ubuntu-dev.tar.gz') '(ubuntu-dev)'),
  (Row 'github-mcp-server (win)'      (First caches\mcp-bin\win 'github-mcp-server_Windows_x86_64.zip') '(github-mcp-server)'),
  (Row 'mcp-grafana (win)'            (First caches\mcp-bin\win 'mcp-grafana_Windows_x86_64.zip') '(mcp-grafana)'),
  (Row 'rust-analyzer (win)'          (First caches\lsp-bin\win 'rust-analyzer-x86_64-pc-windows-msvc.zip') '(rust-analyzer)'),
  (Row 'chrome-headless-shell (linux)' (First caches\t3-tools-linux\chrome-headless-shell\linux64 '*.zip') 'linux64-([0-9.]+)\.zip')
) | Where-Object { $_ }
$lines += $rows

$lines += ''; $lines += '## T3 tool cache (caches/t3-tools-win)'; $lines += ''
foreach ($t in Get-ChildItem caches\t3-tools-win -Directory -ErrorAction SilentlyContinue) {
  $v = (Get-ChildItem $t.FullName -Recurse -Directory | Where-Object { $_.Name -match '^\d' } | Select-Object -First 1).Name
  $lines += "- $($t.Name) $v"
}
$lines += ''; $lines += '## Playwright browsers (caches/playwright-browsers)'; $lines += ''
foreach ($d in Get-ChildItem caches\playwright-browsers -Directory -ErrorAction SilentlyContinue) { $lines += "- $($d.Name)" }
$lines += ''; $lines += '## Also in the release'; $lines += ''
$lines += '- caches/npm-cache: seeded npm cache for offline installs of playwright, agent-device, expo-device-hub and the skill packages'
$lines += '- caches/claude-skills: the public anthropics/skills set (Apache-2.0), t3dotgg/tstack (MIT) and Real-Fruit-Snacks/killer-skills (MIT)'
$ksVer = Get-Content (Join-Path $root 'caches\killer-skills\VERSION') -Raw -ErrorAction SilentlyContinue
if ($ksVer) { $lines += "- caches/killer-skills: killer-skills $($ksVer.Trim())'s runtime (Playwright, Chromium and Mermaid, for Windows) and font pack, for killer-design and killer-repo" }
$lines += '- caches/claude-code-docs: Claude Code documentation, markdown, from code.claude.com/docs/llms.txt'
$lines += '- caches/pip-wheelhouse: Python wheels for the document skills and the Python MCP servers (win + linux)'
$lines += '- MCP servers (config/mcp-servers.json): npm ones in the npm cache, Python ones in the wheelhouse, github-mcp-server binaries in caches/mcp-bin'
$lines += '- caches/playwright-browsers-linux and caches/t3-tools-linux: Linux browser and tool caches taken from the baked distro'
$lines += '- docs/reference/t3code: T3 Code user docs (MIT), in the repo'

$idxPath = Join-Path $root 'caches\claude-plugins\index.json'
if (Test-Path $idxPath) {
  $idx = (Get-Content $idxPath -Raw | ConvertFrom-Json).marketplaces
  $lines += ''; $lines += '## Claude Code plugin marketplaces (caches/claude-plugins)'; $lines += ''
  $lines += '| Marketplace | Upstream | Commit | Plugins | Enabled by default |'; $lines += '|---|---|---|---|---|'
  foreach ($m in $idx) { $lines += "| ``$($m.name)`` | $($m.repo) | ``$("$($m.commit)".Substring(0,7))`` | $(@($m.plugins).Count) | $(if (@($m.enable).Count) { (@($m.enable) -join ', ') } else { '-' }) |" }
}
$mcpCfg = Join-Path $root 'config\mcp-servers.json'
if (Test-Path $mcpCfg) {
  $srv = (Get-Content $mcpCfg -Raw | ConvertFrom-Json).servers
  $lines += ''; $lines += "## MCP servers ($(@($srv).Count))"; $lines += ''
  foreach ($k in 'npm','pip','bin') {
    $ids = @($srv | Where-Object kind -eq $k | ForEach-Object { if ($_.default) { "**$($_.id)**" } else { $_.id } })
    if ($ids.Count) { $lines += "- $k`: $($ids -join ', ')" }
  }
  $lines += '- bold = registered in Claude Code by default'
}
$lines += ''; $lines += '## npm tarballs (caches/npm)'; $lines += ''
foreach ($f in Get-ChildItem caches\npm -Filter '*.tgz' -ErrorAction SilentlyContinue) { $lines += "- $($f.Name)" }

[System.IO.File]::WriteAllText((Join-Path $root 'VERSIONS.md'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
Write-Host "Wrote VERSIONS.md ($($rows.Count) artifacts)"
