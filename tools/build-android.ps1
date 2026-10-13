param(
    [string]$GodotPath = 'godot',
    [string]$TemplatePath = '',
    [string]$AndroidSdkPath = '',
    [Parameter(Mandatory)][string]$JavaSdkPath,
    [string]$OutputPath = '',
    [switch]$IncludeEmulatorArchitecture,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 180
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'process.ps1')
if (-not $AndroidSdkPath) { $AndroidSdkPath = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
if (-not $TemplatePath) { $TemplatePath = Join-Path $projectPath '.godot/tools/4.6.1.stable' }
if (-not $OutputPath) { $OutputPath = Join-Path $projectPath '.godot/releases/Android/SynthwaveDrive.apk' }
$AndroidSdkPath = (Resolve-Path -LiteralPath $AndroidSdkPath).Path
$JavaSdkPath = (Resolve-Path -LiteralPath $JavaSdkPath).Path
$TemplatePath = [IO.Path]::GetFullPath($TemplatePath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$java = Join-Path $JavaSdkPath 'bin/java.exe'
$keytool = Join-Path $JavaSdkPath 'bin/keytool.exe'
$buildTools = Join-Path $AndroidSdkPath 'build-tools/35.0.1'
foreach ($required in @($java, $keytool, (Join-Path $AndroidSdkPath 'platform-tools/adb.exe'),
    (Join-Path $buildTools 'aapt.exe'), (Join-Path $buildTools 'lib/apksigner.jar'),
    (Join-Path $buildTools 'zipalign.exe'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Android build prerequisite missing: $required" }
}

# Extract only the matching Android template, using the previously cached official archive.
# SHA512 is from Godot's 4.6.1-stable release SHA512-SUMS.txt; no download or global install.
$template = Join-Path $TemplatePath 'android_debug.apk'
if (-not (Test-Path -LiteralPath $template)) {
    $archivePath = Join-Path $projectPath '.godot/tools/Godot_v4.6.1-stable_export_templates.tpz'
    if (-not (Test-Path -LiteralPath $archivePath)) { throw "Supply Godot 4.6.1 templates with -TemplatePath, or cache the official archive at $archivePath" }
    $officialHash = 'd80001711c07973b1fd3e88077ba99644e19db7c9e52627e16f38a2937879f809f94dbd8493936fb8204908bbc57a521d41173dce5208061fe4c99772490c541'
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA512).Hash.ToLowerInvariant() -ne $officialHash) { throw 'Cached export template archive does not match the official Godot 4.6.1 SHA512 checksum' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force $TemplatePath | Out-Null
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        foreach ($name in @('android_debug.apk', 'version.txt')) {
            $entry = $archive.GetEntry('templates/' + $name)
            if (-not $entry) { throw "Cached archive is missing $name" }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $TemplatePath $name), $true)
        }
    }
    finally { $archive.Dispose() }
}
if ((Get-Content -LiteralPath (Join-Path $TemplatePath 'version.txt') -Raw).Trim() -ne '4.6.1.stable') { throw 'Android templates must be Godot 4.6.1 stable' }

$buildPath = Join-Path $projectPath ('.godot/releases/android-build-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $buildPath 'source'
New-Item -ItemType Directory -Force $source, (Split-Path -Parent $OutputPath) | Out-Null
$version = Invoke-BoundedProcess -Executable $GodotPath -Arguments @('--version') -LogPath (Join-Path $buildPath 'version') -TimeoutSeconds $TimeoutSeconds
if ($version.StdOut.Trim() -notmatch '^4\.6\.1\.stable') { throw 'Android builds require Godot 4.6.1 stable' }
$javaVersion = Invoke-BoundedProcess -Executable $java -Arguments @('-version') -LogPath (Join-Path $buildPath 'java-version') -TimeoutSeconds $TimeoutSeconds
if ($javaVersion.StdErr -notmatch 'version "17\.') { throw 'Use JDK 17 for this Android build' }
foreach ($folder in @('scripts', 'scenes', 'shaders', 'config', 'localization')) {
    Copy-Item -LiteralPath (Join-Path $projectPath $folder) -Destination $source -Recurse
}
foreach ($file in @('project.godot', 'logo.png')) { Copy-Item -LiteralPath (Join-Path $projectPath $file) -Destination $source }
New-Item -ItemType Directory (Join-Path $source 'tests'), (Join-Path $source 'runtime-notices') | Out-Null
Copy-Item -LiteralPath (Join-Path $projectPath 'tests/exported_release.gd') -Destination (Join-Path $source 'tests')
foreach ($notice in @('GODOT-COPYRIGHT.txt', 'GODOT-LICENSE.txt')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $notice) -Destination (Join-Path $source 'runtime-notices')
}
Copy-Item -LiteralPath (Join-Path $projectPath 'LICENSE') -Destination (Join-Path $source 'runtime-notices/LICENSE.txt')
$preset = Get-Content -LiteralPath (Join-Path $projectPath 'export_presets.cfg') -Raw
$androidIndex = $preset.IndexOf('[preset.1]')
if ($androidIndex -lt 0) { throw 'Android export preset is missing' }
$androidPreset = $preset.Substring($androidIndex).Replace('[preset.1', '[preset.0')
$androidPreset = $androidPreset.Replace('custom_template/debug=""', ('custom_template/debug="' + $template.Replace('\', '/') + '"'))
if ($IncludeEmulatorArchitecture) { $androidPreset = $androidPreset.Replace('architectures/x86_64=false', 'architectures/x86_64=true') }
Set-Content -LiteralPath (Join-Path $source 'export_presets.cfg') -Value $androidPreset -Encoding UTF8

# Persist only a local Android test key, so successive test APKs can upgrade each other.
# The standard Android debug password is public and is never a production signing key.
$debugKey = Join-Path $projectPath '.godot/tools/android-debug.keystore'
if (-not (Test-Path -LiteralPath $debugKey)) {
    Invoke-BoundedProcess -Executable $keytool -Arguments @('-genkeypair', '-noprompt', '-keystore', $debugKey,
        '-storepass', 'android', '-alias', 'androiddebugkey', '-keypass', 'android', '-keyalg', 'RSA', '-keysize', '2048',
        '-validity', '10000', '-dname', 'CN=Android Debug,O=Android,C=US') -LogPath (Join-Path $buildPath 'debug-key') -TimeoutSeconds $TimeoutSeconds | Out-Null
}
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
$savedJavaHome = $env:JAVA_HOME
try {
    $env:APPDATA = Join-Path $buildPath 'appdata'
    $env:LOCALAPPDATA = Join-Path $buildPath 'localappdata'
    $env:JAVA_HOME = $JavaSdkPath
    $editorDirectory = Join-Path $env:APPDATA 'Godot'
    New-Item -ItemType Directory -Force $editorDirectory, $env:LOCALAPPDATA | Out-Null
    $editorSettings = @"
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/java_sdk_path = "$($JavaSdkPath.Replace('\', '/'))"
export/android/android_sdk_path = "$($AndroidSdkPath.Replace('\', '/'))"
export/android/debug_keystore = "$($debugKey.Replace('\', '/'))"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
export/android/shutdown_adb_on_exit = false
"@
    Set-Content -LiteralPath (Join-Path $editorDirectory 'editor_settings-4.6.tres') -Value $editorSettings -Encoding UTF8
    foreach ($step in @('import', 'export')) {
        $log = Join-Path $buildPath ($step + '.log')
        $arguments = @('--headless', '--path', $source, '--log-file', $log)
        if ($step -eq 'import') { $arguments += @('--editor', '--quit') }
        else { $arguments += @('--export-debug', 'Android', $OutputPath) }
        Invoke-BoundedProcess -Executable $GodotPath -Arguments $arguments -LogPath $log -TimeoutSeconds $TimeoutSeconds | Out-Null
        if (-not (Test-Path -LiteralPath $log)) { throw "Android $step produced no log" }
        if (Select-String -LiteralPath $log -Pattern '^(SCRIPT ERROR:|ERROR:|WARNING:)' -Quiet) { throw "Android $step logged errors/warnings: $log" }
    }
}
finally { $env:APPDATA = $savedAppData; $env:LOCALAPPDATA = $savedLocalAppData; $env:JAVA_HOME = $savedJavaHome }

$signature = Invoke-BoundedProcess -Executable $java -Arguments @('-jar', (Join-Path $buildTools 'lib/apksigner.jar'), 'verify', '--verbose', '--print-certs', $OutputPath) -LogPath (Join-Path $buildPath 'signature') -TimeoutSeconds $TimeoutSeconds
if ($signature.StdOut -notmatch 'CN=Android Debug') { throw 'APK is not signed with the expected Android test certificate' }
Invoke-BoundedProcess -Executable (Join-Path $buildTools 'zipalign.exe') -Arguments @('-c', '-P', '16', '4', $OutputPath) -LogPath (Join-Path $buildPath 'alignment') -TimeoutSeconds $TimeoutSeconds | Out-Null
$manifest = Invoke-BoundedProcess -Executable (Join-Path $buildTools 'aapt.exe') -Arguments @('dump', 'badging', $OutputPath) -LogPath (Join-Path $buildPath 'manifest') -TimeoutSeconds $TimeoutSeconds
if ($manifest.StdOut -notmatch "package: name='org.systematic.synthwavedrive'" -or $manifest.StdOut -notmatch "native-code:.*'arm64-v8a'.*'armeabi-v7a'") { throw 'APK identifier or phone architectures differ from the expected preset' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$apk = [IO.Compression.ZipFile]::OpenRead($OutputPath)
try {
    foreach ($entry in @('assets/config/secret_mode.cfg', 'assets/runtime-notices/GODOT-LICENSE.txt', 'assets/runtime-notices/GODOT-COPYRIGHT.txt')) {
        if (-not $apk.GetEntry($entry)) { throw "APK bundled file missing: $entry" }
    }
    $native = @($apk.Entries | Where-Object FullName -Like 'lib/*/libgodot_android.so' | ForEach-Object FullName)
    $expectedCount = if ($IncludeEmulatorArchitecture) { 3 } else { 2 }
    if ($native.Count -ne $expectedCount) { throw 'Unexpected number of native runtime architectures in APK' }
}
finally { $apk.Dispose() }
$hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -LiteralPath ($OutputPath + '.sha256') -Value ($hash + '  ' + [IO.Path]::GetFileName($OutputPath)) -Encoding ASCII
Write-Output "ANDROID DEBUG APK PASS: $OutputPath"
Write-Output 'Debug-signed for direct testing; Google Play distribution requires a separate production signing and store build.'
Write-Output ("Architectures: " + ($native -join ', '))
Write-Output "SHA256: $hash"
Write-Output "Build logs: $buildPath"
