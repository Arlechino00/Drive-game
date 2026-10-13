# Synthwave Drive — Windows64

Extract the whole ZIP into a folder, then open **SynthwaveDrive.exe**. Keep the executable and `SynthwaveDrive.pck` together. The optional `SynthwaveDrive.console.exe` displays diagnostic output for support. No editor or plugins are needed.

Choose Fair or Infinite Boost, select Start driving, and enter a driver name. Avoid traffic, potholes and closed roadwork lanes. Close passes earn boost. A rare Apex challenge rewards winning a thirty-second race with the required boost time and no potholes.

Every new round starts with short English/Romanian prompts while you drive: steer, brake, use Boost, avoid one marked car and slow for a practice radar. The standard intro refers Secret questions to the sySTEMatic Robotics team. The unlocked sySTEMatic level has its own practice for steering, Boost, capture pressure and escape.

Complete the practice, click/tap **Skip**, press Enter or controller A to start a clean normal run; practice does not enter the rankings. The handoff keeps the car and camera in place. Pause freezes it. **Tutorial** from the title replays the selected intro through the driver-name prompt. During paused practice, it resumes the current lesson. During a normal paused run, it resumes driving with basic controls coaching and keeps your progress when dismissed.

## Controls

| Input | Action |
| --- | --- |
| A / D or Left / Right | Steer |
| Controller left stick | Steer |
| Hold Shift / Space / right trigger | Boost |
| Hold S / Down Arrow / left trigger | Brake (takes priority over boost) |
| Escape | Pause / resume |
| R | Restart after a crash or while paused |
| Enter | Start from the title; skip driving practice |
| Controller D-pad / A / B | Navigate menus / accept or skip / back |
| Controller Start | Pause / resume |
| F8 or Ctrl+Shift+S on the title | Secret Mode code entry |

Settings are available from the title and pause screens. Preferences, local records and driver names are saved on this computer in `%APPDATA%\Godot\app_userdata\Synthwave Drive`. Keyboard, mouse and controller input work in menus.

Choose English or Română from the title or Settings; the choice is saved. Cruise speed keeps increasing during long runs. Radar warnings allow braking distance, and speeding at a camera deducts score and raises police Heat. Arrest requires sustained capture pressure; create real separation and clear the escape meter to evade, using steering, traffic or optional Boost. Camera-free sectors allow speeding without a fine.

Switching away from the game pauses it; returning leaves it paused until you resume. Valid ranked rounds save on game over, Menu, Restart and Quit. Extended crawling outside radar approaches, posted-limit sectors and damage recovery has a twenty-second grace period, then leaves that round outside the rankings. A warning and persistent badge explain this; driving and Boost remain available. Five seconds at normal pace restores the grace timer before it expires. Legal radar braking stays ranked.

Results and settings show a notice if saving fails. Damaged records are backed up before recovery. See [save recovery instructions](docs/local-event-setup.md) if a legacy save lock prevents saving.

## Local event codes

Edit **secret_mode.cfg beside the executable** to choose the Secret Mode access phrase and reusable police-capture resume phrase. Keep the quoted string format. The supplied public local-event defaults are `SYSTEMATIC` and `SYSTEMATIC-RESUME`. Changes are read when codes are checked; changing access revokes the old saved unlock.

An invalid loose configuration keeps access locked. Removing it uses the original bundled configuration. Empty `access_code` locks Secret Mode; empty `resume_code` disables continuation. A captured Secret run may resume once, after police have parked, preserving earned progress and fuel. See [local event setup](docs/local-event-setup.md) for details.

## Rights and notices

This game is all rights reserved. Obtain permission from the owner before reuse or redistribution; see `LICENSE`. The supplied sySTEMatic Robotics artwork has its own [branding notice](docs/BRANDING.md). Godot and its runtime dependencies have separate notices in `GODOT-LICENSE.txt` and `GODOT-COPYRIGHT.txt`.

`SHA256SUMS.txt` lists the packaged file hashes. Keep the package intact when reporting a problem, and include the ending reason, selected mode and run seed from F3 if available.
