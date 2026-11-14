<#
.SYNOPSIS
  Installs the toolkit for the current user on a Windows machine that fetches nothing at run
  time, with no admin rights. Run it from a normal PowerShell (not "Run as administrator") in
  the repo root, after unpack-release.ps1. Windows PowerShell 5.1 is enough.

  Everything goes into your own account, and everything heavy into one folder, the install
  root (-Root; %LOCALAPPDATA%\Programs\agent-toolkit unless you pick another):
    node, git, gh, pwsh, python   Node.js, the portable Git for Windows, the GitHub CLI,
                                  PowerShell 7, and Python 3.13 (python.org's NuGet build)
    bin                           the Claude Code CLI, and the MCP and language-server binaries
    npm                           global npm packages
    venv-mcp                      the Python MCP servers, one virtual environment each
    plugins                       the vendored Claude Code plugin marketplaces
    cache                         npm's cache, Playwright's browsers and the Python wheels
  T3 Code installs per user into %LOCALAPPDATA%\Programs\t3code and keeps its own data and tool
  cache in ~\.t3. Claude Code's config, skills and plugins go in ~\.claude. The root's folders go
  on your user PATH and the variables in config\env-vars.md into your user environment (HKCU).
  Nothing is written for other users and nothing asks for elevation. Once it's done, nothing
  points back at the downloaded release, so that can be deleted.

  The default root sits outside the parts of the profile a roaming profile copies at every
  logon. On a VDI desktop that doesn't keep AppData\Local between sessions, pick a root on a
  drive that does, for example -Root D:\agent-toolkit. check-install.ps1 says what it sees.

.PARAMETER Root        Where the apps, binaries and caches go. Recorded as AGENT_TOOLKIT_HOME.
.PARAMETER SkipApps    Skip the apps (T3 Code, Node, Git, gh, PowerShell 7, Python, Claude Code).
.PARAMETER SkipCaches  Skip restoring caches, npm packages, MCP servers, plugins, skills, docs.
.PARAMETER SkipConfig  Skip seeding T3 Code and Claude Code config files.
.PARAMETER SkipEnv     Skip the variables that turn off updaters and telemetry and keep npm and
                       pip offline. PATH, AGENT_TOOLKIT_HOME and the variables that point tools
                       at the root's caches are set either way.
#>
[CmdletBinding()]
param(
  [string]$Root = (Join-Path $env:LOCALAPPDATA 'Programs\agent-toolkit'),
  [switch]$SkipApps,
  [switch]$SkipCaches,
  [switch]$SkipConfig,
  [switch]$SkipEnv
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
# PowerShell variable names ignore case, so the repo folder is $repo: $root would be -Root.
$repo     = Split-Path -Parent $PSScriptRoot
$win      = Join-Path $repo 'windows'
$caches   = Join-Path $repo 'caches'
$config   = Join-Path $repo 'config'
$home_    = $env:USERPROFILE
$Root     = [IO.Path]::GetFullPath($Root).TrimEnd('\')
$env:AGENT_TOOLKIT_HOME = $Root   # common.ps1, install-mcp.ps1 and install-plugins.py read it
# Global npm packages go to the root's npm folder. Node's npmrc says so too, but a prefix variable
# set for the whole machine (the GitHub runners set one, and so may IT) would win over it.
$env:npm_config_prefix = Join-Path $Root 'npm'
$nodeDir  = Join-Path $Root 'node'
$npmDir   = Join-Path $Root 'npm'
$gitDir   = Join-Path $Root 'git'
$ghDir    = Join-Path $Root 'gh'
$pwshDir  = Join-Path $Root 'pwsh'
$pyDir    = Join-Path $Root 'python'
$binDir   = Join-Path $Root 'bin'
$cacheDir = Join-Path $Root 'cache'
$npmCache = Join-Path $cacheDir 'npm'
$pwCache  = Join-Path $cacheDir 'ms-playwright'
$wheelDir = Join-Path $cacheDir 'pip-wheelhouse'
$problems = New-Object System.Collections.Generic.List[string]

$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
if (Test-Elevated) {
  Write-Warning "This PowerShell is elevated, as $me. Nothing here needs that, and everything installs into ${me}'s profile. If you elevated with someone else's account, close this window and run the script again from a normal PowerShell."
}
if ($Root -like '\\*') {
  Write-Warning "$Root is on a network share. Node, Python and Git run noticeably slower from one; a local drive that persists between sessions is better, if your desktop has one."
} elseif ($Root.StartsWith($home_, [StringComparison]::OrdinalIgnoreCase) -and -not $Root.StartsWith($env:LOCALAPPDATA, [StringComparison]::OrdinalIgnoreCase)) {
  Write-Warning "$Root is in a part of your profile that a roaming profile copies at every logon and logoff; the install root is several GB. %LOCALAPPDATA%, or a drive outside the profile, is better."
}
Write-Host "== Installing for $me, into $Root"
New-Item -ItemType Directory -Force -Path $Root | Out-Null
Write-Utf8 (Join-Path $Root 'agent-toolkit.txt') ("Installed by agent-toolkit's install-windows.ps1 for $me on $(Get-Date -Format 'yyyy-MM-dd').`r`n" +
  "Its apps, binaries and caches are all in this folder; deleting it removes them. See https://github.com/Real-Fruit-Snacks/agent-toolkit`r`n")

function Pick($dir, $pattern, $hint) {
  $f = Get-ChildItem -Path $dir -Filter $pattern -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $f) { throw "Missing $pattern in $dir$(if ($hint) { ". $hint" })" }
  return $f.FullName
}

function Step([string]$Title, [scriptblock]$Body) {
  # One app: a failure is reported and remembered, and the install carries on with the rest.
  Write-Host "== $Title"
  try { & $Body }
  catch { Write-Warning "$Title failed: $($_.Exception.Message)"; $problems.Add("${Title}: $($_.Exception.Message)") }
}

function Install-Folder([string]$Target, [scriptblock]$Fill) {
  # Fills a staging folder beside $Target, then swaps it in, so a failed copy never replaces a
  # working one. If a program in $Target is running, the copy there is left as it was.
  $stage = "$Target.new-$PID"
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  New-Item -ItemType Directory -Force -Path (Split-Path $Target) | Out-Null
  & $Fill $stage
  if (-not (Test-Path $Target)) { [IO.Directory]::Move($stage, $Target); return }
  $prev = "$Target.old-$PID"
  try { [IO.Directory]::Move($Target, $prev) }
  catch { Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue; throw "$Target is in use; close what runs from it and run this again" }
  [IO.Directory]::Move($stage, $Target)
  Remove-Item $prev -Recurse -Force -ErrorAction SilentlyContinue
}

function Expand-Zip([string]$Zip, [string]$Dest, [string]$Under) {
  # Unzips $Zip into $Dest: only the entries under $Under/ if given, and lifted out of a single
  # top-level folder if that is all the archive holds.
  if ($Under) {
    $z = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
      foreach ($e in $z.Entries) {
        if (-not $e.Name -or -not $e.FullName.StartsWith("$Under/")) { continue }
        $t = Join-Path $Dest ($e.FullName.Substring($Under.Length + 1) -replace '/', '\')
        New-Item -ItemType Directory -Force -Path (Split-Path $t) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $t, $true)
      }
    } finally { $z.Dispose() }
    return
  }
  [IO.Compression.ZipFile]::ExtractToDirectory($Zip, $Dest)
  $top = @(Get-ChildItem -LiteralPath $Dest -Force)
  if ($top.Count -eq 1 -and $top[0].PSIsContainer) {
    $inner = $top[0].FullName
    Get-ChildItem -LiteralPath $inner -Force | Move-Item -Destination $Dest
    Remove-Item -LiteralPath $inner -Force
  }
}

function Start-Installer([string]$Exe, [string[]]$ArgumentList, [int[]]$Ok = @(0)) {
  $p = Start-Process -FilePath $Exe -ArgumentList $ArgumentList -Wait -PassThru
  if ($Ok -notcontains $p.ExitCode) { throw "$(Split-Path -Leaf $Exe) exited with code $($p.ExitCode)" }
}

function Copy-Folder([string]$From, [string]$To) {
  # A cache copied from the unpacked release into the root, replacing what was there before.
  if (Test-Path $To) { Remove-Item $To -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  Copy-Item (Join-Path $From '*') $To -Recurse -Force
}

if (-not $SkipApps) {
  $older = 'Releases before the no-admin install ship this as an MSI, which needs admin rights; get the latest release with download-release.ps1'

  Step "Node.js -> $nodeDir" {
    $zip = Pick $win 'node-v*-win-x64.zip' $older
    Install-Folder $nodeDir {
      param($d)
      Expand-Zip $zip $d
      # Global packages go in the root too, beside Node, rather than in %APPDATA%, which a VDI
      # desktop often redirects to a network share.
      Set-Content (Join-Path $d 'node_modules\npm\npmrc') "prefix=$npmDir" -Encoding ascii
    }
    New-Item -ItemType Directory -Force -Path $npmDir | Out-Null
    Add-UserPath $nodeDir
    Add-UserPath $npmDir
  }

  Step "Git for Windows (portable) -> $gitDir" {
    $sfx = Pick $win 'PortableGit-*-64-bit.7z.exe' 'Releases before the no-admin install ship the Git installer instead; get the latest release with download-release.ps1'
    Install-Folder $gitDir {
      param($d)
      Start-Installer $sfx @("-o`"$d`"", '-y')
      # Run from the command line, the self-extractor skips post-install.bat, and Git doesn't run
      # right without it. Give it only this copy on PATH: with a machine-wide git first on PATH,
      # it would try to write into that one.
      $keep = $env:Path
      try {
        $env:Path = "$d\cmd;$env:SystemRoot\System32;$env:SystemRoot"
        $out = Invoke-Native { & cmd.exe /d /c "`"$d\post-install.bat`"" }
      } finally { $env:Path = $keep }
      # it deletes itself as its last step, which is how to tell that it finished
      if (Test-Path (Join-Path $d 'post-install.bat')) { throw "post-install.bat didn't finish: $($out -join ' ')" }
      $out | Where-Object { $_ -match 'error|denied|fail' -and $_ -notmatch 'batch file cannot be found' } | ForEach-Object { Write-Warning "  git post-install: $_" }
    }
    Add-UserPath (Join-Path $gitDir 'cmd')
  }

  Step "GitHub CLI -> $ghDir" {
    $zip = Pick $win 'gh_*_windows_amd64.zip' $older
    Install-Folder $ghDir { param($d) Expand-Zip $zip $d }
    Add-UserPath (Join-Path $ghDir 'bin')
  }

  Step "PowerShell 7 -> $pwshDir" {
    $zip = Pick $win 'PowerShell-*-win-x64.zip' $older
    Install-Folder $pwshDir { param($d) Expand-Zip $zip $d }
    Add-UserPath $pwshDir
  }

  Step "Python -> $pyDir" {
    # python.org's NuGet build: the same Python as its installer, as a plain archive, so it
    # can't collide with a Python someone installed for all users.
    $pkg = Pick $win 'python.3.*.nupkg' 'Releases before the no-admin install ship the python.org installer instead; get the latest release with download-release.ps1'
    Install-Folder $pyDir { param($d) Expand-Zip $pkg $d 'tools' }
    Add-UserPath $pyDir
    Add-UserPath (Join-Path $pyDir 'Scripts')
  }

  Step 'T3 Code (per-user installer) -> %LOCALAPPDATA%\Programs\t3code' {
    Start-Installer (Pick $win 'T3-Code-*-x64.exe') @('/S', '/currentuser')
  }

  Step "Claude Code CLI -> $binDir" {
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    Copy-Item (Pick (Join-Path $win 'claude-code') 'claude-*-win32-x64.exe') (Join-Path $binDir 'claude.exe') -Force
    Add-UserPath $binDir
  }
}

if (-not $SkipCaches) {
  # bin and npm hold the MCP and language-server binaries, which Claude Code finds on PATH
  New-Item -ItemType Directory -Force -Path $binDir, $npmDir | Out-Null
  Add-UserPath $binDir
  Add-UserPath $npmDir
  # this run's own tools look in the root's caches, whatever the user environment says yet
  $env:npm_config_cache = $npmCache
  $env:PLAYWRIGHT_BROWSERS_PATH = $pwCache

  Write-Host '== Restoring T3 tool cache'
  $t3tools = Join-Path $home_ '.t3\tools'
  New-Item -ItemType Directory -Force -Path $t3tools | Out-Null
  Copy-Item (Join-Path $caches 't3-tools-win\*') $t3tools -Recurse -Force

  Write-Host '== Restoring T3 manifest snapshots'
  $t3user = Join-Path $home_ '.t3\userdata'
  New-Item -ItemType Directory -Force -Path $t3user | Out-Null
  Copy-Item (Join-Path $caches 't3-userdata\*') $t3user -Force

  Write-Host "== Restoring Playwright browsers -> $pwCache"
  Copy-Folder (Join-Path $caches 'playwright-browsers') $pwCache

  Write-Host "== Installing npm packages from the seeded cache -> $npmCache"
  if (Test-Path (Join-Path $caches 'npm-cache')) {
    Copy-Folder (Join-Path $caches 'npm-cache') $npmCache
    $npm = Find-Npm
    if ($npm) {
      foreach ($pkg in 'playwright', '@playwright/cli', 'agent-device', 'expo-device-hub') {
        $null = Invoke-Native { & $npm install -g --offline --cache "$npmCache" --no-audit --no-fund $pkg }
        if ($LASTEXITCODE -ne 0) { Write-Warning "global npm install of $pkg from the cache failed; T3 still works from its own tool cache" }
      }
    } else { Write-Warning 'npm not found; skipping the global npm packages' }
  }

  Write-Host '== Installing Claude Code skills'
  if (Test-Path (Join-Path $caches 'claude-skills')) {
    $skills = Join-Path $home_ '.claude\skills'
    New-Item -ItemType Directory -Force -Path $skills | Out-Null
    Get-ChildItem (Join-Path $caches 'claude-skills') -Directory | ForEach-Object { Copy-Item $_.FullName (Join-Path $skills $_.Name) -Recurse -Force }
  }

  $py = Find-Python
  Write-Host "== Installing Python packages for the document skills (wheels kept in $wheelDir)"
  if (Test-Path (Join-Path $caches 'pip-wheelhouse\win')) {
    # A copy in the root, so pip still has its wheels after the downloaded release is deleted
    Copy-Folder (Join-Path $caches 'pip-wheelhouse\win') $wheelDir
    Copy-Item (Join-Path $caches 'pip-wheelhouse\requirements*.txt') $wheelDir -Force
    if ($py) {
      $out = Invoke-Native { & $py -m pip install --quiet --disable-pip-version-check --no-index --find-links "$wheelDir" -r (Join-Path $wheelDir 'requirements.txt') }
      if ($LASTEXITCODE -ne 0) { Write-Warning "pip install from the wheelhouse had errors: $(@($out | Select-Object -Last 3) -join ' ')" }
    }
    else { Write-Warning "Python 3.13 not found; open a new terminal and run: python -m pip install --no-index --find-links `"$wheelDir`" -r `"$wheelDir\requirements.txt`"" }
  }

  Write-Host '== MCP servers'
  & (Join-Path $PSScriptRoot 'install-mcp.ps1')

  Write-Host '== Claude Code plugin marketplaces and language servers'
  $claudeExe = Join-Path $binDir 'claude.exe'
  if ($py -and (Test-Path $claudeExe) -and (Test-Path (Join-Path $caches 'claude-plugins\index.json'))) {
    & $py (Join-Path $PSScriptRoot 'install-plugins.py') --repo $repo --claude $claudeExe --marketplaces (Join-Path $Root 'plugins') --bin $binDir
    if ($LASTEXITCODE -ne 0) { Write-Warning 'plugin install reported problems; re-run this script' }
  } else { Write-Warning 'skipping plugins: needs Python 3.13, the Claude Code CLI, and caches\claude-plugins' }

  Write-Host '== Placing offline docs'
  $docs = Join-Path $home_ 'agent-toolkit-docs'
  New-Item -ItemType Directory -Force -Path $docs | Out-Null
  if (Test-Path (Join-Path $caches 'claude-code-docs')) { Copy-Item (Join-Path $caches 'claude-code-docs') (Join-Path $docs 'claude-code') -Recurse -Force }
  if (Test-Path (Join-Path $repo 'docs\reference\t3code')) { Copy-Item (Join-Path $repo 'docs\reference\t3code') (Join-Path $docs 't3code') -Recurse -Force }
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
    Write-Utf8 $path ($cur | ConvertTo-Json -Depth 20)
  }
  $cfgDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $home_ '.claude' }
  $cj = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $cfgDir '.claude.json' } else { Join-Path $home_ '.claude.json' }
  Merge-Seed $cj (Join-Path $config 'claude-home\claude.json.example')
  Merge-Seed (Join-Path $cfgDir 'settings.json') (Join-Path $config 'claude-home\settings.json.example')
}

Write-Host '== Setting user environment variables'
# Where things are: set whatever else is skipped, since the tools can't find the root without them.
$where = [ordered]@{ AGENT_TOOLKIT_HOME = $Root }
if (-not $SkipCaches) { $where.PLAYWRIGHT_BROWSERS_PATH = $pwCache }
foreach ($k in $where.Keys) { [Environment]::SetEnvironmentVariable($k, $where[$k], 'User') }
if (-not $SkipEnv) {
  $vars = @{
    T3CODE_DISABLE_AUTO_UPDATE               = '1'
    T3CODE_TELEMETRY_ENABLED                 = '0'
    T3CODE_OTEL_SDK_DISABLED                 = '1'
    DISABLE_AUTOUPDATER                      = '1'
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = '1'
    DISABLE_TELEMETRY                        = '1'
    DISABLE_ERROR_REPORTING                  = '1'
    GH_NO_UPDATE_NOTIFIER                    = '1'
    POWERSHELL_UPDATECHECK                   = 'Off'
    POWERSHELL_TELEMETRY_OPTOUT              = '1'
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD         = '1'
    npm_config_cache                         = $npmCache
    npm_config_offline                       = 'true'
    PIP_NO_INDEX                             = '1'
    PIP_FIND_LINKS                           = $wheelDir
  }
  foreach ($k in $vars.Keys) { [Environment]::SetEnvironmentVariable($k, $vars[$k], 'User') }
}

if (-not (Send-EnvironmentChange)) { Write-Warning 'Could not tell Windows the PATH changed; sign out and back in if a new terminal does not see it.' }

Write-Host ''
if ($problems.Count) {
  Write-Warning "Finished with $($problems.Count) problem(s):"
  foreach ($p in $problems) { Write-Warning "  $p" }
}
Write-Host "Done, for $me, without admin rights. Open a NEW terminal, then launch T3 Code from the Start menu."
Write-Host 'In Settings > Providers > Claude set Binary path to:'
Write-Host "  $binDir\claude.exe"
Write-Host 'and add the endpoint variables from config\claude-provider-env.example.'
Write-Host "Offline docs: $home_\agent-toolkit-docs"
Write-Host 'Nothing points back at the downloaded release any more; delete it to free the space.'
Write-Host 'To check the install from a new terminal: .\scripts\check-install.ps1'
if ($problems.Count) { exit 1 }
exit 0   # explicit, so a native command's last exit code can't stand in for the result
