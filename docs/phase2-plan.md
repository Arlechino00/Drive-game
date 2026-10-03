# Phase 2 polish implementation plan

Spec: `synthwave_phase2_polish_prompt.md`. Preserve the existing stationary-player architecture, Compatibility renderer, keyboard controls, local saves, and bounded pools. No external assets or plugins.

## Design

Moving traffic uses common cruise speed in lane-based encounter rows. Common speed prevents rows overtaking each other and invalidating the guaranteed adjacent-lane escape route. Vehicle silhouettes and row density supply variety; unpredictable lane switching is excluded from this pass. Rows retain enough spacing for maximum boost speed.

Near misses are evaluated after an object's rear has cleared the player, with its closest clearance tracked only while their longitudinal footprints overlap. Collisions cancel the pass. Each activation awards at most once.

Risk rewards live in a separate RunProgress class: distance points remain worthwhile, near misses add points and boost, combos expire after a quiet interval, and boost is earned then spent. Boost increases approach speed while preserving precise steering.

Road variation uses existing straight chunks with authored visual categories: open grid, city edge, and neon covered sections. Their road surface, lanes, and collision coordinates stay consistent. Theme changes happen on recycled chunks ahead of view.

HUD and menus gain boost/combo displays, short reusable feedback, run statistics, Main Menu, and persisted volume/shake/effect/fullscreen controls. Camera, original synthesized audio, player visual response, and short crash feedback remain modular and bounded.

## Ownership and interfaces

- Traffic agent: `obstacle.gd`, `obstacle_spawner.gd`, `tests/traffic.gd`. Preserve `player_hit`, pool, active-count and reset/advance APIs; add `near_miss(points: int, clearance: float)`, seed support, `advance(..., delta: float = 0.0, player_x: float = 0.0)` and `RoadObstacle` pass tracking. Root uses delta for moving traffic.
- Environment agent: `visual_world.gd`, `road_manager.gd`, `road_chunk.gd`, shaders, `tests/world.gd`. Preserve nine 40 m segment reset/advance API; add `VisualWorld.set_effects(amount: float)` and `RoadManager.get_section_name() -> String`.
- HUD agent: `game_ui.gd`, `tests/ui.gd`. Preserve existing methods/signals; extend `update_hud(score, speed_kmh, multiplier=1.0, boost=0.0, boosting=false)`, `show_game_over(score, best, distance=0.0, top_combo=1.0, near_misses=0, new_best=false)`. Add `menu_pressed`, `settings_changed(key: String, value: float)`, `configure_settings(volume, shake, effects, fullscreen)`, `show_feedback(text, color)` and `set_effects(amount)`.
- Primary: `game.gd`, `player_car.gd`, new `run_progress.gd`, `difficulty_director.gd`, `drive_audio.gd`, `chase_camera.gd`, `game_settings.gd`; integrated tests, validation runner, captures, README.

## Milestones

- [x] Add failing gameplay tests for combo rewards/expiry, boost drain/reset, pause freeze, settings/save round trips; implement gameplay modules and integrate.
- [x] Implement and review traffic/near-miss behavior with collision exclusion, no duplicate rewards, seed replay, lane reachability, and bounded pools.
- [x] Implement and review stronger horizon, roadside motion, and authored chunk variation; check seams, long-run resources, and screen readability.
- [x] Integrate HUD, menus, settings, camera, engine/boost/UI/crash cues; test restart and settings restoration.
- [x] Run editor check, all subsystem tests, integrated smoke, maximum-speed endurance, a several-minute continuous simulation, and real renderer captures. Fix errors before adding further polish.
- [x] Compare changed files to the saved Phase 1 checkpoint, inspect all rendered screens, and update README with behavior, controls, validation, and limits.

## Review focus

Pause must freeze steering, combos, boost drain, spawns and scoring. A collision must never also award a near miss. Recycled objects must clear all per-pass state. Changing settings and restarting must not multiply nodes, callbacks, sounds, or timers. Boost-speed traffic must retain a reachable escape route. A debug seed must reproduce initial and subsequent layouts. High scores and preferences must retain existing saves.

## Final review — 2026-10-01

The final Windows runner passed editor loading, smoke, progression, settings, traffic, world, UI, integrated polish, endurance, continuous physics, clean window close, and nine rendered captures with no engine/script errors or warnings. A separate three-minute rendered driving run passed at 59.9 FPS with a 60 FPS cap on the RTX 2000 Ada laptop GPU; scene nodes stayed at or below 1,941 and monitored memory stayed bounded. Logs are in `.godot/validation/`.

Review corrected current-tick lateral sampling, release/repress of an empty boost during pause, immediate restart cleanup of sparks/crash audio, and the audio mix-thread drain on shutdown. The source comparison used `.godot/phase1_checkpoint/` because this folder has no Git repository; main scene and project settings remained byte-identical. All final captures were inspected for readable traffic, HUD, menus, sliders, boost, and close-pass feedback.

Road categories retain straight lanes and common traffic speed to preserve the reachable-path guarantee. Advanced lane switching, curves, beat-reactive visuals, and stretch modes remain future work. Physical controller feel and sound balance by ear were not verified.

## Handling and modes revision — 2026-10-02

User feedback identified an undersized car, safe parking on lane dividers, and slow early pacing. The car now scales 1.55 in width/length and 1.2 in height, with a shared 3.3×1.5×6.0 m physics/near-miss footprint. Its center stays within ±6.2 m so it remains on the road. Every traffic silhouette overlaps a player parked at a neighboring divider; open lane centers retain clearance.

Cruise starts at 45 m/s, reaches 62 m/s over650 m, and boosts up to80 m/s. Existing64 m minimum spacing remains reachable: twelve alternating paired-van rows passed using actual steering at the maximum66 m/s relative approach speed. Fair retains earned/draining boost; Infinite Boost uses held input without draining. Title selection is pinned during a run and retained on restart. Existing Fair records remain in `scores`; unlimited records use `scores_infinite` in the same save.

Fresh validation passed the full suite without errors/warnings, including divider contacts, both modes, record separation, UI at960×540, maximum-speed generation over128 km/eight seeds, and continuous three-minute simulations in both modes. A three-minute rendered Infinite Boost run passed at59.9 FPS with a60 FPS cap and bounded resources. Eleven final screens were inspected. Source comparison used `.godot/handling-modes-checkpoint-20261002-210735/`; project settings and main scene were preserved. Physical controller input and subjective sound balance remain unverified.

## UI revision — 2026-10-02

The user's 2560×2048 viewport made fixed-size menus and HUD text too small. UI now uses a 1100×800 reference layout, scaled uniformly to the visible game canvas while preserving the saved 3D resolution and aspect. An inherited MSDF font keeps transformed text sharp. The title has readable mode cards, an explicit selection mark, and a prominent Start action. Pause/results use paired secondary actions. Settings have larger slider handles, percentages, and a clear fullscreen switch. The HUD emphasizes speed and shows boost percentage or infinity, with an empty-fuel hint for Fair mode.

New responsive checks verify screen-space bounds and effective text/control sizes in six windows from 960×540 to 3440×1440, including the configured 2560×2048 display. Native mouse hits, arrow/Enter mode selection, keyboard sliders/toggle, and focus release passed. Eighteen additional renders cover title choices, HUD, pause, settings, and results in three window sizes. Capture dimensions account for Godot's preserved 5:4 aspect and exclude letterbox bars; an initial full-window expectation was corrected after actual renderer evidence.

The final full runner, including all twenty-nine captures and both three-minute simulations, passed without engine/script errors or warnings. Simulations retained stable monitored memory and at most 1,975 scene nodes. Primary and independent read-only review found no remaining actionable UI regressions. Source comparison used `.godot/ui-checkpoint-20261002-215516/`; only the UI subsystem, tests, runner, and documentation changed. Project settings and the main scene were preserved.

## Car design and logo revision — 2026-10-02

The box-based player visual became a chamfered, tapered sports-car shell with sloped glass, circular tires and five-spoke rims, raised headlights, rear wing, segmented tail lights, grille, diffuser, and hollow exhaust tips. Meshes/materials are built once and reused. The existing collision dimensions, steering, front-wheel yaw, body response, and boost hooks remain unchanged. Geometry checks compare the resting body with the existing footprint; decorative yaw/lean still moves independently of the fixed collider.

The supplied transparent `logo.png` is byte-identical to the Downloads attachment. It appears untinted beside the title and as an alpha-textured roof graphic, preserving aspect and colors. Mipmaps support distant roof rendering. UI delegation owned only the branding row and its assertions; primary reviewed and integrated those changes with the car.

The full runner passed all gameplay, geometry, branding/input, endurance, and both continuous-mode checks without errors/warnings; maximum scene count was 2,042 with stable monitored memory. Thirty-one rendered screens include normal gameplay, responsive menus, and front/rear model views. Initial close-view camera framing was overwritten by the ordinary chase update; the capture now freezes that update and asserts the review pose and full car bounds before saving. The corrected capture passed and was visually reviewed. Independent review found no actionable car/UI blocker. Comparison uses `.godot/car-branding-checkpoint-20261002-231657/`; project settings, main scene, original PNG, and gameplay subsystems were preserved.
