<#
.SYNOPSIS
  Builds wsl\ubuntu-dev.tar.gz on a machine WITH internet: imports the raw Ubuntu
  rootfs into a temporary distro, runs wsl-provision.sh inside it (apt + the
  toolkit's linux/ and caches/ folders), exports the result, and removes the
  temporary distro.
#>
[CmdletBinding()]
param(
  [string]$TempDistro = 'agent-toolkit-bake',
  [string]$DevUser = 'dev'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$wsl  = Join-Path $root 'wsl'
$rootfs = Get-ChildItem $wsl -Filter 'ubuntu-*-wsl-amd64-*.rootfs.tar.gz' | Select-Object -First 1
if (-not $rootfs) { throw 'Ubuntu rootfs not found in wsl\' }
# gzip keeps the asset under GitHub's 2 GB per-file cap; wsl --import reads .tar.gz directly
$out = Join-Path $wsl 'ubuntu-dev.tar.gz'
$tmpDir = Join-Path $env:TEMP "wsl-$TempDistro"

# repo path as seen from inside WSL
$drive = $root.Substring(0,1).ToLower()
$wslRoot = "/mnt/$drive" + ($root.Substring(2) -replace '\\', '/')

$existing = (wsl.exe -l -q 2>$null) -replace "`0", '' | Where-Object { $_.Trim() -eq $TempDistro }
if ($existing) { wsl.exe --unregister $TempDistro | Out-Null }

Write-Host "== Importing $($rootfs.Name) as $TempDistro"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
wsl.exe --import $TempDistro $tmpDir $rootfs.FullName --version 2
if ($LASTEXITCODE -ne 0) { throw 'wsl --import failed' }

Write-Host '== Provisioning (this apt-installs and copies the toolkit; a few minutes)'
wsl.exe -d $TempDistro -u root -- bash -lc "bash '$wslRoot/scripts/wsl-provision.sh' '$wslRoot' '$DevUser'"
if ($LASTEXITCODE -ne 0) { throw 'provision failed' }

Write-Host '== Cleaning apt caches and shutting down'
wsl.exe -d $TempDistro -u root -- bash -lc 'apt-get clean; rm -rf /var/lib/apt/lists/* /tmp/*; history -c' | Out-Null
wsl.exe --terminate $TempDistro | Out-Null

Write-Host "== Exporting to $out"
if (Test-Path $out) { Remove-Item $out -Force }
Remove-Item (Join-Path $wsl 'ubuntu-dev.tar') -Force -ErrorAction SilentlyContinue
wsl.exe --export $TempDistro $out --format tar.gz
if ($LASTEXITCODE -ne 0) { throw 'wsl --export failed' }

Write-Host '== Removing temporary distro'
wsl.exe --unregister $TempDistro | Out-Null
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue

$size = [math]::Round((Get-Item $out).Length / 1MB)
Write-Host "Done: $out ($size MB)"
