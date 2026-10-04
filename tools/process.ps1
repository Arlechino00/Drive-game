function ConvertTo-NativeArgument([string]$Value) {
    # Windows CommandLineToArgvW quoting, including paths ending in a slash.
    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }
    return '"' + ([regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1')) + '"'
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$LogPath,
        [ValidateRange(1, 3600)][int]$TimeoutSeconds = 180
    )
    $stdoutPath = $LogPath + '.stdout.log'
    $stderrPath = $LogPath + '.stderr.log'
    New-Item -ItemType Directory -Force (Split-Path -Parent $LogPath) | Out-Null
    $nativeArguments = ($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $start = @{ FilePath = $Executable; PassThru = $true; RedirectStandardOutput = $stdoutPath; RedirectStandardError = $stderrPath }
    if ($env:OS -eq 'Windows_NT') { $start.WindowStyle = 'Hidden' }
    else { $start.NoNewWindow = $true }
    if ($nativeArguments) { $start.ArgumentList = $nativeArguments }
    $process = Start-Process @start
    try {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Kill this process and its children, including the Godot console wrapper.
            if ($env:OS -eq 'Windows_NT') {
                & "$env:SystemRoot/System32/taskkill.exe" /PID $process.Id /T /F 2>&1 | Out-Null
            }
            else { $process.Kill() }
            $process.WaitForExit(5000) | Out-Null
            throw "Process timed out after $TimeoutSeconds seconds: $Executable. Logs: $stdoutPath, $stderrPath"
        }
        $process.WaitForExit()
        $process.Refresh()
        $exitCode = $process.ExitCode
        $stdout = Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        if ($exitCode -ne 0) { throw "Process failed (exit $exitCode): $Executable. Logs: $stdoutPath, $stderrPath`n$stderr`n$stdout" }
        return [pscustomobject]@{ ExitCode = $exitCode; StdOut = $stdout; StdErr = $stderr }
    }
    finally { $process.Dispose() }
}
