param(
    [string]$GodotPath = 'godot',
    [Parameter(Mandatory)][string]$TemplatePath,
    [string]$OutputPath = '',
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process.ps1')
$buildPath = Join-Path $projectPath ('.godot/releases/build-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $buildPath 'source'
$package = Join-Path $buildPath 'package'
New-Item -ItemType Directory -Force $source, $package | Out-Null
if (-not $OutputPath) { $OutputPath = Join-Path $projectPath '.godot/releases/SynthwaveDrive-Windows64.zip' }
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force (Split-Path -Parent $OutputPath) | Out-Null
$templateDirectory = (Resolve-Path -LiteralPath $TemplatePath).Path
$template = Join-Path $templateDirectory 'windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $template)) { throw "Windows64 release template missing from $templateDirectory" }
if (-not (Test-Path -LiteralPath (Join-Path $templateDirectory 'windows_release_x86_64_console.exe'))) { throw "Windows64 console wrapper missing from $templateDirectory" }
if ((Get-Content -LiteralPath (Join-Path $templateDirectory 'version.txt') -Raw).Trim() -ne '4.6.1.stable') { throw 'Templates must be Godot 4.6.1 stable' }
$version = Invoke-BoundedProcess -Executable $GodotPath -Arguments @('--version') -LogPath (Join-Path $buildPath 'version') -TimeoutSeconds $TimeoutSeconds
if ($version.StdOut.Trim() -notmatch '^4\.6\.1\.stable') { throw 'Release builds require Godot 4.6.1 stable' }
# A fresh staged source makes the export independent of local editor caches.
foreach ($folder in @('scripts', 'scenes', 'shaders', 'config')) {
    Copy-Item -LiteralPath (Join-Path $projectPath $folder) -Destination $source -Recurse
}
foreach ($file in @('project.godot', 'logo.png')) { Copy-Item -LiteralPath (Join-Path $projectPath $file) -Destination $source }
New-Item -ItemType Directory (Join-Path $source 'tests') | Out-Null
Copy-Item -LiteralPath (Join-Path $projectPath 'tests/exported_release.gd') -Destination (Join-Path $source 'tests')
$preset = Get-Content -LiteralPath (Join-Path $projectPath 'export_presets.cfg') -Raw
$escapedTemplate = $template.Replace('\', '/').Replace('"', '\"')
$preset = $preset.Replace('custom_template/release=""', ('custom_template/release="' + $escapedTemplate + '"'))
Set-Content -LiteralPath (Join-Path $source 'export_presets.cfg') -Value $preset -Encoding UTF8
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
try {
    $env:APPDATA = Join-Path $buildPath 'appdata'
    $env:LOCALAPPDATA = Join-Path $buildPath 'localappdata'
    New-Item -ItemType Directory -Force $env:APPDATA, $env:LOCALAPPDATA | Out-Null
    foreach ($step in @('import', 'export')) {
        $log = Join-Path $buildPath ($step + '.log')
        $arguments = @('--headless', '--path', $source, '--log-file', $log)
        if ($step -eq 'import') { $arguments += @('--editor', '--quit') }
        else { $arguments += @('--export-release', 'Windows Desktop', (Join-Path $package 'SynthwaveDrive.exe')) }
        $result = Invoke-BoundedProcess -Executable $GodotPath -Arguments $arguments -LogPath $log -TimeoutSeconds $TimeoutSeconds
        if (-not (Test-Path -LiteralPath $log)) { throw "Build $step produced no log" }
        if (Select-String -LiteralPath $log -Pattern '^(SCRIPT ERROR:|ERROR:|WARNING:)' -Quiet) { throw "Build $step logged errors/warnings: $log" }
    }
}
finally { $env:APPDATA = $savedAppData; $env:LOCALAPPDATA = $savedLocalAppData }
foreach ($artifact in @('SynthwaveDrive.exe', 'SynthwaveDrive.pck', 'SynthwaveDrive.console.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $package $artifact))) { throw "Export missing $artifact" }
}
Copy-Item -LiteralPath (Join-Path $projectPath 'config/secret_mode.cfg') -Destination (Join-Path $package 'secret_mode.cfg')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RELEASE-README.md') -Destination (Join-Path $package 'README.md')
foreach ($notice in @('LICENSE', 'CHANGELOG.md')) {
    Copy-Item -LiteralPath (Join-Path $projectPath $notice) -Destination $package
}
New-Item -ItemType Directory (Join-Path $package 'docs') | Out-Null
foreach ($notice in @('BRANDING.md', 'local-event-setup.md')) {
    Copy-Item -LiteralPath (Join-Path $projectPath ('docs/' + $notice)) -Destination (Join-Path $package 'docs')
}
# Include Godot's license and third-party notices with the runtime.
foreach ($notice in @('GODOT-COPYRIGHT.txt', 'GODOT-LICENSE.txt')) {
    Copy-Item -LiteralPath (Join-Path $projectPath ('tools/' + $notice)) -Destination $package
}
& (Join-Path $PSScriptRoot 'verify-release.ps1') -PackagePath $package -TimeoutSeconds $TimeoutSeconds
$manifest = Get-ChildItem -LiteralPath $package -File -Recurse | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($package.Length + 1).Replace('\', '/')
    ((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()) + '  ' + $relative
}
Set-Content -LiteralPath (Join-Path $package 'SHA256SUMS.txt') -Value $manifest -Encoding ASCII
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $OutputPath -CompressionLevel Optimal -Force
# Verify the extracted ZIP, so the delivered artifact is what passed.
& (Join-Path $PSScriptRoot 'verify-release.ps1') -PackagePath $OutputPath -TimeoutSeconds $TimeoutSeconds
Write-Output "WINDOWS RELEASE PASS: $OutputPath"
Write-Output ('SHA256: ' + (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant())
