<#
.SYNOPSIS
  Installs the bundled MCP servers on Windows from the offline caches and
  registers the default ones in Claude Code's user config. Called by
  install-windows.ps1; safe to re-run. Everything goes under the install root
  (AGENT_TOOLKIT_HOME, %LOCALAPPDATA%\Programs\agent-toolkit by default):
    npm servers  -> <root>\npm, npm install -g --offline from <root>\cache\npm
    pip servers  -> <root>\venv-mcp\<id> from caches\pip-wheelhouse\win
    bin servers  -> <root>\bin from caches\mcp-bin\win
  Default servers are added to ~\.claude.json (or CLAUDE_CONFIG_DIR\.claude.json)
  only if a server with that id is not already registered. Every server, default
  or not, is written to ~\agent-toolkit-docs\mcp-servers.md with a 'claude mcp add'
  line, so the rest are one command away.
#>
[CmdletBinding()]
param([switch]$RegisterAll)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$root   = Split-Path -Parent $PSScriptRoot
$caches = Join-Path $root 'caches'
$home_  = $env:USERPROFILE
$tk     = Get-ToolkitRoot
$manifest = Get-Content (Join-Path $root 'config\mcp-servers.json') -Raw | ConvertFrom-Json
$servers = $manifest.servers

function Expand-Vars($s) { "$s" -replace '\$\{HOME\}', ($home_ -replace '\\', '/') -replace '\$\{CWD\}', '.' }

# ---- npm ----
$npm = Find-Npm
$npmCache = Join-Path $tk 'cache\npm'
$npmPkgs = $servers | Where-Object kind -eq 'npm' | Where-Object { -not $_.platforms -or (@($_.platforms) -contains 'win') } | ForEach-Object package
$installed = @{}
if ($npm -and (Test-Path $npmCache)) {
  Write-Host "== npm MCP servers ($($npmPkgs.Count))"
  foreach ($pkg in $npmPkgs) {   # one at a time, so one package that can't resolve offline doesn't block the rest
    $out = Invoke-Native { & $npm install -g --offline --cache "$npmCache" --no-audit --no-fund $pkg }
    if ($LASTEXITCODE -ne 0) { Write-Warning "  npm install failed for $pkg : $(@($out | Select-String -Pattern 'npm error' | Select-Object -First 2) -join ' ')" }
  }
  $gRoot = "$(@(Invoke-Native { & $npm root -g }) | Select-Object -Last 1)".Trim()
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
$venv = Join-Path $tk 'venv-mcp'
$py = Find-Python   # the wheelhouse is built for Python 3.13: that one, not just the newest
function OnThisPlatform($s) { -not $s.platforms -or (@($s.platforms) -contains 'win') }
if ($py -and (Test-Path $wheels)) {
  # one venv per server: these tools pin conflicting versions of shared dependencies
  Write-Host "== Python MCP servers -> $venv\<id>"
  New-Item -ItemType Directory -Force -Path $venv | Out-Null
  foreach ($s in ($servers | Where-Object kind -eq 'pip' | Where-Object { OnThisPlatform $_ })) {
    $sv = Join-Path $venv $s.id
    $exe = Join-Path $sv "Scripts\$($s.bin).exe"
    if (-not (Test-Path $exe)) {
      if (-not (Test-Path (Join-Path $sv 'Scripts\python.exe'))) { $null = Invoke-Native { & $py -m venv $sv } }
      $null = Invoke-Native { & (Join-Path $sv 'Scripts\python.exe') -m pip install --quiet --disable-pip-version-check --no-index --find-links "$wheels" $s.package }
    }
    if (Test-Path $exe) { $installed[$s.id] = @{ command = $exe; args = @($s.args | ForEach-Object { Expand-Vars $_ }) }; Write-Host "  ok  $($s.id)" }
    else { Write-Warning "  missing: $($s.id) ($($s.package) has no wheel for this Python in the wheelhouse)"; Remove-Item $sv -Recurse -Force -ErrorAction SilentlyContinue }
  }
} else { Write-Warning 'Python 3.13 or the wheelhouse is missing; skipping pip MCP servers' }

# ---- bin ----
$binDir = Join-Path $caches 'mcp-bin\win'
$localBin = Join-Path $tk 'bin'
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
Write-Utf8 $cj ($cfg | ConvertTo-Json -Depth 10)
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
Write-Utf8 (Join-Path $docs 'mcp-servers.md') (($lines -join "`n") + "`n")
Write-Host "== catalog: $docs\mcp-servers.md"
