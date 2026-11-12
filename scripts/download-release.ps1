<#
.SYNOPSIS
  Downloads a release's assets into one folder, in one command, from any machine that can reach
  github.com. Uses the GitHub CLI if present, otherwise plain HTTPS (the repo is public, so no
  token is needed), through the system proxy with your Windows credentials.

  By default it fetches what a Windows install uses: the repo, SHA256SUMS.txt, the Windows apps,
  the Windows caches and the release's project page, about 4 GB. -Include wsl adds the Ubuntu
  distro and the WSL installer, -Include linux the Linux files, and -All everything (about
  10 GB). Before it starts, it checks the drive has room for what's left to fetch.
    .\scripts\download-release.ps1                          # latest release, Windows -> .\assets
    .\scripts\download-release.ps1 -Include wsl             # and WSL
    .\scripts\download-release.ps1 -Tag v1.0.4 -To D:\toolkit-assets -All
  Then: .\scripts\unpack-release.ps1 -From .\assets
#>
[CmdletBinding()]
param(
  [string]$Tag,
  [string]$To = (Join-Path (Get-Location) 'assets'),
  [string]$Repo = 'Real-Fruit-Snacks/agent-toolkit',
  [ValidateSet('wsl', 'linux')][string[]]$Include = @(),
  [switch]$All
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest's progress bar slows 5.1 to a crawl
# Windows PowerShell 5.1 can default to TLS 1.0, which GitHub refuses; and a proxy that wants a
# Windows sign-in gets this account's, as a browser would.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
if ([Net.WebRequest]::DefaultWebProxy) { [Net.WebRequest]::DefaultWebProxy.Credentials = [Net.CredentialCache]::DefaultNetworkCredentials }
New-Item -ItemType Directory -Force -Path $To | Out-Null
$To = (Resolve-Path $To).Path

$api = if ($Tag) { "https://api.github.com/repos/$Repo/releases/tags/$Tag" } else { "https://api.github.com/repos/$Repo/releases/latest" }
$rel = Invoke-RestMethod $api -Headers @{ 'User-Agent' = 'agent-toolkit' }

function Wanted($name) {
  if ($All) { return $true }
  if ($name -like 'wsl--*') { return $Include -contains 'wsl' }
  if ($name -like 'linux--*' -or $name -like 'caches--*-linux.zip') { return $Include -contains 'linux' }
  return $true   # the repo, SHA256SUMS.txt, the page, windows-- and the Windows caches
}
$assets = @($rel.assets | Where-Object { Wanted $_.name })
$skipped = @($rel.assets | Where-Object { -not (Wanted $_.name) })

# GitHub publishes a sha256 digest per asset; a file already here is kept only if its hash
# matches, so a same-size stale or truncated download is always replaced.
function Have($a) {
  $dest = Join-Path $To $a.name
  if (-not (Test-Path $dest)) { return $false }
  $want = if ($a.digest) { ($a.digest -replace '^sha256:', '') } else { $null }
  if ($want) { return (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -eq $want }
  return (Get-Item $dest).Length -eq $a.size
}
$todo = @($assets | Where-Object { -not (Have $_) })
$need = ($todo | Measure-Object size -Sum).Sum
$GiB = 1GB
Write-Host ("== {0}: {1} of {2} assets ({3:N2} GiB), {4} still to fetch ({5:N2} GiB)" -f $rel.tag_name, $assets.Count, $rel.assets.Count, (($assets | Measure-Object size -Sum).Sum / $GiB), $todo.Count, ($need / $GiB))
if ($skipped) { Write-Host ("   leaving out {0} ({1:N2} GiB) for WSL and Linux; add -Include wsl, -Include linux or -All for them" -f $skipped.Count, (($skipped | Measure-Object size -Sum).Sum / $GiB)) }

if (-not $To.StartsWith('\\')) {
  $drive = Get-PSDrive -Name $To.Substring(0, 1) -ErrorAction SilentlyContinue
  if ($drive -and $drive.Free -lt ($need + 512MB)) {
    throw ("{0} has {1:N1} GiB free, and this download needs {2:N1} GiB, then about as much again to unpack. Free some space, or pass -To on a bigger drive." -f $drive.Root, ($drive.Free / $GiB), ($need / $GiB))
  }
  if ($drive) { Write-Host ("   {0} has {1:N1} GiB free; unpacking needs about as much again as the download" -f $drive.Root, ($drive.Free / $GiB)) }
}

if ($todo.Count -and (Get-Command gh -ErrorAction SilentlyContinue)) {
  $patterns = @($todo | ForEach-Object { '--pattern'; $_.name })
  Write-Host "== gh release download $($rel.tag_name) ($($todo.Count) files)"
  & gh release download $rel.tag_name --repo $Repo --dir $To --clobber @patterns
  if ($LASTEXITCODE -ne 0) { throw 'gh release download failed' }
  $todo = @($todo | Where-Object { -not (Have $_) })
  if ($todo) { throw "gh left $($todo.Count) file(s) that don't match GitHub's digests: $(($todo.name) -join ', ')" }
}
foreach ($a in $todo) {
  $dest = Join-Path $To $a.name
  $want = if ($a.digest) { ($a.digest -replace '^sha256:', '') } else { $null }
  Write-Host "  get   $($a.name) ($([math]::Round($a.size/1MB)) MB)"
  for ($try = 1; $try -le 4; $try++) {
    try {
      Invoke-WebRequest $a.browser_download_url -OutFile $dest -Headers @{ 'User-Agent' = 'agent-toolkit' } -UseBasicParsing
      if ($want -and ((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -ne $want)) { throw "hash mismatch after download" }
      break
    }
    catch { if ($try -eq 4) { throw }; Write-Host "    retry $try ($($_.Exception.Message))"; Start-Sleep 10 }
  }
}
Write-Host ''
Write-Host "Done. Next: .\scripts\unpack-release.ps1 -From `"$To`""
