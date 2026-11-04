<#
.SYNOPSIS
  Installs the bundled MCP servers on Windows from the offline caches and
  registers the default ones in Claude Code's user config. Called by
  install-windows.ps1; safe to re-run.
    npm servers  -> npm install -g --offline from caches\npm-cache
    pip servers  -> ~\.venv-mcp from caches\pip-wheelhouse\win
    bin servers  -> ~\.local\bin from caches\mcp-bin\win
  Default servers are added to ~\.claude.json (or CLAUDE_CONFIG_DIR\.claude.json)
  only if a server with that id is not already registered. Every server, default
  or not, is written to ~\agent-toolkit-docs\mcp-servers.md with a 'claude mcp add'
  line, so the rest are one command away.
#>
[CmdletBinding()]
param([switch]$RegisterAll)
$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $PSScriptRoot
$caches = Join-Path $root 'caches'
$home_  = $env:USERPROFILE
$manifest = Get-Content (Join-Path $root 'config\mcp-servers.json') -Raw | ConvertFrom-Json
$servers = $manifest.servers

function Expand-Vars($s) { "$s" -replace '\$\{HOME\}', ($home_ -replace '\\', '/') -replace '\$\{CWD\}', '.' }

# ---- npm ----
$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $npm) { $npm = Get-Command (Join-Path $env:ProgramFiles 'nodejs\npm.cmd') -ErrorAction SilentlyContinue }
$npmCache = Join-Path $home_ '.npm-toolkit-cache'
$npmPkgs = $servers | Where-Object kind -eq 'npm' | Where-Object { -not $_.platforms -or (@($_.platforms) -contains 'win') } | ForEach-Object package
$installed = @{}
if ($npm -and (Test-Path $npmCache)) {
  Write-Host "== npm MCP servers ($($npmPkgs.Count))"
  & $npm.Source install -g --offline --cache "$npmCache" --no-audit --no-fund @npmPkgs 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Warning 'some npm MCP servers failed to install from the cache' }
  $gRoot = (& $npm.Source root -g).Trim()
  foreach ($s in ($servers | Where-Object kind -eq 'npm')) {
    $pj = Join-Path (Join-Path $gRoot $s.package) 'package.json'
    if (-not (Test-Path $pj)) { Write-Warning "  missing: $($s.package)"; continue }
    $bin = (Get-Content $pj -Raw | ConvertFrom-Json).bin
    $rel = if ($bin -is [string]) { $bin } else { $bin.($s.bin) }
    if (-not $rel) { $rel = ($bin.PSObject.Properties | Select-Object -First 1).Value }
    $installed[$s.id] = @{ command = 'node'; args = @((Join-Path (Join-Path $gRoot $s.package) $rel)) + @($s.args | ForEach-Object { Expand-Vars $_ }) }
    Write-Host "  ok  $($s.id)"
  }
} else { Write-Warning 'npm or the seeded npm cache is missing; skipping npm MCP servers' }

# ---- pip ----
$wheels = Join-Path $caches 'pip-wheelhouse\win'
$reqMcp = Join-Path $caches 'pip-wheelhouse\requirements-mcp.txt'
$venv = Join-Path $home_ '.venv-mcp'
$py = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
if (-not $py) {  # fall back to a python on PATH that actually runs (Windows ships a Store stub named python.exe)
  foreach ($c in 'python.exe','python3.exe') { $g = Get-Command $c -ErrorAction SilentlyContinue; if ($g) { $v = & $g.Source --version 2>&1; if ($LASTEXITCODE -eq 0 -and "$v" -match '^Python 3') { $py = Get-Item $g.Source; break } } }
}
function OnThisPlatform($s) { -not $s.platforms -or (@($s.platforms) -contains 'win') }
if ($py -and (Test-Path $wheels)) {
  # one venv per server: these tools pin conflicting versions of shared dependencies
  Write-Host '== Python MCP servers -> ~\.venv-mcp\<id>'
  New-Item -ItemType Directory -Force -Path $venv | Out-Null
  foreach ($s in ($servers | Where-Object kind -eq 'pip' | Where-Object { OnThisPlatform $_ })) {
    $sv = Join-Path $venv $s.id
    $exe = Join-Path $sv "Scripts\$($s.bin).exe"
    if (-not (Test-Path $exe)) {
      if (-not (Test-Path (Join-Path $sv 'Scripts\python.exe'))) { & $py.FullName -m venv $sv }
      & (Join-Path $sv 'Scripts\python.exe') -m pip install --quiet --disable-pip-version-check --no-index --find-links "$wheels" $s.package 2>$null
    }
    if (Test-Path $exe) { $installed[$s.id] = @{ command = $exe; args = @($s.args | ForEach-Object { Expand-Vars $_ }) }; Write-Host "  ok  $($s.id)" }
    else { Write-Warning "  missing: $($s.id) ($($s.package) has no wheel for this Python in the wheelhouse)"; Remove-Item $sv -Recurse -Force -ErrorAction SilentlyContinue }
  }
} else { Write-Warning 'Python or the wheelhouse is missing; skipping pip MCP servers' }

# ---- bin ----
$binDir = Join-Path $caches 'mcp-bin\win'
$localBin = Join-Path $home_ '.local\bin'
New-Item -ItemType Directory -Force -Path $localBin | Out-Null
foreach ($s in ($servers | Where-Object kind -eq 'bin' | Where-Object { OnThisPlatform $_ })) {
  $zip = Get-Item (Join-Path $binDir $s.asset_win) -ErrorAction SilentlyContinue
  if (-not $zip) { Write-Warning "  missing archive for $($s.id)"; continue }
  $tmp = Join-Path $env:TEMP "mcpbin-$($s.id)"; Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
  Expand-Archive $zip.FullName -DestinationPath $tmp -Force
  $exe = Get-ChildItem $tmp -Recurse -Filter "$($s.bin).exe" | Select-Object -First 1
  Copy-Item $exe.FullName (Join-Path $localBin "$($s.bin).exe") -Force
  $installed[$s.id] = @{ command = (Join-Path $localBin "$($s.bin).exe"); args = @($s.args) }
  Write-Host "  ok  $($s.id)"
}

# ---- register defaults in Claude Code user config ----
$cfgDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $home_ '.claude' }
$cj = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $cfgDir '.claude.json' } else { Join-Path $home_ '.claude.json' }
$cfg = if (Test-Path $cj) { Get-Content $cj -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $cfg.PSObject.Properties['mcpServers']) { $cfg | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([pscustomobject]@{}) }
$added = 0
foreach ($s in $servers) {
  if (-not $installed.ContainsKey($s.id)) { continue }
  if (-not ($s.default -or $RegisterAll)) { continue }
  if ($cfg.mcpServers.PSObject.Properties[$s.id]) { continue }
  $entry = [ordered]@{ type = 'stdio'; command = $installed[$s.id].command; args = @($installed[$s.id].args) }
  if ($s.env) { $e = [ordered]@{}; foreach ($p in $s.env.PSObject.Properties) { $e[$p.Name] = Expand-Vars $p.Value }; $entry.env = $e }
  $cfg.mcpServers | Add-Member -NotePropertyName $s.id -NotePropertyValue ([pscustomobject]$entry)
  $added++
}
New-Item -ItemType Directory -Force -Path (Split-Path $cj) | Out-Null
$cfg | ConvertTo-Json -Depth 10 | Set-Content $cj -Encoding utf8
Write-Host "== registered $added default MCP server(s) in $cj"

# ---- catalog with add-commands for the rest ----
$docs = Join-Path $home_ 'agent-toolkit-docs'; New-Item -ItemType Directory -Force -Path $docs | Out-Null
$lines = @('# Bundled MCP servers', '', 'Installed by the toolkit. Default ones are already in your Claude Code user config. Add any other with the line shown, filling in placeholders.', '')
foreach ($s in $servers) {
  if (-not $installed.ContainsKey($s.id)) { continue }
  $i = $installed[$s.id]
  $envFlags = if ($s.env) { ($s.env.PSObject.Properties | ForEach-Object { "-e $($_.Name)=`"$(Expand-Vars $_.Value)`"" }) -join ' ' } else { '' }
  $cmdLine = "claude mcp add -s user $envFlags $($s.id) -- `"$($i.command)`" " + (($i.args | ForEach-Object { "`"$_`"" }) -join ' ')
  $lines += "## $($s.id)" + $(if ($s.default) { ' (registered by default)' } else { '' })
  $lines += ''; $lines += $s.note; $lines += ''; $lines += '```'; $lines += ($cmdLine -replace '\s+', ' '); $lines += '```'; $lines += ''
}
Set-Content (Join-Path $docs 'mcp-servers.md') ($lines -join "`n") -Encoding utf8
Write-Host "== catalog: $docs\mcp-servers.md"
