# Synthwave Drive

A Godot 4.6 arcade endless racer: weave through futuristic traffic, avoid potholes and closed work lanes, earn boost from close passes, and escape police in the hidden Systematic Secret level. Named leaderboards and manually configured reusable continuation codes run locally. Built with GDScript, procedural meshes, shaders, original synthesized audio, and the supplied Systematic Robotics logo. No plugins are required.

## Run

Open `project.godot` in Godot 4.6 or newer and press **F5**, choose a mode, then choose **Start driving** or press Enter and enter your driver name. From a terminal with Godot on PATH, run `godot --path .` in this folder.

## Controls

| Input | Action |
| --- | --- |
| A / Left Arrow | Steer left |
| D / Right Arrow | Steer right |
| Controller left stick | Steer |
| Hold Shift / Space / controller right trigger | Spend boost |
| Escape | Pause / resume; return from Settings |
| R | Restart after a crash or while paused |
| Enter | Start from the title screen |
| F3 | Toggle seed, difficulty wave, road section, encounter/pool counts, and FPS |
| F8 or Ctrl+Shift+S on title | Hidden Secret Mode access dialog |

Menus support mouse and keyboard focus. Settings are available from the title and pause screens. Master volume, camera shake, visual effects, and fullscreen are saved locally.

## Interface

The interface scales with the rendered game area, keeping menus and controls readable in small windows and at high resolutions. Larger headings, mode cards, and a bright main action make the title, pause, and results screens easier to navigate. Secondary actions sit side by side, with visible keyboard focus and control hints. Driver names support up to 24 visible Unicode characters; the last name is prefilled, and restart retains the driver. Leaderboard shows the best ten drivers on this computer, with separate rankings for each mode and resumed Secret runs.

The HUD gives speed the strongest emphasis, with score and combo on the left. A wider boost bar shows remaining fuel as a percentage, or an infinity symbol in Infinite Boost mode. Empty Fair fuel explains how to earn more. A pothole warning counts down the repeat-hit window, and the boost hint explains the shorter recovery period. Police results sit beside the stopped cars and clearly mark disqualified scores. Settings use clear percentage values, larger slider handles, and a high-contrast fullscreen switch. Text stays sharp as the interface scales.

## Car and branding

The player car has a futuristic wedge body, sloped tinted canopy, round tires with five-spoke rims, slim headlights, a low aero wing, segmented rear lights, hood vents, diffuser, and hollow exhaust tips. Metallic magenta paint and cyan accents keep its silhouette distinct from traffic. Steering, body lean, and boost trails remain attached to the model.

The original Systematic Robotics logo appears beside the title, on the car's roof, and as the Godot application icon. Its colors, transparency, and proportions are preserved; distance filtering keeps the roof graphic stable in the chase view. The source is `logo.png`, copied unchanged from the supplied image.

## Modes

Choose **Fair** or **Infinite Boost** on the title screen. Fair uses earned boost that drains while held. Infinite Boost gives unlimited fuel: hold Shift, Space, or the controller's right trigger for sustained boost; release to cruise. Traffic, collisions, and scoring still work in both modes.

The selected mode is shown in the HUD and results, retained on restart, and can be changed after returning to the title screen. Records are separate so unlimited-boost runs do not overwrite Fair records. Existing high-score saves belong to Fair mode.

**Systematic Secret** unlocks through **F8** (or **Ctrl+Shift+S**, for keyboards where F8 is a media key) on the title and the code in `config/secret_mode.cfg`. The supplied phrase is `SYSTEMATIC`; change it in that file for your event. There is no hard-coded fallback. Missing/empty config keeps the mode locked, and a changed phrase invalidates the saved unlock when selecting/restarting Secret. Successful entry reveals the third mode card. This level uses a blue night palette and finite earned boost.

In Secret, traffic impact, a second pothole within ten driving seconds, or entering roadworks starts a moving police chase. Traffic costs up to 1,000 points and 30 m/s; repeat holes cost up to 500 and 18 m/s; roadworks cost up to 750 and 26 m/s. Speed recovers over four seconds, and limited boost remains usable during recovery. Police start 64 m behind with a three-second approach grace. Sixteen clean seconds without mistakes or close calls, or a gap of 100 m, escapes and awards 1,000 points. Further mistakes cost 14 m of gap; close calls earn fuel but cost 6 m and reset clean progress. A gap of 7 m means capture. A live, zoomed rear-view shows the actual police car.

After captured Secret police have arrived, **Bribe / resume** accepts the reusable `resume_code` beside `access_code` in `config/secret_mode.cfg` (supplied value: `SYSTEMATIC-RESUME`). Both codes stay valid until manually edited; there is no daily rotation or expiry. Each submission reads the current file immediately. An operator checks the post like and shares the configured resume code. One continuation per run preserves points, distance and remaining fuel, clears immediate hazards, and starts at cruise speed. HUD/results mark it Resumed; its final ranking and records are separate. Fair/Infinite never offer continuation. See [local event setup](docs/local-event-setup.md) for editing both codes and local save recovery.

## Driving and scoring

- Forward travel is automatic. Steering has quick lateral acceleration, controlled release, body lean, yaw, and front-wheel feedback. The redesigned car retains the 3.3×1.5×6.0 m collision body. Sitting on a divider beside occupied lanes collides; an open lane center remains safe.
- Cruise speed starts at 45 m/s (162 km/h) and reaches 62 m/s (223 km/h) after 650 m, roughly 12 seconds without boost. Boost adds up to 18 m/s, capped at 80 m/s (288 km/h), with camera pullback, wider FOV, exhaust trails, and stronger engine audio.
- Fair runs start with 40% boost. Near misses restore 18%, or 24% for clearance below 0.35 m. Holding boost drains 27% per second. After running empty, release the button before engaging newly earned charge. Infinite Boost runs keep the meter full.
- A close pass earns a base 100, 250, or 500 points according to clearance. It counts only after the traffic vehicle's rear clears the player, once per pass. A collision cancels the reward.
- Close passes add 0.5 to the combo, up to x5.0. The combo resets after 4.5 seconds without another close pass, or on impact. Bonuses use the combo; distance remains worth 10 points/m with a modest combo bonus.
- In Fair/Infinite, a pothole deducts up to 500 points, breaks the combo, and immediately removes 18 m/s (about 65 km/h), with a minimum speed of 27 m/s. Cruise speed recovers over four seconds; boost is unavailable during recovery and consumes no fuel. Another pothole in less than ten driving seconds ends the run. A hit at exactly ten seconds starts a new window. Pause freezes both timers.
- Roadworks close one or two lanes. In Fair/Infinite, entering a closed lane ends the run and invalidates its score; existing score, distance, combo, and speed records are preserved. Police approach from behind with a siren and park beside the stopped player. Invalid runs show **SCORE INVALID** and cannot earn a new record.
- In Fair/Infinite, traffic collision freezes the run and adds short sparks, impact shake, and sound. The player and the matching struck traffic model remain stopped while a futuristic police car pulls up alongside. Game Over shows the ending reason, score, best score, distance, top combo, and near-miss count. Restart is immediate, including during the police approach. Pothole failure and barrier collisions use the ordinary results view.
- Score, longest distance, highest combo, and top speed persist per mode in `user://highscore.cfg`: existing `scores` for Fair, `scores_infinite`, `scores_secret`, and `scores_secret_resumed`. Preferences use `user://settings.cfg`. Named leaderboard entries use `user://player_records.cfg`; saved access unlocks use `user://secret_access.cfg`. Record and leaderboard writes merge the latest saved results under a lock and replace files atomically, preserving results from another open game. Malformed score fields are recovered independently. A valid current access code repairs damaged saved unlock data.

## Traffic, road, and atmosphere

Ten readable futuristic traffic designs have faceted bodies, tinted glass, round tires, and distinctive red rear lights. The original **Pulse Coupe** (blue), **Relay Van** (purple), and **Solar GT** (amber) are joined by **Torque Muscle** (crimson, racing stripes and triple rear lamps), **Vector Hatch** (teal, short upright hatch and L-shaped lamps), **Atlas SUV** (green, raised body and roof rails), **Nomad Wagon** (white, long roof and vertical lamps), **Hauler Pickup** (orange, open cargo bed), **Apex Supercar** (silver, low wedge, wing and four round lamps), and **Executive Sedan** (violet, formal trunk and rectangular lamps). The magenta player car remains separate.

Each model has its own width, from the 1.8 m Vector Hatch to the 3.2 m Hauler Pickup; Torque Muscle and Atlas SUV are also wider than smaller cars. The original three retain their 2.0, 2.4, and 2.8 m widths. Visible bodies, collision boxes, close-pass clearance, and rival navigation use the same model dimensions. Height and length retain the existing compact, tall, and wide categories. Immutable meshes and materials are cached across the pool. A pool slot creates each additional design only on its first use and then reuses it, with a maximum of ten designs per slot and twelve slots.

### Rare Apex race

After 1,800 m, Apex has a 6% chance per eligible traffic vehicle, with at least 2,500 m between its spawns. Meeting it one car length ahead automatically shows **APEX CHALLENGES YOU** and starts a thirty-second race. A race does not start during an existing police pursuit. The actual pooled Apex accelerates to rival speed and navigates traffic with quick overtakes, tight following gaps, and three one-second speed bursts. It predicts the swept footprints using your actual speed before cutting ahead or behind, checks the center lane during wider detours, and briefly brakes when necessary before passing slower traffic. Its 66 m/s maximum burst speed leaves the player's 80 m/s boost an advantage. Countdown and lead use driving time and actual opponent position. The main camera keeps a nearby trailing rival visible; a small live Apex screen shows the real car and its distance ahead or behind even when it leaves the main view. The screen reuses one camera and viewport, which stop rendering outside the race.

To win, finish strictly ahead, meet a boost target randomly chosen from **four, five, six, or seven seconds total**, and hit **no potholes** during the race. The challenge and race HUD show that encounter's target and your progress. Targets replay with the run seed using a separate random stream, preserving traffic layouts. A pothole permanently marks that race failed even after recovering; ordinary damage and collision rules still apply. Fair/Secret drivers must save or earn enough fuel through near misses. Infinite Boost drivers must still engage boost. Traffic is limited to one ordinary encounter per row during the race, keeping room for the rival and an escape route.

A win awards **20,000 points** and **ten seconds of unlimited boost**. Hold the usual boost input to use it; it preserves finite fuel, clears the empty-fuel input lock, and returns to earned fuel when it expires. The reward does not bypass Fair pothole recovery. Infinite Boost remains unlimited after the reward timer expires. Race, popup, and reward timers freeze while paused.

A loss shows Apex's taunt. Fair/Infinite receive no additional penalty or police chase. Secret starts the existing moving police pursuit for public-road racing and speeding, without an extra collision penalty. A Secret impact during the race ends the challenge as a loss and applies its existing impact consequence. Restart/menu clear the race and its reward. Wins/losses, timer boundaries, all ten model bounds, pooled reuse, and rival lane safety are covered by dedicated tests.

Traffic travels in its lanes at 14 m/s. Rows mix single vehicles and pairs. A common traffic speed preserves row separation; a guaranteed safe lane connects to an adjacent safe lane in the next row. Rows stay at least 64 m apart at maximum difficulty, including boost-speed play.

Potholes have a jagged asphalt rim, dark center, and amber edge markers. Roadworks use orange/white barricades, warning lamps, cones, and a compact road roller, all contained within their closed lane. These hazards stay fixed to the road and award no near-miss rewards. Stationary rows are 80 m apart and never block all three lanes. Seeded traffic waves drain before stationary hazards enter view so their different approach speeds cannot squeeze away the escape route. New encounters spawn at least 70 m ahead even after a delayed frame; the combined pool is capped at twelve objects.

Cruise speed increases gradually while traffic density rises and falls in smooth waves. Recovery windows reduce density without abruptly changing handling.

Nine recycled 40 m road chunks provide continuous coverage. Three authored visual categories repeat in 400 m sections: **Open Grid**, **City Edge**, and **Neon Canopy**. A lighter entrance chunk leads into each section. The straight road and lane coordinates remain consistent while props change ahead of view.

The highway uses a shared seamless asphalt texture, restrained surface highlights, pale lane dashes, magenta divider studs, cyan edge lights, shoulders, and metal guardrails. A darker, wider ground grid frames the road. City buildings have stepped rooftops and window patterns; canopy arches include diagonal braces and inset light panels. Small repeated grid and window details use MultiMesh batches, created once per chunk.

The backdrop uses a sliced orange-to-pink sun behind three distinct faceted mountain ranges, a warm rose-to-violet sky, soft irregular cloud wisps, and sparse fixed stars. Two skyline layers contain 72 buildings with stepped crowns, landmark towers, rooftop antennas, and restrained cyan, violet, and amber windows. The city's structure and lights use ten fixed mesh batches, reducing the previous background's separate building draws. A central valley frames the road and sunset. Secret mode switches the sky, sun, halo, mountains, and skyline to a consistent blue palette using the same resources. Warm key lighting and a cool rim light reveal the car facets, while driving lights and light fog retain hazard clarity. The effects setting adjusts glow, atmospheric detail, skyline emission, sun emission and halo, exhaust trails, crash effects, and HUD animation. Camera shake can be turned off separately.

Original synthesized engine, boost, near-miss, crash, pothole, police siren, UI, and looping arpeggio sounds use Music, Engine, SFX, and UI buses. Playback nodes are reused across restarts. The siren stops once police have parked. Setting visual effects to zero keeps emergency lights steady instead of flashing.

## Architecture

| File | Responsibility |
| --- | --- |
| `scripts/game.gd` | State transitions, integration, records, input, clean shutdown |
| `scripts/player_car.gd` | Arcade steering, stable collision footprint, car visuals |
| `scripts/vehicle_mesh.gd` | Cached procedural vehicle hulls, canopies, and detail meshes |
| `scripts/traffic_models.gd` | Ten traffic identities, distinct silhouettes/lights, shared mesh/material catalog |
| `scripts/apex_race.gd` / `apex_race_ui.gd` | Rare opponent race rules, traffic-aware rival, countdown/challenge/results/reward UI |
| `scripts/run_progress.gd` | Score, timed combo, boost, pothole damage timers, run validity and statistics |
| `scripts/difficulty_director.gd` | Cruise progression and density waves |
| `scripts/obstacle_spawner.gd` / `obstacle.gd` | Seeded encounter pool, reachable traffic/static waves, relative movement, distinct contact signals and close-pass detection |
| `scripts/hazard_visuals.gd` | Cached pothole and roadworks geometry |
| `scripts/police_aftermath.gd` | Reusable police approach, matching stopped traffic replicas, emergency lights and results camera framing |
| `scripts/police_pursuit.gd` | Tunable chase gap/clean progress, shared-world rear camera and fixed police reuse |
| `scripts/player_records.gd` / `secret_access.gd` | Validated bounded local rankings, configured unlock, manually configured reusable resume and persistent access unlock |
| `scripts/road_manager.gd` / `road_chunk.gd` | Spatial chunk ring, section metadata, shared materials, decoration |
| `scripts/visual_world.gd` / `shaders/` | Procedural horizon and effects controls |
| `scripts/chase_camera.gd` / `crash_effect.gd` | Camera response and reusable impact sparks |
| `scripts/game_ui.gd` | HUD, reusable popup, menus, settings |
| `scripts/community_ui.gd` | Modal driver/access/resume entry, local ranking tabs and pursuit mirror |
| `scripts/game_settings.gd` / `drive_audio.gd` | Preferences and bounded audio playback |

The player stays near world origin while the road and encounters move toward the camera. Traffic movement subtracts its cruise speed from player speed; static hazards move with the road. This avoids growing world coordinates and keeps seeded rows predictable. Steering runs before traffic samples the current physics tick, so close-pass clearance matches the actual path. Contact signals identify the hazard type and retain the struck object for aftermath framing. Police and stopped traffic replicas have no physics actors, so the ending animation cannot trigger further collisions.

Pause freezes steering, encounters, score, combos, boost, damage timers, camera, and gameplay feedback. Menus remain interactive. After a police ending, driving and scoring remain frozen while only the police scene and camera advance. Restart clears transient sounds, police actors, damage, invalidation, sparks, rewards, pass state, and camera state without rebuilding the scene.

## Reproduce a run

Normal starts generate a fresh nonnegative seed. F3 shows it. Launch with that seed to reproduce traffic layouts:

```text
godot --path . -- --seed=2468
```

A supplied seed is reused on restart. Invalid or negative seed arguments keep ordinary randomized runs. Player choices and the distance-based difficulty curve still affect encounter timing.

## Validation

On Windows, run:

```powershell
./tests/run.ps1 -GodotPath 'path/to/Godot_console.exe' -Capture
```

Omit `-GodotPath` when Godot is on PATH. Omit `-Capture` for headless checks only. The runner isolates saves in `.godot/validation/appdata`, writes logs in `.godot/validation`, and fails on a nonzero exit or engine/script errors or warnings.

Checks cover editor loading, keyboard steering/start/restart, pause freezing, collisions at both dividers against every traffic type, twelve alternating escape lanes at 288 km/h, real near misses and duplicate exclusion, both modes and separate records, combo/boost rules, settings, seed replay, responsive UI, and clean window close. Hazard checks use real Area3D contacts in both modes, test exact ten-second and repeated physics-tick boundaries, score clamping, speed recovery, held-boost lockout, frozen paused timers, and record-file preservation after disqualification. Police checks cover all traffic types, stopped actors, arrival/parking, effects-off lights, viewport framing, and 200 reuses. UI checks cover 960×540, 1280×720, 1920×1080, 2560×1440, 2560×2048, and 3440×1440 windows, including hazard warnings, recovery hints, both police result types, transformed bounds, effective text sizes, actual mouse hits, keyboard mode selection, and settings controls. Maximum-speed generation runs eight seeds over 128 km and 200 restarts. Traffic tests cover eight boost-speed runs and 52.8 km of relative encounter motion; mixed-speed hazard tests cover 149.6 km, reachable adjacent lanes, catch-time separation, and delayed-frame spawning. World tests cover 232.5 km and 200 resets. Pools, scene nodes, materials, seams, and reachable lanes remain bounded.

Named ranking checks cover Unicode, deterministic ties, limits, malformed saves, stale-instance merging, save contention and read/write/rename failures. Record recovery checks cover malformed fields, preserved valid statistics, stale-instance score merging, mode isolation, equal-score ties, lock ownership and failed-write retry. Access checks cover configured unlock/revocation, damaged-unlock repair, reusable config-based resume, live edits, invalid/missing values and unlock-save contention. Secret integration checks exercise real impacts, clean escape, finite damaged boost, capture, eligibility and separate resumed scores, including a real R-key restart after changing the access phrase. Pursuit resources are checked across 200 reuses. Encounter regressions cover swept corner impacts at 60 Hz, exactly one outcome, contact-time aftermath placement and synchronous pool reset safety.

The continuous checks drive through actual physics collisions with an input-based test driver in all three modes for 10,800 physics frames each: three simulated minutes at 60 Hz. The Infinite driver holds boost for at least 90% of its frames and briefly releases the real boost key when Apex and traffic require slowing; uninterrupted held-input behavior is checked separately. Route planning uses actual approach speeds, full encounter occupancy windows, and the time needed to steer between lanes. Scene nodes and live memory are monitored. A separate real-time rendered run is available:

```text
godot --path . --max-fps 60 --script res://tests/continuous.gd -- --render-soak
```

Append `--infinite-boost` to test sustained maximum boost in that run.
Append `--secret` to test the locked level with test-only access data.

For an uncapped 600-frame renderer benchmark:

```text
godot --path . --disable-vsync --fixed-fps 60 --script res://tests/continuous.gd -- --render-benchmark
```

Append `--secret --pursuit` for a 600-frame measurement with the live police mirror active throughout. That isolated mirror benchmark keeps other encounters inactive; the normal continuous checks exercise full procedural generation.
Append `--infinite-boost --apex` for a 600-frame measurement with the live Apex screen active, including the distant-rival road backdrop. This fixture keeps other encounters inactive.

Direct checks use the normal Godot user-data folder. Prefer the Windows runner to protect personal saves, or redirect APPDATA to `.godot/validation/appdata` before running direct commands.

`-Capture` renders eleven screenshots at the configured resolution in `tests/`: both mode selections, Fair gameplay and boost, Infinite Boost gameplay, city, canopy, real near-miss feedback, pause, game over, and settings. It also renders six UI states in 960×540, 1280×720, and 1920×1080 windows as `ui_*_<width>.png`, two hero views as `car_front.png` and `car_rear.png`, and three-vehicle lineups as `traffic_front.png` and `traffic_rear.png`. Six additional 1280×720 views show `pothole.png`, `pothole_warning.png`, `roadworks.png`, `police_approaching.png`, `police_roadworks.png`, and `police_crash.png`; warning and police captures are triggered by actual contacts. The ten-model contact sheet is `traffic_models.png`. Actual Apex challenge, boosted victory/reward, and Secret loss/police views are `apex_challenge.png`, `apex_win.png`, and `apex_secret_loss.png`. Rival-screen captures show far ahead, far behind, and a nearby trailing Apex as `apex_rival_ahead.png`, `apex_rival_behind.png`, and `apex_near_rival.png`. Ordinary captures contain the rendered area and exclude any side bars from the saved aspect ratio. Model-review captures use a temporary test window and fixed camera; project settings remain unchanged. Capture framing deliberately places encounters and advances sections; independent gameplay tests verify actual behavior.

Thirteen new 1280×720 captures show driver entry, access, unlocked title, Secret level, distant/close pursuits, escape, capture, resume entry, assisted driving/results, and both Secret ranking partitions. Police and escape shots use actual contacts and clean recovery.

Background captures are `background_sunset.png`, `background_city.png`, `background_canopy.png`, `background_secret.png`, `background_effects_off.png`, and the 1920×800 `background_wide.png`. The earlier matching view is preserved as `background_before.png`. The background check exercises 200 palette/effects changes, verifies all 19 world nodes and 41 resource identities remain stable, checks mountain valleys and skyline clearance, and preserves driving lights, fog, and actual hazard materials and collision bounds.

Validated on 2026-10-04 with Godot 4.6.1 and Compatibility rendering. All 35 checks passed without engine/script errors or warnings, including all ten model widths, real collision and near-miss boundaries, Apex spawn frequency and cooldown, race rules, aggressive rival safety, live opponent visibility, UI, Secret outcomes, and bounded world/pool reuse. The original seeded three-minute drives covered 11.05 km each in Fair and Secret, and 14.27 km in Infinite Boost, with at most 5,353 scene nodes and stable monitored memory. Infinite used actual held boost for 98.73% of its frames, with one brief release interval for traffic. Updated ten-model and actual Apex challenge/victory/Secret-loss captures passed and were inspected. A fresh copy containing only the staged project files passed editor import and gameplay smoke validation without local caches. Earlier swept-collision, record-recovery, unlock-recovery and score-validation fixes remain covered. Logs are in `.godot/validation/`; the driver investigation and final isolated checks are in `.godot/validation/driver-debug/`.

The final uncapped 600-frame Secret pursuit benchmark averaged 208.8 rendered FPS on the RTX 2000 Ada laptop GPU with stable monitored memory and the shared-world rear viewport active for the whole measurement. This short measurement isolates the pursuit view; it is separate from the three-minute generation simulations and is not a real-time soak.

## Current limits

Road variation is visual: the road keeps straight lanes without curves or elevation. Ordinary traffic stays in fixed lanes; Apex uses its tested overtaking and lane-change behavior during races. Audio uses lightweight synthesized material. Physical controller response, sound balance by ear, and subjective difficulty tuning still benefit from live play sessions. Performance depends on hardware and display settings.
