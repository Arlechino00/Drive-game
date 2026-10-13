param(
    [string]$GodotPath = 'godot',
    [switch]$Capture,
    [ValidateRange(1, 3600)][int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$projectPath = Split-Path -Parent $PSScriptRoot
$validationPath = Join-Path $projectPath '.godot/validation'
$savedAppData = $env:APPDATA
$savedLocalAppData = $env:LOCALAPPDATA
New-Item -ItemType Directory -Force -Path (Join-Path $validationPath 'appdata') | Out-Null
. (Join-Path $projectPath 'tools/process.ps1')

function Invoke-GodotCheck([string]$Name, [string[]]$RunArguments) {
    $logPath = Join-Path $validationPath ($Name + '.log')
    Remove-Item -LiteralPath $logPath -ErrorAction SilentlyContinue
    Write-Output "Checking $Name (limit $TimeoutSeconds seconds)"
    # Non-tutorial fixtures exercise the normal run directly; tutorial.gd opts in.
    $arguments = @('--path', $projectPath, '--log-file', $logPath) + $RunArguments
    if ($RunArguments -notcontains '--') { $arguments += '--' }
    $arguments += '--no-tutorial'
    $result = Invoke-BoundedProcess -Executable $GodotPath -Arguments $arguments -LogPath $logPath -TimeoutSeconds $TimeoutSeconds
    if (-not (Test-Path -LiteralPath $logPath)) { throw "$Name produced no engine log. See $logPath.stdout.log" }
    if (Select-String -LiteralPath $logPath -Pattern '^(SCRIPT ERROR:|ERROR:|WARNING:)' -Quiet) {
        throw "$Name logged an engine/script error or warning. See $logPath"
    }
}

try {
    # Keep validation logs, editor data, and score saves out of the player's profile.
    $env:APPDATA = Join-Path $validationPath 'appdata'
    $env:LOCALAPPDATA = Join-Path $validationPath 'localappdata'
    New-Item -ItemType Directory -Force $env:LOCALAPPDATA | Out-Null
    Invoke-GodotCheck 'editor' @('--headless', '--editor', '--quit')
    Invoke-GodotCheck 'smoke' @('--headless', '--script', 'res://tests/smoke.gd')
    Invoke-GodotCheck 'handling' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/handling.gd')
    Invoke-GodotCheck 'tutorial' @('--headless', '--script', 'res://tests/tutorial.gd')
    Invoke-GodotCheck 'tutorial-police' @('--headless', '--script', 'res://tests/tutorial_police.gd')
    foreach ($stageTwo in @('stage_two_speed', 'stage_two_high_speed', 'high_speed_balance', 'high_speed_interactions', 'stage_two_world', 'stage_two_traffic', 'stage_two_police', 'stage_two_apex', 'stage_two_localization', 'stage_two_integration', 'round_integrity', 'controller_ui', 'ui_audio_improvements', 'police_traffic_contacts', 'motorcycle')) {
        Invoke-GodotCheck $stageTwo @('--headless', '--script', "res://tests/$stageTwo.gd")
    }
    foreach ($subsystem in @('progression', 'hazard_rules', 'settings', 'player_records', 'record_recovery', 'secret_access', 'persistence_config', 'pursuit', 'radar_rules', 'radar_integration', 'braking_traffic', 'braking_distance', 'sector_traffic', 'touch_drive_controls', 'mobile_integration', 'secret_world', 'modes', 'traffic', 'encounters', 'world', 'background', 'car_design', 'traffic_design', 'traffic_models', 'apex_race', 'apex_safety', 'apex_race_ui', 'apex_visibility', 'aftermath', 'ui', 'ui_responsive', 'community_ui', 'polish')) {
        Invoke-GodotCheck $subsystem @('--headless', '--script', "res://tests/$subsystem.gd")
    }
    Invoke-GodotCheck 'render-settings' @('--headless', '--script', 'res://tests/render_settings.gd')
    Invoke-GodotCheck 'save-improvements' @('--headless', '--script', 'res://tests/save_improvements.gd')
    Invoke-GodotCheck 'save-lock' @('--headless', '--script', 'res://tests/save_lock.gd')
    Invoke-GodotCheck 'large-steps' @('--headless', '--script', 'res://tests/large_steps.gd')
    Invoke-GodotCheck 'apex-generated' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/apex_generated.gd')
    Invoke-GodotCheck 'audit-regressions' @('--headless', '--script', 'res://tests/audit_regressions.gd')
    Invoke-GodotCheck 'hazards' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/hazards.gd')
    Invoke-GodotCheck 'secret-mode' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/secret_mode.gd')
    Invoke-GodotCheck 'endurance' @('--headless', '--script', 'res://tests/endurance.gd')
    Invoke-GodotCheck 'continuous' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/continuous.gd')
    Invoke-GodotCheck 'continuous-infinite' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/continuous.gd', '--', '--infinite-boost')
    Invoke-GodotCheck 'continuous-secret' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/continuous.gd', '--', '--secret')
    Invoke-GodotCheck 'radar-braking-drive' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/continuous.gd', '--', '--radar-braking')
    Invoke-GodotCheck 'radar-braking-infinite' @('--headless', '--fixed-fps', '60', '--script', 'res://tests/continuous.gd', '--', '--radar-braking', '--infinite-boost')
    Invoke-GodotCheck 'quit' @('--headless', '--script', 'res://tests/quit.gd')
    if ($Capture) {
        Invoke-GodotCheck 'tutorial-capture' @('--fixed-fps', '60', '--script', 'res://tests/tutorial_capture.gd')
        Invoke-GodotCheck 'stage-two-capture' @('--fixed-fps', '60', '--script', 'res://tests/stage_two_capture.gd')
        Invoke-GodotCheck 'mobile-capture' @('--fixed-fps', '60', '--script', 'res://tests/mobile_capture.gd')
        Invoke-GodotCheck 'radar-capture' @('--fixed-fps', '60', '--script', 'res://tests/radar_capture.gd')
        Invoke-GodotCheck 'capture' @('--fixed-fps', '60', '--script', 'res://tests/capture.gd')
        Invoke-GodotCheck 'ui-capture' @('--fixed-fps', '60', '--script', 'res://tests/ui_capture.gd')
        Invoke-GodotCheck 'car-capture' @('--fixed-fps', '60', '--script', 'res://tests/car_capture.gd')
        Invoke-GodotCheck 'hazard-capture' @('--fixed-fps', '60', '--script', 'res://tests/hazard_capture.gd')
        Invoke-GodotCheck 'secret-capture' @('--fixed-fps', '60', '--script', 'res://tests/secret_capture.gd')
        Invoke-GodotCheck 'traffic-models-capture' @('--fixed-fps', '60', '--script', 'res://tests/traffic_models.gd', '--', '--capture')
        Invoke-GodotCheck 'apex-capture' @('--fixed-fps', '60', '--script', 'res://tests/apex_capture.gd')
        Invoke-GodotCheck 'background-capture' @('--fixed-fps', '60', '--script', 'res://tests/background.gd', '--', '--capture')
    }
    Write-Output 'VALIDATION PASS'
}
finally {
    $env:APPDATA = $savedAppData
    $env:LOCALAPPDATA = $savedLocalAppData
}
