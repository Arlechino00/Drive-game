param(
    [Parameter(Mandatory)][string]$PackagePath,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process.ps1')
$validationPath = Join-Path $projectPath ('.godot/validation/export-' + [guid]::NewGuid().ToString('N'))
$package = Join-Path $validationPath 'package'
New-Item -ItemType Directory -Force $package | Out-Null
if (Test-Path -LiteralPath $PackagePath -PathType Container) {
    Copy-Item -Path (Join-Path $PackagePath '*') -Destination $package -Recurse
}
else { Expand-Archive -LiteralPath $PackagePath -DestinationPath $package }
foreach ($required in @('SynthwaveDrive.exe', 'SynthwaveDrive.pck', 'SynthwaveDrive.console.exe', 'secret_mode.cfg', 'README.md', 'LICENSE', 'GODOT-LICENSE.txt', 'GODOT-COPYRIGHT.txt', 'docs/BRANDING.md', 'docs/local-event-setup.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $package $required) -PathType Leaf)) { throw "Package missing $required" }
}
$manifestPath = Join-Path $package 'SHA256SUMS.txt'
if (Test-Path -LiteralPath $manifestPath) {
    foreach ($line in Get-Content -LiteralPath $manifestPath) {
        if ($line -notmatch '^([a-f0-9]{64})  (.+)$') { throw 'Invalid package hash manifest' }
        $expected = $Matches[1]
        $relative = $Matches[2]
        $target = [IO.Path]::GetFullPath((Join-Path $package $relative))
        if (-not $target.StartsWith($package + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package manifest path escapes package' }
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw "Package hash mismatch: $relative" }
    }
}
$executable = Join-Path $package 'SynthwaveDrive.console.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Package lacks the Windows console wrapper' }
$external = Join-Path $package 'secret_mode.cfg'
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
try {
    foreach ($scenario in @('external', 'invalid', 'fallback')) {
        $env:APPDATA = Join-Path $validationPath ($scenario + '/appdata')
        $env:LOCALAPPDATA = Join-Path $validationPath ($scenario + '/localappdata')
        New-Item -ItemType Directory -Force $env:APPDATA, $env:LOCALAPPDATA | Out-Null
        $extra = @()
        if ($scenario -eq 'external') {
            Set-Content -LiteralPath $external -Encoding ASCII -Value "[secret_mode]`naccess_code=`"RELEASE-ACCESS`"`nresume_code=`"RELEASE-RESUME`""
        }
        elseif ($scenario -eq 'invalid') {
            Set-Content -LiteralPath $external -Encoding ASCII -Value "[secret_mode]`naccess_code=42`nresume_code=42"
            $extra = @('--invalid-external')
        }
        else {
            Remove-Item -LiteralPath $external
            $extra = @('--bundled-fallback')
        }
        $log = Join-Path $validationPath ($scenario + '.log')
        $result = Invoke-BoundedProcess -Executable $executable -Arguments (@('--headless', '--log-file', $log, '--', '--verify-release') + $extra) -LogPath $log -TimeoutSeconds $TimeoutSeconds
        if (-not (Test-Path -LiteralPath $log)) { throw "Export scenario $scenario produced no log" }
        if (Select-String -LiteralPath $log -Pattern '^(SCRIPT ERROR:|ERROR:|WARNING:)' -Quiet) { throw "Export scenario $scenario logged errors/warnings: $log" }
        if (-not (Select-String -LiteralPath $log -Pattern '^EXPORTED RELEASE PASS:' -Quiet)) { throw "Export scenario $scenario did not finish verification: $log" }
        Write-Output "Export verified: $scenario"
    }
}
finally {
    $env:APPDATA = $savedAppData
    $env:LOCALAPPDATA = $savedLocalAppData
}
Write-Output "EXPORTED PACKAGE PASS. Isolated logs: $validationPath"
