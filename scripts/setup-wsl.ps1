<#
.SYNOPSIS
  Installs the WSL platform from the bundled MSI and imports the Ubuntu distro.
  Prefers the baked export (wsl\ubuntu-dev.tar.gz) and falls back to the raw rootfs.
  Run elevated. A reboot may be required the first time WSL is enabled.
#>
[CmdletBinding()]
param(
  [string]$DistroName = 'ubuntu-dev',
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'WSL\ubuntu-dev')
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wsl  = Join-Path $root 'wsl'

$msi = Get-ChildItem $wsl -Filter 'wsl.*.x64.msi' | Select-Object -First 1
if (-not $msi) { throw 'wsl.*.x64.msi not found in wsl\' }

Write-Host '== Enabling Windows features (no-op if already on)'
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null

Write-Host "== Installing WSL platform from $($msi.Name)"
Start-Process msiexec.exe -Wait -ArgumentList @('/i', "`"$($msi.FullName)`"", '/qn', '/norestart')

wsl.exe --set-default-version 2 | Out-Null

$baked = Get-ChildItem $wsl -Filter 'ubuntu-dev.tar*' | Select-Object -First 1
$rootfs = Get-ChildItem $wsl -Filter 'ubuntu-*-wsl-amd64-*.rootfs.tar.gz' | Select-Object -First 1
$source = if ($baked) { $baked.FullName } elseif ($rootfs) { $rootfs.FullName } else { throw 'No distro tarball in wsl\' }
$baked = $source

$existing = (wsl.exe -l -q 2>$null) -replace "`0", '' | Where-Object { $_.Trim() -eq $DistroName }
if ($existing) {
  Write-Host "== Distro $DistroName already registered, skipping import"
} else {
  Write-Host "== Importing $DistroName from $(Split-Path -Leaf $source)"
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  wsl.exe --import $DistroName $InstallDir $source --version 2
}

wsl.exe --set-default $DistroName
Write-Host ''
if ($source -eq $baked) {
  Write-Host "Done. $DistroName is ready with Git, Node, gh, and Claude Code preinstalled."
  Write-Host 'Default user is "dev". Set endpoint env in ~/.claude/settings.json inside the distro.'
} else {
  Write-Host "Done, but this was the raw rootfs. Run scripts/wsl-provision.sh inside the distro"
  Write-Host 'to install Git, Node, gh, and Claude Code from the linux\ folder.'
}
Write-Host 'In T3 Code: Settings > Sharing & access > pick the distro.'
