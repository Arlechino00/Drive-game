# Synthwave Drive — Windows64

Extract the whole ZIP into a folder, then open **SynthwaveDrive.exe**. Keep the executable and `SynthwaveDrive.pck` together. The optional `SynthwaveDrive.console.exe` displays diagnostic output for support. No editor or plugins are needed.

Choose Fair or Infinite Boost, select Start driving, and enter a driver name. Avoid traffic, potholes and closed roadwork lanes. Close passes earn boost. A rare Apex challenge rewards winning a thirty-second race with the required boost time and no potholes.

## Controls

| Input | Action |
| --- | --- |
| A / D or Left / Right | Steer |
| Controller left stick | Steer |
| Hold Shift / Space / right trigger | Boost |
| Escape | Pause / resume |
| R | Restart after a crash or while paused |
| Enter | Start from the title |
| F8 or Ctrl+Shift+S on the title | Secret Mode code entry |

Settings are available from the title and pause screens. Preferences, local records and driver names are saved on this computer in `%APPDATA%\Godot\app_userdata\Synthwave Drive`. Keyboard, mouse and controller input work in menus.

## Local event codes

Edit **secret_mode.cfg beside the executable** to choose the Secret Mode access phrase and reusable police-capture resume phrase. Keep the quoted string format. The supplied public local-event defaults are `SYSTEMATIC` and `SYSTEMATIC-RESUME`. Changes are read when codes are checked; changing access revokes the old saved unlock.

An invalid loose configuration keeps access locked. Removing it uses the original bundled configuration. Empty `access_code` locks Secret Mode; empty `resume_code` disables continuation. A captured Secret run may resume once, after police have parked, preserving earned progress and fuel. See [local event setup](docs/local-event-setup.md) for details.

## Rights and notices

This game is all rights reserved. Obtain permission from the owner before reuse or redistribution; see `LICENSE`. The supplied sySTEMatic Robotics artwork has its own [branding notice](docs/BRANDING.md). Godot and its runtime dependencies have separate notices in `GODOT-LICENSE.txt` and `GODOT-COPYRIGHT.txt`.

`SHA256SUMS.txt` lists the packaged file hashes. Keep the package intact when reporting a problem, and include the ending reason, selected mode and run seed from F3 if available.
