$projectRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $projectRoot)
$readme = Join-Path $repoRoot 'README.md'
$changelog = Join-Path $projectRoot 'assets\CHANGELOG.md'

Copy-Item -Path $readme -Destination $changelog -Force
Write-Host "Synced $readme -> $changelog"
