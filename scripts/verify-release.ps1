<#
.SYNOPSIS
  Proves a published release is internally consistent before anyone downloads it.
  GitHub records a SHA-256 digest for every release asset; this compares those
  digests against the SHA256SUMS.txt that is itself published on the release,
  and optionally against the local release\ folder.
    .\scripts\verify-release.ps1 -Tag v1.0.0
  Exit code 1 on any mismatch. Needs the GitHub CLI.
#>
[CmdletBinding()]
param(
  [string]$Tag,
  [string]$Repo = 'Real-Fruit-Snacks/agent-toolkit',
  [switch]$Local
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Tag) { $Tag = gh release view --repo $Repo --json tagName -q .tagName }

$assets = gh api "repos/$Repo/releases/tags/$Tag" -q '.assets[] | "\(.digest)|\(.name)|\(.size)"' | ForEach-Object {
  $d, $n, $s = $_ -split '\|'
  [pscustomobject]@{ name = $n; digest = ($d -replace '^sha256:', ''); size = [long]$s }
}
$sumsAsset = $assets | Where-Object name -eq 'SHA256SUMS.txt'
if (-not $sumsAsset) { throw "SHA256SUMS.txt is not on release $Tag" }

$tmp = Join-Path $env:TEMP "sums-$Tag.txt"
gh release download $Tag --repo $Repo --pattern 'SHA256SUMS.txt' --output $tmp --clobber | Out-Null
$sums = @{}
foreach ($line in Get-Content $tmp) { if ($line -match '^([0-9a-f]{64})\s+\*?(.+)$') { $sums[$Matches[2].Trim()] = $Matches[1] } }

$bad = 0
foreach ($a in $assets) {
  if ($a.name -eq 'SHA256SUMS.txt') { continue }
  if (-not $sums.ContainsKey($a.name)) { Write-Host "  NOT IN SUMS   $($a.name)"; $bad++; continue }
  if ($a.digest -ne $sums[$a.name]) { Write-Host "  DIGEST DIFF   $($a.name)"; $bad++ } else { Write-Host "  ok            $($a.name)" }
}
foreach ($n in $sums.Keys) { if (-not ($assets | Where-Object name -eq $n)) { Write-Host "  MISSING ASSET $n"; $bad++ } }

if ($Local) {
  Write-Host ''
  Write-Host '== local release\ folder vs published digests'
  foreach ($a in $assets) {
    $p = Join-Path $root "release\$($a.name)"
    if (-not (Test-Path $p)) { Write-Host "  no local      $($a.name)"; continue }
    $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $a.digest) { Write-Host "  LOCAL DIFF    $($a.name)"; $bad++ } else { Write-Host "  ok            $($a.name)" }
  }
}

Write-Host ''
if ($bad -eq 0) { Write-Host "Release $Tag is consistent: $($assets.Count) assets, digests match SHA256SUMS.txt." }
else { Write-Host "$bad problem(s). Re-upload the listed assets with --clobber, then re-run."; exit 1 }
