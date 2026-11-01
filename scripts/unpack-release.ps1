<#
.SYNOPSIS
  Reverses package-release.ps1: takes a folder of downloaded release assets and
  restores the windows\ linux\ wsl\ caches\ layout inside this repo checkout.
    .\scripts\unpack-release.ps1 -From C:\Downloads\agent-toolkit-assets
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$From)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Get-ChildItem $From -File | ForEach-Object {
  if ($_.Name -match '^(windows|linux|wsl)--(.+)$') {
    $dir, $name = $Matches[1], $Matches[2]
    $dest = if ($name -like 'claude-*') { Join-Path $dir 'claude-code' } else { $dir }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item $_.FullName (Join-Path $dest $name) -Force
  } elseif ($_.Name -match '^caches--(.+)\.zip$') {
    $dest = Join-Path 'caches' $Matches[1]
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Expand-Archive $_.FullName -DestinationPath $dest -Force
  }
}
Write-Host 'Restored. Verify with: Get-Content VERSIONS.md'
