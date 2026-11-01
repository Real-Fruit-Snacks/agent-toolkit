<#
.SYNOPSIS
  Reads the tool versions a T3 Code build expects (headless Chrome, agent-device,
  expo-device-hub, cloudflared) out of the downloaded win32 server zip and compares
  them with what is staged in caches\. With -Fix it downloads/installs the missing
  versions (needs internet) and removes stale ones.

  T3 pins these per build. If the cache does not match, T3 ignores it and tries to
  download on first use, which fails offline.
#>
[CmdletBinding()]
param([switch]$Fix)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$zip = Get-ChildItem windows -Filter 't3-*-win32-x64.zip' | Select-Object -First 1
if (-not $zip) { throw 'windows\t3-*-win32-x64.zip not found' }
$tmp = Join-Path $env:TEMP 't3-pins'
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
Expand-Archive $zip.FullName -DestinationPath $tmp
# The server bundle is compiled into t3.exe (single-file executable), so scan
# every large file as Latin-1 text rather than only .js files.
$latin1 = [System.Text.Encoding]::GetEncoding(28591)
$bundle = Get-ChildItem $tmp -Recurse -File | Where-Object { $_.Length -gt 5MB }
$text = ($bundle | ForEach-Object { $latin1.GetString([System.IO.File]::ReadAllBytes($_.FullName)) }) -join "`n"
Remove-Item $tmp -Recurse -Force

$want = [ordered]@{}
if ($text -match 'chrome-for-testing-public[\s\S]{0,400}?VERSION = "(\d+\.\d+\.\d+\.\d+)"' -or $text -match 'VERSION = "(1\d\d\.\d+\.\d+\.\d+)"') { $want['chrome-headless-shell'] = $Matches[1] }
if ($text -match '"agent-device":\s*"(\d+\.\d+\.\d+)"')        { $want['agent-device'] = $Matches[1] }
if ($text -match '"expo-device-hub":\s*"([0-9A-Za-z.\-]+)"')   { $want['expo-device-hub'] = $Matches[1] }
if ($text -match 'cloudflared/releases/download/([\d.]+)/')    { $want['cloudflared'] = $Matches[1] }

Write-Host "Build $($zip.Name) expects:"
$want.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-22} {1}" -f $_.Key, $_.Value) }

function Have($tool) {
  $d = Join-Path 'caches\t3-tools-win' $tool
  if (-not (Test-Path $d)) { return @() }
  Get-ChildItem $d -Recurse -Directory | Where-Object { $_.Name -match '^\d' } | ForEach-Object { $_.Name }
}

$ok = $true
foreach ($tool in 'chrome-headless-shell','agent-device','expo-device-hub') {
  $v = $want[$tool]; if (-not $v) { continue }
  $have = Have $tool
  if ($have -contains $v) { Write-Host "  ok    $tool $v"; continue }
  $ok = $false
  Write-Host "  MISS  $tool $v (have: $($have -join ', '))"
  if (-not $Fix) { continue }
  switch ($tool) {
    'chrome-headless-shell' {
      $dest = "caches\t3-tools-win\chrome-headless-shell\win64\$v"
      $z = Join-Path $env:TEMP "chs-$v.zip"
      curl.exe -fsSL -o $z "https://storage.googleapis.com/chrome-for-testing-public/$v/win64/chrome-headless-shell-win64.zip"
      Expand-Archive $z -DestinationPath "$dest.tmp" -Force
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      Move-Item "$dest.tmp\chrome-headless-shell-win64" $dest; Remove-Item "$dest.tmp" -Recurse -Force; Remove-Item $z
      Get-ChildItem caches\t3-tools-linux\chrome-headless-shell\linux64 -ErrorAction SilentlyContinue | Remove-Item -Force
      New-Item -ItemType Directory -Force -Path caches\t3-tools-linux\chrome-headless-shell\linux64 | Out-Null
      curl.exe -fsSL -o "caches\t3-tools-linux\chrome-headless-shell\linux64\chrome-headless-shell-linux64-$v.zip" "https://storage.googleapis.com/chrome-for-testing-public/$v/linux64/chrome-headless-shell-linux64.zip"
    }
    default {
      $dest = "caches\t3-tools-win\$tool\$v"
      New-Item -ItemType Directory -Force -Path $dest | Out-Null
      Set-Content (Join-Path $dest 'package.json') "{`n  `"dependencies`": {`n    `"$tool`": `"^$v`"`n  }`n}`n" -NoNewline
      Push-Location $dest
      npm install --no-audit --no-fund --omit=dev "$tool@$v" | Out-Null
      if ($LASTEXITCODE -eq 0) { New-Item -ItemType File -Path '.install-complete' -Force | Out-Null }
      Pop-Location
      Get-ChildItem caches\npm -Filter "$tool-*.tgz" -ErrorAction SilentlyContinue | Remove-Item -Force
      Push-Location caches\npm; npm pack "$tool@$v" | Out-Null; Pop-Location
    }
  }
  # drop stale versions of this tool
  Get-ChildItem "caches\t3-tools-win\$tool" -Recurse -Directory | Where-Object { $_.Name -match '^\d' -and $_.Name -ne $v } | Remove-Item -Recurse -Force
  Write-Host "  fixed $tool $v"
}
if ($ok) { Write-Host 'All pins satisfied.' } elseif (-not $Fix) { Write-Host 'Re-run with -Fix on a connected machine.'; exit 1 }
