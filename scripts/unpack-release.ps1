<#
.SYNOPSIS
  Reverses package-release.ps1: takes a folder of downloaded release assets,
  verifies them against SHA256SUMS.txt, and restores the windows\ linux\ wsl\
  caches\ layout inside this repo checkout.
    .\scripts\unpack-release.ps1 -From C:\Downloads\agent-toolkit-assets
.PARAMETER SkipVerify
  Skip the SHA256 check (for example when SHA256SUMS.txt was not downloaded).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$From,
  [switch]$SkipVerify
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$sums = Join-Path $From 'SHA256SUMS.txt'
if (-not $SkipVerify) {
  if (-not (Test-Path $sums)) { throw "SHA256SUMS.txt not found in $From. Download it, or pass -SkipVerify." }
  $bad = 0; $checked = 0
  foreach ($line in Get-Content $sums) {
    if ($line -notmatch '^([0-9a-f]{64})\s+\*?(.+)$') { continue }
    $hash, $name = $Matches[1], $Matches[2].Trim()
    $p = Join-Path $From $name
    if (-not (Test-Path $p)) { Write-Host "  missing  $name"; continue }
    $checked++
    $actual = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $hash) { Write-Host "  BAD HASH $name"; $bad++ } else { Write-Host "  ok       $name" }
  }
  if ($bad -gt 0) { throw "$bad file(s) failed the SHA256 check. Re-download them." }
  Write-Host "Verified $checked file(s)."
}

# Rejoin assets that were split to stay under GitHub's 2 GiB limit: <name>.part1, .part2, ...
$groups = Get-ChildItem $From -File | Where-Object { $_.Name -match '^(.+)\.part(\d+)$' } | Group-Object { $_.Name -replace '\.part\d+$', '' }
foreach ($g in $groups) {
  $parts = $g.Group | Sort-Object { [int]($_.Name -replace '^.+\.part', '') }
  $nums = @($parts | ForEach-Object { [int]($_.Name -replace '^.+\.part', '') })
  for ($k = 0; $k -lt $nums.Count; $k++) { if ($nums[$k] -ne $k + 1) { throw "$($g.Name): part $($k + 1) is missing. Download every .part file." } }
  $target = Join-Path $From $g.Name
  Write-Host "  joining  $($g.Name) from $($parts.Count) parts"
  $outFs = [System.IO.File]::Create($target)
  try { foreach ($p in $parts) { $in = [System.IO.File]::OpenRead($p.FullName); try { $in.CopyTo($outFs, 8MB) } finally { $in.Dispose() } } } finally { $outFs.Dispose() }
  $side = Join-Path $From "$($g.Name).sha256"
  if (Test-Path $side) {
    $want = ((Get-Content $side -Raw).Trim() -split '\s+')[0].ToLower()
    $got = (Get-FileHash $target -Algorithm SHA256).Hash.ToLower()
    if ($got -ne $want) { Remove-Item $target -Force; throw "$($g.Name): joined file does not match its .sha256. Re-download the parts." }
    Write-Host "  ok       $($g.Name) (joined)"
  } elseif (-not $SkipVerify) { throw "$($g.Name).sha256 not found; download it to verify the joined file, or pass -SkipVerify." }
}

Get-ChildItem $From -File | ForEach-Object {
  if ($_.Name -match '^repo--.+\.zip$') {
    # the repo snapshot; this checkout already is the repo, so skip it here
    return
  }
  if ($_.Name -match '\.part\d+$' -or $_.Name -match '\.sha256$') { return }   # pieces and sidecars of joined assets
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
Write-Host 'Restored. Next: .\scripts\install-windows.ps1 (or setup-wsl.ps1 / install-linux.sh).'
