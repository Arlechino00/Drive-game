param([string]$Destination = '')
$ErrorActionPreference = 'Stop'
if (-not $Destination) { $Destination = Join-Path (Split-Path -Parent $PSScriptRoot) '.godot/tools' }
$Destination = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Force $Destination | Out-Null
$baseUrl = 'https://github.com/godotengine/godot-builds/releases/download/4.6.1-stable/'
# Official release asset SHA256 values; changing engine version requires review.
$assets = @(
    @{ Name = 'Godot_v4.6.1-stable_win64.exe.zip'; Hash = '088da0457e2d1f7f8a45e6d4605a42b756ea33b9ccd75059bdbc01bb31c2b40d' },
    @{ Name = 'Godot_v4.6.1-stable_export_templates.tpz'; Hash = 'e6d372afd4fdfaae9571eb5e3568afcd96ce6db9a569244034154faf0ac69875' }
)
Add-Type -AssemblyName System.IO.Compression.FileSystem
foreach ($asset in $assets) {
    $archivePath = Join-Path $Destination $asset.Name
    if (-not (Test-Path -LiteralPath $archivePath)) {
        & curl.exe --location --fail --retry 2 --max-time 900 --output $archivePath ($baseUrl + $asset.Name)
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $($asset.Name)" }
    }
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $asset.Hash) { throw "Official SHA256 mismatch: $archivePath" }
    if ($asset.Name.EndsWith('.zip')) { Expand-Archive -LiteralPath $archivePath -DestinationPath $Destination -Force }
    else {
        $templateDirectory = Join-Path $Destination '4.6.1.stable'
        New-Item -ItemType Directory -Force $templateDirectory | Out-Null
        $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
        try {
            foreach ($name in @('windows_release_x86_64.exe', 'windows_release_x86_64_console.exe', 'windows_debug_x86_64.exe', 'windows_debug_x86_64_console.exe', 'version.txt')) {
                $entry = $archive.GetEntry('templates/' + $name)
                if (-not $entry) { throw "Official archive missing $name" }
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $templateDirectory $name), $true)
            }
        }
        finally { $archive.Dispose() }
    }
}
Write-Output "Godot 4.6.1 and Windows64 templates verified in $Destination"
