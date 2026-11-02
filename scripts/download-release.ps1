<#
.SYNOPSIS
  Downloads every asset of a release into one folder, in one command, from any
  machine that can reach github.com. Uses the GitHub CLI if present, otherwise
  plain Invoke-WebRequest (the repo is public, so no token is needed).
    .\scripts\download-release.ps1                     # latest release -> .\assets
    .\scripts\download-release.ps1 -Tag v1.0.0 -To D:\toolkit-assets
  Then: .\scripts\unpack-release.ps1 -From .\assets
#>
[CmdletBinding()]
param(
  [string]$Tag,
  [string]$To = (Join-Path (Get-Location) 'assets'),
  [string]$Repo = 'Real-Fruit-Snacks/agent-toolkit'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $To | Out-Null

if (Get-Command gh -ErrorAction SilentlyContinue) {
  $args_ = @('release', 'download', '--repo', $Repo, '--dir', $To, '--clobber')
  if ($Tag) { $args_ = @('release', 'download', $Tag) + $args_[2..($args_.Length - 1)] }
  Write-Host "== gh $($args_ -join ' ')"
  & gh @args_
  if ($LASTEXITCODE -ne 0) { throw 'gh release download failed' }
} else {
  $api = if ($Tag) { "https://api.github.com/repos/$Repo/releases/tags/$Tag" } else { "https://api.github.com/repos/$Repo/releases/latest" }
  $rel = Invoke-RestMethod $api -Headers @{ 'User-Agent' = 'agent-toolkit' }
  Write-Host "== $($rel.tag_name): $($rel.assets.Count) assets"
  $ProgressPreference = 'SilentlyContinue'
  # GitHub publishes a sha256 digest per asset; an existing file is kept only if its hash matches,
  # so a same-size stale or truncated download is always replaced.
  foreach ($a in $rel.assets) {
    $dest = Join-Path $To $a.name
    $want = if ($a.digest) { ($a.digest -replace '^sha256:', '') } else { $null }
    if (Test-Path $dest) {
      $ok = if ($want) { (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -eq $want } else { (Get-Item $dest).Length -eq $a.size }
      if ($ok) { Write-Host "  have  $($a.name)"; continue }
      Write-Host "  stale $($a.name), replacing"
    }
    Write-Host "  get   $($a.name) ($([math]::Round($a.size/1MB)) MB)"
    for ($try = 1; $try -le 4; $try++) {
      try {
        Invoke-WebRequest $a.browser_download_url -OutFile $dest -Headers @{ 'User-Agent' = 'agent-toolkit' }
        if ($want -and ((Get-FileHash $dest -Algorithm SHA256).Hash.ToLower() -ne $want)) { throw "hash mismatch after download" }
        break
      }
      catch { if ($try -eq 4) { throw }; Write-Host "    retry $try ($($_.Exception.Message))"; Start-Sleep 10 }
    }
  }
}
Write-Host ''
Write-Host "Done. Next: .\scripts\unpack-release.ps1 -From `"$To`""
