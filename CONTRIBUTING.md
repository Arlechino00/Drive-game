# Contributing

Read `agents.md` and the current `README.md` before changing a subsystem. Keep changes small, preserve existing modes and procedural generation safety, and review uncommitted work before editing. Ask the owner for permission to reuse or redistribute the project; the source is all rights reserved. Branding has its own notice in `docs/BRANDING.md`.

Use Godot **4.6.1 stable** for validation and releases. No plugins or external game libraries are required. Start the game from `project.godot` or with `godot --path .`.

## Validation

On Windows:

```powershell
./tests/run.ps1 -GodotPath 'path/to/Godot_v4.6.1-stable_win64_console.exe'
./tests/run.ps1 -GodotPath 'path/to/Godot_v4.6.1-stable_win64_console.exe' -Capture
```

Every engine process has a 180 second limit; override with `-TimeoutSeconds` when needed. The runner fails on nonzero exits and Godot errors or warnings. APPDATA and LOCALAPPDATA point into `.godot/validation`, protecting personal saves. Logs and captures must be inspected when changing visuals. Push and pull request CI run the headless suite on Windows; rendered captures remain a local check.

For the cold normal-traffic renderer benchmark, isolate APPDATA and LOCALAPPDATA before using `tests/continuous.gd -- --cold-benchmark`. This rendered check needs a GPU and is separate from CI. See the README for commands and other rendered benchmarks.

## Windows release

`tools/install-godot.ps1` downloads the pinned editor and official templates into ignored `.godot/tools`, verifies their SHA256 hashes, and extracts only Windows64 templates. It does not install templates globally. Existing templates can be supplied directly:

```powershell
./tools/install-godot.ps1
./tools/build-release.ps1 -GodotPath './.godot/tools/Godot_v4.6.1-stable_win64_console.exe' -TemplatePath './.godot/tools/4.6.1.stable'
```

The build uses fresh staged source, bundles `config/*.cfg`, copies editable `secret_mode.cfg` beside the executable, includes source/branding/Godot notices, verifies the exported title unlock and captured-run resume, and verifies the extracted ZIP again. Tests cover loose valid configuration, invalid loose configuration failing closed, and absent loose configuration using the bundle. All release test saves are isolated. The default output is `.godot/releases/SynthwaveDrive-Windows64.zip`; `-OutputPath` chooses another ZIP path. SHA256SUMS lists packaged file hashes.

Official release templates disable script/scene path overrides. The explicit internal `-- --verify-release` flag runs checks against the normal shipped main scene; the packaging tool always isolates its saves and requires a pass marker. Use `tools/verify-release.ps1 -PackagePath 'path/to/package.zip'` to repeat that check safely.

Tag pushes matching `v*` validate, package and publish the Windows ZIP. Manual release workflow runs produce a downloadable artifact without creating a release. Do not tag a release until the headless suite, affected rendered checks and package verification pass.
