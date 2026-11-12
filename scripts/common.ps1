<#
.SYNOPSIS
  Helpers shared by install-windows.ps1, install-mcp.ps1, setup-wsl.ps1 and check-install.ps1.
  Dot-sourced, not run on its own.

  Everything here works in Windows PowerShell 5.1 from a standard user account, because that
  is the shell and the account this kit is for: nothing needs admin rights, and every write
  goes to the user's own profile or registry hive (HKCU).
#>

function Invoke-Native([scriptblock]$Command) {
  # In Windows PowerShell 5.1, a native command's stderr becomes a terminating error when
  # $ErrorActionPreference is Stop and the stream is redirected, so npm's first warning would
  # end the install. Run it under Continue, hand back every line as text, and let the caller
  # check $LASTEXITCODE.
  $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & $Command 2>&1 | ForEach-Object { "$_" } } finally { $ErrorActionPreference = $eap }
}

function Write-Utf8([string]$Path, [string]$Text) {
  # Set-Content -Encoding utf8 writes a byte-order mark in 5.1, and not every JSON reader skips it.
  New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
  [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

function Test-Elevated {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ToolkitRoot {
  # The one folder the install puts its apps, binaries and caches in. install-windows.ps1 -Root
  # picks it and records it as the user variable AGENT_TOOLKIT_HOME; the default is outside the
  # parts of the profile that roam, so a roaming profile doesn't copy gigabytes at every logon.
  if ($env:AGENT_TOOLKIT_HOME) { return $env:AGENT_TOOLKIT_HOME.TrimEnd('\') }
  return (Join-Path $env:LOCALAPPDATA 'Programs\agent-toolkit')
}

function Find-Python([string]$Version = '3.13') {
  # The bundled wheels are built for one Python, so find that one rather than the newest: the
  # kit's own copy, then python.org's per-user and all-users installs, then any python on PATH.
  # Windows ships a Store stub named python.exe that only prints an error, so each one is run.
  $tag = $Version -replace '\.', ''
  $cands = @((Join-Path (Get-ToolkitRoot) 'python\python.exe'),
             (Join-Path $env:LOCALAPPDATA "Programs\Python\Python$tag\python.exe"),
             (Join-Path $env:ProgramFiles "Python$tag\python.exe")) | Where-Object { Test-Path $_ }
  $cands = @($cands) + @(Get-Command python.exe, python3.exe -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
  foreach ($c in $cands) {
    $v = Invoke-Native { & $c --version }
    if ($LASTEXITCODE -eq 0 -and "$v" -match "^Python $([regex]::Escape($Version))\.") { return $c }
  }
  return $null
}

function Find-Npm {
  # The kit's own Node first, then whatever is on PATH, then an all-users install.
  $own = Join-Path (Get-ToolkitRoot) 'node\npm.cmd'
  if (Test-Path $own) { return $own }
  $g = Get-Command npm.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($g) { return $g.Source }
  $all = Join-Path $env:ProgramFiles 'nodejs\npm.cmd'
  if (Test-Path $all) { return $all }
  return $null
}

function Add-UserPath([string]$Dir) {
  # Prepends $Dir to the user PATH (HKCU\Environment) if it isn't there, keeping the value
  # REG_EXPAND_SZ so entries like %USERPROFILE%\... stay unexpanded, and to this process's PATH
  # so the rest of the run finds it. Call Send-EnvironmentChange once afterwards.
  $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
  try {
    $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $entries = @($raw -split ';' | Where-Object { $_ })
    $have = @($entries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') })
    if ($have -notcontains $Dir.TrimEnd('\')) {
      $key.SetValue('Path', ((@($Dir) + $entries) -join ';'), [Microsoft.Win32.RegistryValueKind]::ExpandString)
    }
  } finally { $key.Close() }
  if (@($env:Path -split ';' | ForEach-Object { $_.TrimEnd('\') }) -notcontains $Dir.TrimEnd('\')) { $env:Path = "$Dir;$env:Path" }
}

function Send-EnvironmentChange {
  # Tells Explorer the user environment changed, so terminals opened from it see the new PATH
  # without signing out. Best effort: returns $false if it can't.
  try {
    if (-not ('AgentToolkit.Native' -as [type])) {
      Add-Type -Namespace AgentToolkit -Name Native -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);'
    }
    $r = [UIntPtr]::Zero
    [void][AgentToolkit.Native]::SendMessageTimeout([IntPtr]0xffff, 0x001A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r)
    return $true
  } catch { return $false }
}

function Import-NewTerminalEnvironment {
  # Loads the environment a terminal opened now would get: the machine variables, then the
  # user's, and PATH as the machine part followed by the user part.
  foreach ($scope in 'Machine', 'User') {
    $vars = [Environment]::GetEnvironmentVariables($scope)
    foreach ($k in $vars.Keys) { if ($k -ne 'Path') { Set-Item -Path "env:$k" -Value $vars[$k] } }
  }
  $env:Path = (@([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) | Where-Object { $_ }) -join ';'
}
