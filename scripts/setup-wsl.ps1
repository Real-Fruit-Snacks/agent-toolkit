<#
.SYNOPSIS
  Imports the provisioned Ubuntu distro (ubuntu-dev) into WSL for the current user.
  Prefers the baked export (wsl\ubuntu-dev.tar.gz) and falls back to the raw rootfs.

  With WSL already on the machine, as IT often leaves it, this needs no admin rights: a WSL
  distro belongs to the user who imports it. Run it from a normal PowerShell.

  Turning WSL on in the first place does need an administrator, once per machine. Without WSL,
  this stops and says so; from an elevated PowerShell it enables the features and installs WSL
  from the bundled MSI, then imports the distro for the elevated account. A reboot may be
  needed the first time.
#>
[CmdletBinding()]
param(
  [string]$DistroName = 'ubuntu-dev',
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'WSL\ubuntu-dev')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$root = Split-Path -Parent $PSScriptRoot
$wsl  = Join-Path $root 'wsl'
$me   = [Security.Principal.WindowsIdentity]::GetCurrent().Name

# wsl.exe --version only works once the WSL package is installed; the stub Windows ships without it fails
$hasWsl = $false
if (Get-Command wsl.exe -ErrorAction SilentlyContinue) { $null = Invoke-Native { & wsl.exe --version }; $hasWsl = ($LASTEXITCODE -eq 0) }

if ($hasWsl) {
  Write-Host '== WSL is installed; importing for this account (no admin rights needed)'
} elseif (-not (Test-Elevated)) {
  $msi = Get-ChildItem $wsl -Filter 'wsl.*.x64.msi' -ErrorAction SilentlyContinue | Select-Object -First 1
  throw ("WSL isn't installed on this machine, and turning it on needs an administrator, once. Ask IT to install WSL" +
         $(if ($msi) { " (the release carries the installer: wsl\$($msi.Name))" } else { '' }) +
         ', or run this script from an elevated PowerShell. Then run it again from a normal PowerShell: importing the distro needs no admin rights.')
} else {
  $msi = Get-ChildItem $wsl -Filter 'wsl.*.x64.msi' | Select-Object -First 1
  if (-not $msi) { throw 'wsl.*.x64.msi not found in wsl\' }
  Write-Host '== Enabling Windows features (no-op if already on)'
  dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
  dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
  Write-Host "== Installing WSL platform from $($msi.Name)"
  Start-Process msiexec.exe -Wait -ArgumentList @('/i', "`"$($msi.FullName)`"", '/qn', '/norestart')
  Write-Warning "This window is elevated, as $me, so the distro is imported for $me. If that isn't your everyday account, run this script again from a normal PowerShell to import it for yours."
}

$null = Invoke-Native { & wsl.exe --set-default-version 2 }

$baked = @('ubuntu-dev.tar.gz', 'ubuntu-dev.tar') | ForEach-Object { Get-Item (Join-Path $wsl $_) -ErrorAction SilentlyContinue } | Select-Object -First 1
if (-not $baked -and (Get-ChildItem $wsl -Filter 'ubuntu-dev.tar.gz.part*' -ErrorAction SilentlyContinue)) { throw 'wsl\ holds ubuntu-dev.tar.gz.part* pieces; run scripts\unpack-release.ps1 to join them first' }
$rootfs = Get-ChildItem $wsl -Filter 'ubuntu-*-wsl-amd64-*.rootfs.tar.gz' | Select-Object -First 1
$source = if ($baked) { $baked.FullName } elseif ($rootfs) { $rootfs.FullName } else { throw 'No distro tarball in wsl\' }

# WSL 2 runs the distro in a small VM. On a VDI desktop, which is itself a VM, that needs the host
# to pass virtualization through, and most don't; WSL then fails with one of these.
function Explain-Wsl([string[]]$Out, [string]$What) {
  $text = ($Out -join ' ') -replace "`0", ''
  if ($text -match '0x80370102|0x80370114|HCS_E_HYPERV_NOT_INSTALLED|[Vv]irtuali[sz]ation|Virtual Machine Platform') {
    throw ("$What, because WSL 2 can't start a VM here. On a virtual desktop that usually means the host doesn't pass " +
           'virtualization through to it, which only IT can change (Hyper-V nested virtualization, or the same setting in ' +
           'VMware or Citrix). The Windows install doesn''t need WSL: install-windows.ps1 is the whole kit without it.' + "`nWSL said: $text")
  }
  throw "${What}: $text"
}

# wsl.exe -l writes UTF-16, which arrives with a NUL after each character
$existing = @(Invoke-Native { & wsl.exe -l -q }) -replace "`0", '' | Where-Object { $_.Trim() -eq $DistroName }
if ($existing) {
  Write-Host "== Distro $DistroName already registered, skipping import"
} else {
  Write-Host "== Importing $DistroName from $(Split-Path -Leaf $source) into $InstallDir"
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  $out = Invoke-Native { & wsl.exe --import $DistroName $InstallDir $source --version 2 }
  if ($LASTEXITCODE -ne 0) { Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue; Explain-Wsl $out "wsl --import failed (code $LASTEXITCODE)" }
}

Write-Host "== Starting $DistroName once"
$out = Invoke-Native { & wsl.exe -d $DistroName -- true }
if ($LASTEXITCODE -ne 0) { Explain-Wsl $out "$DistroName is imported but doesn't start (code $LASTEXITCODE)" }

wsl.exe --set-default $DistroName
Write-Host ''
if ($baked) {
  Write-Host "Done. $DistroName is ready for $me with Git, Node, gh, and Claude Code preinstalled."
  Write-Host 'Default user is "dev". Set endpoint env in ~/.claude/settings.json inside the distro.'
} else {
  Write-Host "Done, but this was the raw rootfs. Run scripts/wsl-provision.sh inside the distro"
  Write-Host 'to install Git, Node, gh, and Claude Code from the linux\ folder.'
}
Write-Host 'In T3 Code: Settings > Sharing & access > pick the distro.'
