# sySTEMatic Secret Mode, player names and local rankings

The requested game extension adds a named-player leaderboard, an access-code secret level with finite boost and police pursuits, and a reusable post-like resume code. Both access and resume codes are manually edited in `config/secret_mode.cfg` and stay valid until changed. Existing Fair and Infinite Boost modes retain their current rules and score saves. The desktop project has no backend or social-account connection and does not verify likes automatically.

## Player flow

Starting from the title asks for a driver name, prefilled with the last name. Whitespace-only names are rejected; visible Unicode names up to 24 characters are supported. Restart keeps the same driver. Ranked entries retain the best score for each normalized player name, mode and assistance status, with deterministic ties and a bounded collection. Existing unnamed personal-best files remain intact. The leaderboard labels its scope as local and separates Fair, Infinite Boost, Secret, and resumed Secret runs.

F8 on the title opens a hidden access-code dialog, as selected by the user. The access phrase is read only from `config/secret_mode.cfg`, with no hard-coded fallback. Missing or empty configuration keeps the mode locked. Successful entry persists the unlock and reveals a third mode card; changing the configured code invalidates prior unlocks. Secret Mode is a distinct level of the same endless highway, with stronger police/night accents and earned boost. Its initial charge, earning and drain rules match Fair mode. Unlimited boost is unavailable in this level.

## Secret pursuit

Traffic impact, the second pothole within ten driving seconds, or entering a worksite starts a moving police pursuit instead of immediately ending the run. Impact deducts points, breaks the combo and causes a strong, recoverable slowdown. Limited boost remains usable during Secret damage so fuel management can help recovery. Further mistakes during pursuit slow the player again, reset clean-driving progress and bring police closer. Close passes still earn boost, but reset the clean-driving escape route and bring police closer.

Pursuit has an initial approach grace period, a measured gap, clean-driving progress and two escape routes: sustain sixteen seconds without close calls/mistakes, or create a large gap with boost. Police catch the player when their gap falls to the capture threshold. Values are tunable and tested at 45 and 62 m/s cruise so the first mistake is survivable with clean driving, while repeated impacts can lose. Pause freezes pursuit, boost and damage. Escape awards a modest bonus and resumes normal Secret driving; later mistakes may begin another chase.

A reusable police visual follows behind; a small rear-view display and gap/progress text keep pursuit visible without changing steering or blocking hazards. Police actors have no gameplay collision shapes. Resource counts remain bounded.

## Bribe / resume

After police catch a Secret run, the existing stopped-car police arrival plays. Once police have arrived, Bribe / resume accepts the `resume_code` from the same configuration section as `access_code`. The operator checks the post like manually and shares that configured code. It never expires or rotates automatically, and stays reusable across runs until edited. Each attempt reloads the file, so a changed value takes effect immediately. Missing, empty or non-string resume values disable continuation. Previously issued one-time codes are retired.

One code-assisted continuation is available per Secret run. Resuming preserves driver, score and distance, clears police/hazards/damage, starts at safe cruise speed, and retains the remaining earned fuel. The run is marked resumed and its final score goes into a separate assisted ranking and record section. Fair/Infinite results never expose this action. A final unassisted caught score may remain ranked as the legitimate score reached before continuation.

## Validation

Tests cover real input/name entry and collisions; secret unlock and mode isolation; clean escape, finite-fuel escape and repeated-hit capture; pursuit pause/restart/menu; configured resume reuse, live edits, missing/invalid codes, eligibility and one continuation per run; record preservation; local ranked ordering/limits/Unicode/malformed saves; six responsive UI sizes; rendered Secret/police/rear-view/leaderboard screens; and existing game regressions. Headless tests isolate user data. Rendering remains Godot 4.6.2 Compatibility. No deployment, external message, social login or online score service is introduced.
