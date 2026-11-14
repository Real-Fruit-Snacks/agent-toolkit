<#
.SYNOPSIS
  Checks an install from the side of the account that ran install-windows.ps1, as a terminal
  opened now would see it: every app runs from the install root at the pinned version and is on
  that account's PATH, the user variables are set, and the MCP servers, plugins, language
  servers and skills are in place. It also says what kind of machine and
  profile it sees (a VDI desktop, a multi-session host, a roaming profile or a profile
  container) and how much the install put where a roaming profile would copy it at every logon.
  Needs no admin rights, changes nothing, and prints one line per check; exits 1 if any failed.
    .\scripts\check-install.ps1

.PARAMETER Root         The install root to check. Default: AGENT_TOOLKIT_HOME, as the install
                        recorded it, or %LOCALAPPDATA%\Programs\agent-toolkit.
.PARAMETER SkipApps     Leave out the app checks (for an install run with -SkipApps).
.PARAMETER SkipCaches   Leave out the MCP, plugin and skill checks (-SkipCaches).
.PARAMETER SkipConfig   Leave out the Claude Code config check (-SkipConfig).
.PARAMETER SkipEnv      Leave out the environment variable checks (-SkipEnv).
.PARAMETER StandardUser Also fail if this account is an administrator. The weekly build runs
                        the whole install, then this, as a new account with no admin rights.
.PARAMETER MaxProfileMB Also fail if the install put more than this many MB in the parts of the
                        profile a roaming profile copies (the weekly build sets a limit).
#>
[CmdletBinding()]
param(
  [string]$Root,
  [switch]$SkipApps,
  [switch]$SkipCaches,
  [switch]$SkipConfig,
  [switch]$SkipEnv,
  [switch]$StandardUser,
  [int]$MaxProfileMB = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
# PowerShell variable names ignore case, so the repo folder is $repo: $root would be -Root.
$repo   = Split-Path -Parent $PSScriptRoot
$win    = Join-Path $repo 'windows'
$caches = Join-Path $repo 'caches'
$home_  = $env:USERPROFILE
$failed = New-Object System.Collections.Generic.List[string]

function Ok([string]$What, [string]$Detail)   { Write-Host ('  ok    {0,-16} {1}' -f $What, $Detail) }
function Note([string]$What, [string]$Detail) { Write-Host ('  note  {0,-16} {1}' -f $What, $Detail) }
function Fail([string]$What, [string]$Detail) { Write-Host ('  FAIL  {0,-16} {1}' -f $What, $Detail); $failed.Add("${What}: $Detail") }
function Pin([string]$Dir, [string]$Filter, [string]$Regex) {
  # the version the release pins, read from the installer's file name in windows\
  $f = Get-ChildItem $Dir -Filter $Filter -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($f -and $f.Name -match $Regex) { return $Matches[1] }
  return $null
}
function SizeMB([string]$Path) {
  if (-not (Test-Path $Path)) { return 0 }
  $item = Get-Item $Path -Force
  if (-not $item.PSIsContainer) { return [math]::Round($item.Length / 1MB) }
  try { $sum = 0L; foreach ($f in $item.EnumerateFiles('*', [IO.SearchOption]::AllDirectories)) { $sum += $f.Length }; return [math]::Round($sum / 1MB) }
  catch { return [math]::Round(((Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB) }
}

# the command as run, so a saved log says which checks it asked for
Write-Host ('== check-install.ps1 ' + (($PSBoundParameters.GetEnumerator() | ForEach-Object { if ($_.Value -is [switch]) { "-$($_.Key)" } else { "-$($_.Key) $($_.Value)" } }) -join ' ')).TrimEnd()

# What a new terminal gets: the user's variables and PATH as they are in the registry now.
Import-NewTerminalEnvironment
if (-not $Root) { $Root = Get-ToolkitRoot }
$Root     = $Root.TrimEnd('\')
$binDir   = Join-Path $Root 'bin'
$userPath = @("$([Environment]::GetEnvironmentVariable('Path', 'User'))" -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') })

Write-Host '== Account'
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
# whoami lists BUILTIN\Administrators (S-1-5-32-544) for any member, even with UAC filtering the token
$inAdmins = @(Invoke-Native { & whoami.exe /groups /fo csv } | Select-Object -Skip 1 | ConvertFrom-Csv -Header Name, Type, Sid, Attributes | Where-Object { $_.Sid -eq 'S-1-5-32-544' }).Count -gt 0
$what = if (Test-Elevated) { "$me, elevated" } elseif ($inAdmins) { "$me, in Administrators but not elevated" } else { $null }
if (-not $what) { Ok 'account' "$me, a standard user: not in Administrators" }
elseif ($StandardUser) { Fail 'account' "$what; this check is meant to run as a standard user" }
else { Note 'account' $what }

Write-Host '== This machine'
# All read-only, and readable by a standard user: the session, the edition, VDI agents' services,
# and how the profile is kept. Each is a hint about where the install root has to live.
$os = Get-CimInstance Win32_OperatingSystem
$session = "$env:SESSIONNAME"
$kind = if ($session -like 'ICA-*') { 'a Citrix session' } elseif ($session -like 'RDP-*') { 'a remote desktop session' } elseif ($session -eq 'Console') { 'the console' } else { 'a session with no name' }
Note 'session' "$kind$(if ($session) { " ($session)" }), on $($os.Caption)"
if ($os.Caption -match 'multi-session' -or $os.ProductType -ne 1) {
  Note 'shared host' 'several people can be signed in here at once. Each one installs into their own account, and each T3 Code takes the next free port from 3773.'
}
$agents = @(@(@('BrokerAgent', 'Citrix VDA'), @('WSNM', 'VMware Horizon agent'), @('RDAgentBootLoader', 'Azure Virtual Desktop or Windows 365 agent')) | Where-Object { Get-Service -Name $_[0] -ErrorAction SilentlyContinue } | ForEach-Object { $_[1] })
if ($agents) { Note 'vdi' "$($agents -join ', ') running: a virtual desktop" }
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$central = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction SilentlyContinue).CentralProfile
$fslogix = (Get-ItemProperty 'HKLM:\SOFTWARE\FSLogix\Profiles' -ErrorAction SilentlyContinue).Enabled -eq 1
$upm = [bool](Get-Service -Name ctxProfile -ErrorAction SilentlyContinue)
$keepsLocal = $true
if ($fslogix) { Note 'profile' 'FSLogix profile containers are on: the whole profile, AppData\Local included, is kept between sessions' }
elseif ($upm) { $keepsLocal = $false; Note 'profile' "Citrix Profile Management: it's often set to leave AppData\Local out, so ask IT whether it's kept" }
elseif ($central) { $keepsLocal = $false; Note 'profile' "a roaming profile ($central): it doesn't carry AppData\Local to other machines" }
else { Ok 'profile' 'a local profile' }
$rootLocal = $Root.StartsWith($env:LOCALAPPDATA, [StringComparison]::OrdinalIgnoreCase)
if (-not $keepsLocal -and $rootLocal) {
  Note 'install root' "$Root is in AppData\Local. If T3 Code is gone at your next sign-in, this desktop doesn't keep it: install again with -Root on a drive that persists (ask IT which)."
}
if ($env:APPDATA -like '\\*') { Note 'appdata' "AppData\Roaming is redirected to $(Split-Path $env:APPDATA): fine, the install keeps nothing there" }
if ($Root -like '\\*') { Note 'install root' "$Root is on a network share: the apps run slower from it than from a local drive" }

if (-not $SkipApps) {
  Write-Host "== Apps, from $Root"
  $ccPin = if (Test-Path (Join-Path $win 'claude-code\VERSION')) { (Get-Content (Join-Path $win 'claude-code\VERSION') -Raw).Trim() } else { $null }
  $tools = @(
    @{ id = 'node';   exe = "$Root\node\node.exe";     args = @('--version'); dir = "$Root\node";     pin = (Pin $win 'node-v*-win-x64.zip' '^node-(v[0-9.]+)-win-x64\.zip$') },
    @{ id = 'git';    exe = "$Root\git\cmd\git.exe";   args = @('--version'); dir = "$Root\git\cmd";  pin = (Pin $win 'PortableGit-*-64-bit.7z.exe' '^PortableGit-([0-9]+\.[0-9]+\.[0-9]+)') },
    @{ id = 'bash';   exe = "$Root\git\bin\bash.exe";  args = @('--version'); dir = $null;            pin = $null },
    @{ id = 'gh';     exe = "$Root\gh\bin\gh.exe";     args = @('--version'); dir = "$Root\gh\bin";   pin = (Pin $win 'gh_*_windows_amd64.zip' '^gh_([0-9.]+)_windows') },
    @{ id = 'pwsh';   exe = "$Root\pwsh\pwsh.exe";     args = @('--version'); dir = "$Root\pwsh";     pin = (Pin $win 'PowerShell-*-win-x64.zip' '^PowerShell-([0-9.]+)-win') },
    @{ id = 'python'; exe = "$Root\python\python.exe"; args = @('--version'); dir = "$Root\python";   pin = (Pin $win 'python.*.nupkg' '^python\.([0-9.]+)\.nupkg$') },
    @{ id = 'claude'; exe = "$binDir\claude.exe";      args = @('--version'); dir = $binDir;          pin = $ccPin }
  )
  foreach ($t in $tools) {
    if (-not (Test-Path $t.exe)) { Fail $t.id "missing: $($t.exe)"; continue }
    $out = Invoke-Native { & $t.exe @($t.args) }
    # the line with the version on it; stderr is mixed in, and bash can warn before it
    $line = "$(@(@($out) | Where-Object { "$_" -match '\d+\.\d+' }) + @(@($out) | Where-Object { "$_".Trim() }) | Select-Object -First 1)".Trim()
    if ($LASTEXITCODE -ne 0) { Fail $t.id "$($t.exe) exited $LASTEXITCODE`: $line"; continue }
    if ($t.pin -and $line -notlike "*$($t.pin)*") { Fail $t.id "runs $line, but the release pins $($t.pin)"; continue }
    if ($t.dir -and $userPath -notcontains $t.dir.TrimEnd('\')) { Fail $t.id "$($t.dir) is not on the user PATH"; continue }
    Ok $t.id "$line  ($($t.exe))"
    # Windows puts the machine PATH before the user PATH, so a copy installed for all users wins.
    $first = Get-Command "$($t.id).exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($t.dir -and $first -and $first.Source -ne $t.exe) { Note $t.id "a new terminal runs $($first.Source) first; it was installed for all users" }
  }

  $npmrc = Join-Path $Root 'node\node_modules\npm\npmrc'
  if (Test-Path $npmrc) {
    # What the install set up: Node's own npmrc points global packages at the root, which is on PATH.
    $want = Join-Path $Root 'npm'
    $set = "$(Get-Content $npmrc | Where-Object { $_ -match '^prefix=' } | Select-Object -First 1)" -replace '^prefix=', ''
    if ($set.TrimEnd('\') -ne $want) { Fail 'npm prefix' "Node's npmrc sends global packages to '$set', not $want" }
    elseif ($userPath -notcontains $want) { Fail 'npm prefix' "$want is not on the user PATH" }
    else { Ok 'npm prefix' $want }
    # A prefix variable set for the machine or the user wins over the npmrc for npm install -g in a terminal.
    if ($env:npm_config_prefix -and $env:npm_config_prefix.TrimEnd('\') -ne $want) {
      Note 'npm prefix' "npm_config_prefix is set to $($env:npm_config_prefix) here, so npm install -g in a terminal goes there; the kit's own packages are in $want"
    }
  }

  $t3 = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\t3code') -Filter '*.exe' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike 'Uninstall*' } | Select-Object -First 1
  if ($t3) { Ok 't3 code' "$($t3.VersionInfo.ProductVersion)  ($($t3.FullName))" } else { Fail 't3 code' 'no T3 Code in %LOCALAPPDATA%\Programs\t3code' }
}

if (-not $SkipEnv) {
  Write-Host '== User environment variables'
  $want = [ordered]@{ AGENT_TOOLKIT_HOME = $Root; T3CODE_DISABLE_AUTO_UPDATE = '1'; T3CODE_TELEMETRY_ENABLED = '0'; DISABLE_AUTOUPDATER = '1'; CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'; PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = '1'; npm_config_offline = 'true'; PIP_NO_INDEX = '1' }
  $wrong = @($want.Keys | Where-Object { [Environment]::GetEnvironmentVariable($_, 'User') -ne $want[$_] })
  if ($wrong) { Fail 'variables' "not set for this user: $($wrong -join ', ')" } else { Ok 'variables' "$($want.Count) checked, including AGENT_TOOLKIT_HOME and DISABLE_AUTOUPDATER" }
}

if (-not $SkipConfig) {
  Write-Host '== Claude Code config'
  $cj = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json' } else { Join-Path $home_ '.claude.json' }
  $cfg = if (Test-Path $cj) { Get-Content $cj -Raw | ConvertFrom-Json } else { $null }
  if ($cfg -and $cfg.hasCompletedOnboarding -eq $true) { Ok 'onboarding seed' $cj } else { Fail 'onboarding seed' "not merged into $cj" }
}

if (-not $SkipCaches) {
  Write-Host '== MCP servers'
  $cj = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json' } else { Join-Path $home_ '.claude.json' }
  $cfg = if (Test-Path $cj) { Get-Content $cj -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
  $have = if ($cfg.PSObject.Properties['mcpServers']) { $cfg.mcpServers } else { [pscustomobject]@{} }
  $servers = (Get-Content (Join-Path $repo 'config\mcp-servers.json') -Raw | ConvertFrom-Json).servers
  $defaults = @($servers | Where-Object { $_.default -and (-not $_.platforms -or @($_.platforms) -contains 'win') } | ForEach-Object id)
  $missing = @($defaults | Where-Object { -not $have.PSObject.Properties[$_] })
  if ($missing) { Fail 'registered' "default servers not in ${cj}: $($missing -join ', ')" } else { Ok 'registered' "$($defaults.Count) default servers: $($defaults -join ', ')" }
  foreach ($p in $have.PSObject.Properties) {
    $cmd = $p.Value.command; $first = @($p.Value.args)[0]
    if ($cmd -eq 'node') { if (-not (Test-Path $first)) { Fail $p.Name "entry point missing: $first" } }
    elseif (-not (Test-Path $cmd)) { Fail $p.Name "command missing: $cmd" }
  }
  $venvDir = Join-Path $Root 'venv-mcp'
  $venvs = @(Get-ChildItem $venvDir -Directory -ErrorAction SilentlyContinue)
  if ($venvs.Count -lt 10) { Fail 'python servers' "only $($venvs.Count) in $venvDir" } else { Ok 'python servers' "$($venvs.Count) in $venvDir" }
  if (Test-Path (Join-Path $home_ 'agent-toolkit-docs\mcp-servers.md')) { Ok 'catalog' '~\agent-toolkit-docs\mcp-servers.md' } else { Fail 'catalog' 'mcp-servers.md not written' }

  Write-Host '== Plugins and language servers'
  $claude = Join-Path $binDir 'claude.exe'
  $idx = Join-Path $caches 'claude-plugins\index.json'
  if ((Test-Path $claude) -and (Test-Path $idx)) {
    $want = @((Get-Content $idx -Raw | ConvertFrom-Json).marketplaces | ForEach-Object { $m = $_; @($m.enable) | Where-Object { $_ } | ForEach-Object { "$_@$($m.name)" } })
    $raw = (Invoke-Native { & $claude plugin list --json }) -join "`n"
    # assigned first, then wrapped: in 5.1, @($raw | ConvertFrom-Json) nests the array in another
    try { $listed = $raw | ConvertFrom-Json; $listed = @($listed) } catch { $listed = $null; Fail 'plugins' "could not read claude plugin list --json: $($raw.Substring(0, [math]::Min(200, $raw.Length)))" }
    if ($null -ne $listed) {
      $bad = @($want | Where-Object { $id = $_; -not ($listed | Where-Object { $_.id -eq $id -and $_.enabled -and -not $_.errors }) })
      if ($bad) { Fail 'plugins' "not enabled and loading: $($bad -join ', ')" } else { Ok 'plugins' "$($want.Count) enabled and loading" }
    }
  } elseif (-not (Test-Path $idx)) { Note 'plugins' "not checked: caches\claude-plugins is gone from the repo (deleted with the release?)" }
  else { Fail 'plugins' "no $claude" }
  if (Test-Path (Join-Path $Root 'npm\pyright-langserver.cmd')) { Ok 'pyright' "$Root\npm\pyright-langserver.cmd" } else { Fail 'pyright' "pyright-langserver not in $Root\npm" }
  if (Test-Path (Join-Path $binDir 'rust-analyzer.exe')) { Ok 'rust-analyzer' "$binDir\rust-analyzer.exe" } else { Fail 'rust-analyzer' "not in $binDir" }

  Write-Host '== Skills'
  $skills = 'docx', 'full-send'
  $gone = @($skills | Where-Object { -not (Test-Path (Join-Path $home_ ".claude\skills\$_\SKILL.md")) })
  if ($gone) { Fail 'skills' "missing from ~\.claude\skills: $($gone -join ', ')" } else { Ok 'skills' "$($skills -join ', ') and the rest" }
}

Write-Host '== Footprint'
# A roaming profile copies everything under the profile except AppData\Local at every logon and
# logoff, so the install keeps its weight in the root and only small, tool-owned folders here.
if (Test-Path $Root) { Ok 'install root' ("{0}: {1:N0} MB" -f $Root, (SizeMB $Root)) }
$parts = [ordered]@{ '~\.t3\tools' = (Join-Path $home_ '.t3\tools'); '~\.claude\skills' = (Join-Path $home_ '.claude\skills'); '~\.claude\plugins' = (Join-Path $home_ '.claude\plugins'); '~\agent-toolkit-docs' = (Join-Path $home_ 'agent-toolkit-docs') }
if (-not $Root.StartsWith($env:LOCALAPPDATA, [StringComparison]::OrdinalIgnoreCase) -and $Root.StartsWith($home_, [StringComparison]::OrdinalIgnoreCase)) { $parts["$Root (the install root)"] = $Root }
$sizes = [ordered]@{}; foreach ($k in $parts.Keys) { $sizes[$k] = SizeMB $parts[$k] }
$total = ($sizes.Values | Measure-Object -Sum).Sum
$detail = ($sizes.Keys | Where-Object { $sizes[$_] } | ForEach-Object { "$_ $($sizes[$_])" }) -join ', '
$line = "{0:N0} MB where a roaming profile would copy it{1}" -f $total, $(if ($detail) { ": $detail" } else { '' })
if ($MaxProfileMB -gt 0 -and $total -gt $MaxProfileMB) { Fail 'profile' "$line; the limit is $MaxProfileMB MB" } else { Ok 'profile' $line }
# folders that earlier versions of the install used, in the parts of the profile that roam
$older = @('.npm-toolkit-cache', '.venv-mcp', '.claude-toolkit', '.cache\killer-skills', '.cache\killer-skills-fonts', '.cache\ms-playwright', '.local\bin\claude.exe') |
  Where-Object { Test-Path (Join-Path $home_ $_) } | ForEach-Object { "~\$_ ($(SizeMB (Join-Path $home_ $_)) MB)" }
if ($older) { Note 'older layout' "$($older -join ', '): where earlier installs put things. Unless they're your own, delete them; nothing here uses them now." }

Write-Host ''
if ($failed.Count) {
  Write-Host "$($failed.Count) check(s) failed:"
  foreach ($f in $failed) { Write-Host "  $f" }
  exit 1
}
Write-Host "Every check passed, for $me."
exit 0
