<#
.SYNOPSIS
  Reverses package-release.ps1: takes a folder of downloaded release assets, verifies them
  against SHA256SUMS.txt, and restores the windows\ linux\ wsl\ caches\ layout inside this repo
  checkout. The release's project page goes to page\, to read offline.
    .\scripts\unpack-release.ps1 -From .\assets
  Assets left out of the download on purpose (the WSL and Linux ones, by default) are noted
  once, not treated as missing.
.PARAMETER Move
  Move the files instead of copying them, and delete each zip once it's unpacked, so a small
  disk (a VDI desktop's, say) doesn't hold the release twice. The download folder is used up.
.PARAMETER SkipVerify
  Skip the SHA256 check (for example when SHA256SUMS.txt was not downloaded).
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$From,
  [switch]$Move,
  [switch]$SkipVerify
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$repo = Split-Path -Parent $PSScriptRoot
$From = (Resolve-Path $From).Path

# what a Windows-only download leaves out, by design
function Optional($name) { $name -like 'wsl--*' -or $name -like 'linux--*' -or $name -like 'caches--*-linux.zip' -or $name -like 'repo--*' }

$sums = Join-Path $From 'SHA256SUMS.txt'
if (-not $SkipVerify) {
  if (-not (Test-Path $sums)) { throw "SHA256SUMS.txt not found in $From. Download it, or pass -SkipVerify." }
  $bad = 0; $checked = 0; $leftOut = @(); $missing = @()
  foreach ($line in Get-Content $sums) {
    if ($line -notmatch '^([0-9a-f]{64})\s+\*?(.+)$') { continue }
    $hash, $name = $Matches[1], $Matches[2].Trim()
    $p = Join-Path $From $name
    if (-not (Test-Path $p)) { if (Optional $name) { $leftOut += $name } else { $missing += $name; Write-Host "  missing  $name" }; continue }
    $checked++
    $actual = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $hash) { Write-Host "  BAD HASH $name"; $bad++ } else { Write-Host "  ok       $name" }
  }
  if ($bad -gt 0) { throw "$bad file(s) failed the SHA256 check. Re-download them." }
  Write-Host "Verified $checked file(s)."
  if ($leftOut) { Write-Host "  not downloaded: $($leftOut.Count) file(s) for WSL, Linux or a machine without a clone, which a Windows install doesn't use" }
  if ($missing) { Write-Warning "$($missing.Count) file(s) a Windows install uses weren't downloaded; run download-release.ps1 again to fetch them." }
}

function Expand-Into([string]$Zip, [string]$Dest) {
  # Entry by entry: much faster than Expand-Archive in Windows PowerShell 5.1, overwrites what
  # an earlier run left, and refuses any entry that would land outside $Dest.
  $destFull = [IO.Path]::GetFullPath($Dest).TrimEnd('\') + '\'
  [void][IO.Directory]::CreateDirectory($destFull)
  $z = [IO.Compression.ZipFile]::OpenRead($Zip)
  try {
    foreach ($e in $z.Entries) {
      if (-not $e.Name) { continue }   # a folder entry
      $t = [IO.Path]::GetFullPath((Join-Path $destFull ($e.FullName -replace '/', '\')))
      if (-not $t.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) { throw "$(Split-Path -Leaf $Zip): entry $($e.FullName) points outside $Dest" }
      [void][IO.Directory]::CreateDirectory((Split-Path $t))
      [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $t, $true)
    }
  } finally { $z.Dispose() }
}
function Put([string]$Src, [string]$Dest) { if ($Move) { Move-Item $Src $Dest -Force } else { Copy-Item $Src $Dest -Force } }

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
  if ($Move) { $parts | Remove-Item -Force }
}

Get-ChildItem $From -File | ForEach-Object {
  if ($_.Name -match '^repo--.+\.zip$') { return }   # the repo snapshot; this checkout already is the repo
  if ($_.Name -match '\.part\d+$' -or $_.Name -match '\.sha256$') { return }   # pieces and sidecars of joined assets
  if ($_.Name -match '^(windows|linux|wsl)--(.+)$') {
    $dir, $name = $Matches[1], $Matches[2]
    $dest = if ($name -like 'claude-*') { Join-Path (Join-Path $repo $dir) 'claude-code' } else { Join-Path $repo $dir }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Put $_.FullName (Join-Path $dest $name)
  } elseif ($_.Name -match '^caches--(.+)\.zip$') {
    Write-Host "  unzipping $($_.Name)"
    Expand-Into $_.FullName (Join-Path $repo "caches\$($Matches[1])")
    if ($Move) { Remove-Item $_.FullName -Force }
  } elseif ($_.Name -match '^page--.+\.zip$') {
    # the release's project page, as published with it: page\index.html opens in a browser
    $page = Join-Path $repo 'page'
    if (Test-Path $page) { Remove-Item $page -Recurse -Force }
    Expand-Into $_.FullName $page
    if ($Move) { Remove-Item $_.FullName -Force }
    Write-Host "  page     $page\index.html"
  }
}
Write-Host 'Restored. Next: .\scripts\install-windows.ps1 (or setup-wsl.ps1 / install-linux.sh).'
