<#
.SYNOPSIS
  Packages the large folders into release assets under release\ and prints the
  gh command to upload them. Does NOT create or push anything by itself.

  Folders with many files (caches) are zipped so the release has one asset per
  logical unit. Single installers are copied as-is. GitHub caps each asset at
  2 GB, which nothing here approaches.
#>
[CmdletBinding()]
param([string]$Tag)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$out = Join-Path $root 'release'
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

if (-not $Tag) {
  $t3 = (Get-ChildItem windows -Filter 'T3-Code-*-x64.exe' | Select-Object -First 1).Name
  if ($t3 -match 'T3-Code-(.+)-x64\.exe') { $Tag = "v$($Matches[1])-1" } else { throw 'Pass -Tag' }
}

# single-file assets, prefixed by folder so the release listing stays readable
foreach ($dir in 'windows','linux','wsl') {
  Get-ChildItem $dir -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $out "$dir--$($_.Name)") }
}
Get-ChildItem windows\claude-code,linux\claude-code -File | Where-Object { $_.Name -like 'claude-*' } | ForEach-Object {
  $side = if ($_.DirectoryName -like '*windows*') { 'windows' } else { 'linux' }
  Copy-Item $_.FullName (Join-Path $out "$side--$($_.Name)")
}

# zipped cache bundles
function Zip($src, $name) {
  if (-not (Test-Path $src)) { return }
  Write-Host "  zipping $src"
  Compress-Archive -Path (Join-Path $src '*') -DestinationPath (Join-Path $out $name) -CompressionLevel Optimal
}
Zip caches\t3-tools-win       'caches--t3-tools-win.zip'
Zip caches\t3-tools-linux     'caches--t3-tools-linux.zip'
Zip caches\playwright-browsers 'caches--playwright-browsers.zip'
Zip caches\npm                'caches--npm.zip'
Zip caches\t3-userdata        'caches--t3-userdata.zip'

Get-ChildItem $out | ForEach-Object { "$($_.Name)`t$([math]::Round($_.Length/1MB)) MB" }
Get-ChildItem $out -File | Get-FileHash -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLower())  $(Split-Path -Leaf $_.Path)" } | Set-Content (Join-Path $out 'SHA256SUMS.txt')

Write-Host ''
Write-Host 'To publish when ready (run yourself):'
Write-Host "  gh release create $Tag --title `"$Tag`" --notes-file VERSIONS.md release\*"
Write-Host ''
Write-Host 'On the destination machine, scripts\unpack-release.ps1 puts the assets back into the folder layout.'
