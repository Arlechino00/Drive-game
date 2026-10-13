# Android mobile adaptation

User selected Android first. Keep the desktop game and the fixed-distance radar/braking rules, and add an installable landscape Android version with touch steering, brake, boost and pause.

1. Add an independent reusable multi-touch overlay with per-finger state and release/cancel handling. Test actual touch events before integrating it.
2. Connect touch state to existing steering/boost/brake logic; clear input on pause, restart, menu and backgrounding. Android Back dismisses dialogs/settings or pauses the run. Provide touch access to Secret Mode and virtual-keyboard submission.
3. Keep controls inside the display safe area, use phone-specific hints and graphics defaults, and avoid overlapping the existing radar/Police/Apex displays.
4. Add a reproducible Android export using the installed JDK/SDK and verified Godot 4.6.1 templates. Keep build/cache/preferences isolated and preserve the Windows preset.
5. Validate desktop regressions, real multi-touch gameplay and small/wide landscape captures, then inspect and run the APK on an Android emulator if available. Record physical-phone limitations accurately.

Ownership: primary owns gameplay/UI integration, integration/capture tests and documentation; mobile_touch_controls owns its standalone overlay/test; android_build owns Android export/build tooling. No store publishing, physical-device installation, or source-control publication is requested.

Validation on 2026-10-05: all 48 headless checks passed without engine/script warnings or errors. Eighteen rendered mobile views passed at 960×540/2400×1080, with additional 854×480 bounds and simulated safe-area checks. Representative driving/Apex views were inspected; independent touch/integration/community/mode checks also passed. Native Android export/runtime checks use a separate ignored emulator data directory to preserve the existing AVD. Physical-phone performance is not measured.

Final phone APK: `.godot/releases/Android/SynthwaveDrive.apk`, SHA256 `1e171a4db5fa0e4db55535d6e41fbdf9b482a10e8c5b6db5b638aaeaed32095e`. Manifest/API/ARM architectures, test signature, bundled configuration/notices and alignment checks passed. Native software-keyboard appearance remains a device check: the isolated emulator still advertises an internal hardware keyboard after disabling its AVD keyboard option, and the matching Godot Android implementation intentionally suppresses software input in that configuration. Hardware text entry/Start and automated submission signals pass. No production workaround was added for this emulator-specific constraint.

Native Android checks passed normal launcher cold start/warm return, full landscape/safe-area layout, actual steering/boost/gradual brake inputs, touch Pause, Android Back and Home/background return remaining paused. Host graphics resolved the legacy SwiftShader emulator shader failure without changing production rendering. Native receipt/screens/logs are in `.godot/validation/android-emulator/`; the isolated emulator was stopped and the original AVD preserved. All five steps are complete within available emulator validation; physical-phone keyboard and performance checks remain external.
