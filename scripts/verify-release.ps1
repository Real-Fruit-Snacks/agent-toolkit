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

# Look the release up from the list rather than /releases/tags/<tag>: that endpoint
# cannot see drafts, whose git tag only exists once they are published.
# Parse the JSON in PowerShell; a jq string with inner quotes gets mangled by Windows PowerShell 5.1.
$rel = (gh api "repos/$Repo/releases?per_page=30" | ConvertFrom-Json) | Where-Object { $_.tag_name -eq $Tag } | Select-Object -First 1
if (-not $rel) { throw "no release (draft or published) with tag $Tag" }
$assets = $rel.assets | ForEach-Object {
  [pscustomobject]@{ name = $_.name; digest = ("$($_.digest)" -replace '^sha256:', ''); size = [long]$_.size }
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
  # The project page is rendered from the published release, so it's uploaded after SHA256SUMS.txt
  # is fixed and can't be in it. It still needs the digest GitHub records for every upload.
  if ($a.name -like 'page--*.zip' -and -not $sums.ContainsKey($a.name)) {
    if ($a.digest -match '^[0-9a-f]{64}$') { Write-Host "  page          $($a.name) (published after the sums; GitHub's digest $($a.digest.Substring(0, 12)))" } else { Write-Host "  NO DIGEST     $($a.name)"; $bad++ }
    continue
  }
  if (-not $sums.ContainsKey($a.name)) { Write-Host "  NOT IN SUMS   $($a.name)"; $bad++; continue }
  if ($a.digest -ne $sums[$a.name]) { Write-Host "  DIGEST DIFF   $($a.name)"; $bad++ } else { Write-Host "  ok            $($a.name)" }
}
foreach ($n in $sums.Keys) { if (-not ($assets | Where-Object name -eq $n)) { Write-Host "  MISSING ASSET $n"; $bad++ } }

if ($Local) {
  Write-Host ''
  Write-Host '== local release\ folder vs published digests'
  foreach ($a in $assets) {
    $p = Join-Path (Join-Path $root 'release') $a.name
    if (-not (Test-Path $p)) { Write-Host "  no local      $($a.name)"; continue }
    $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $a.digest) { Write-Host "  LOCAL DIFF    $($a.name)"; $bad++ } else { Write-Host "  ok            $($a.name)" }
  }
}

Write-Host ''
$n = @($assets | Where-Object { $_.name -notlike 'page--*.zip' }).Count
if ($bad -eq 0) { Write-Host "Release $Tag is consistent: $n assets, digests match SHA256SUMS.txt." }
else { Write-Host "$bad problem(s). Re-upload the listed assets with --clobber, then re-run."; exit 1 }
