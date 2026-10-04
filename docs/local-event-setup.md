# Local event setup

Players enter a driver name before starting. Leaderboard shows the best ten drivers on this computer, with separate Fair, Infinite Boost, Secret and resumed Secret rankings. Restart keeps the same driver.

## Edit both codes in one file

When running the source project, open `config/secret_mode.cfg`. In a Windows release, edit `secret_mode.cfg` beside `SynthwaveDrive.exe` after extracting the complete ZIP:

```ini
[secret_mode]
access_code="SYSTEMATIC"
resume_code="SYSTEMATIC-RESUME"
```

Both codes remain valid until you edit them manually. They do not expire, rotate daily, or change after use. Change either whenever you want; values are case-sensitive, with surrounding spaces ignored. Keep the codes in this file when distributing the local project.

On the title screen, press **F8** (or **Ctrl+Shift+S** if F8 is a media key on your keyboard), enter `access_code`, and select the revealed **Secret** card. Unlock is saved on this computer. Changing the access code invalidates that saved unlock when Secret is selected or restarted. Missing/empty access keeps the mode locked. Editing only the resume code preserves the access unlock.

Secret uses finite earned boost and a blue night palette. Traffic impact, a second pothole within ten driving seconds, or entering roadworks starts a police chase. Avoid mistakes and close calls for sixteen seconds, or build a 100 m gap with limited boost, to escape. Repeated mistakes bring the police closer. Capture ends the run and shows police stopping alongside.

## Give the player the resume code

After police stop beside a captured Secret player, **Bribe / resume** appears. Check the post like manually and give the player the configured `resume_code`. The game does not connect to social accounts or verify likes itself. There is no code-issuing command to run.

The same resume code works in later games. The game rereads the configuration on every submission, so manual edits take effect immediately without restarting. An old value stops working as soon as it is replaced. Missing, empty or invalid `resume_code` disables continuation; the access code can still unlock Secret. Previously generated one-time codes are no longer accepted.

One continuation is allowed per Secret run. It keeps points, distance and remaining fuel, clears immediate hazards and police, and resumes at cruise speed. HUD/results mark it **Resumed**, and its final score goes into a separate ranking. Fair and Infinite Boost never offer continuation.

## Local saves

Godot's `user://` normally resolves to `%APPDATA%/Godot/app_userdata/Synthwave Drive/` on Windows:

| File | Content |
| --- | --- |
| `player_records.cfg` | Last driver name and local leaderboard |
| `secret_access.cfg` | Saved access-unlock fingerprint |
| `highscore.cfg` | Per-mode score, distance, combo and speed records |
| `settings.cfg` | Sound, effects, camera and window preferences |

The editable codes live in the project's `config/secret_mode.cfg`, or beside the exported executable, rather than these save files. An exported build uses its bundled configuration only when the loose file is absent. A present invalid file keeps access/continuation unavailable instead of using a different code. Validation uses its own profile under `.godot/validation`.

Leaderboard and record saves merge the latest results before writing, so an older open game cannot erase a newer saved result. Score fields are validated independently; one malformed field does not discard the other valid records. If saved Secret unlock data is damaged, entering the current access code rebuilds it. Incorrect codes and unreadable/unwritable storage do not grant access.

Leaderboard refreshes when opened or its mode filter changes. A corrupt or unsupported `player_records.cfg` is copied unchanged to a unique `player_records.cfg.recovered-*` backup before supported records are rebuilt. The backup preserves future-format data but is not migrated automatically. Keep it if you need to recover older entries. A valid driver name can still start a run if records cannot be written; the game displays a save notice.

Saves briefly hold an empty lock directory beside the affected file: `secret_access.cfg.lock`, `player_records.cfg.lock`, or `highscore.cfg.lock`. If a game crashes during a save, close all game instances, remove only the corresponding empty lock directory, and retry. Resume validation reads the configuration directly and does not depend on these locks.
