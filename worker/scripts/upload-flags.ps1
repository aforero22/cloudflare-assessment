param(
    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$')]
    [string]$Bucket = 'cf-assessment-flags',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $cache = Join-Path (Get-Location) '.flags-cache'
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    # Download only; the package includes the SVG set and MIT license.
    $version = if ($env:FLAG_ICONS_VERSION) { $env:FLAG_ICONS_VERSION } else { '7.5.0' }
    $archive = & npm.cmd pack "flag-icons@$version" --ignore-scripts --pack-destination $cache --silent
    if ($LASTEXITCODE -ne 0) { throw 'Flag package download failed' }
    & tar -xzf (Join-Path $cache ($archive | Select-Object -Last 1)) -C $cache
    if ($LASTEXITCODE -ne 0) { throw 'Flag package extraction failed' }
    Get-ChildItem -LiteralPath (Join-Path $cache 'package/flags/4x3') -Filter '*.svg' | ForEach-Object {
        if ($_.BaseName -cmatch '^[A-Za-z]{2}$') {
            $cc = $_.BaseName.ToLowerInvariant()
            $object = "$Bucket/flags/$cc.svg"
            if ($DryRun) {
                Write-Output "Would upload $($_.FullName) to $object (image/svg+xml)"
            } else {
                & npx.cmd wrangler r2 object put $object --file $_.FullName --content-type 'image/svg+xml' --remote
                if ($LASTEXITCODE -ne 0) { throw "Upload failed: $object" }
            }
        }
    }
} finally {
    Pop-Location
}
