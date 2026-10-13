# Stage Two implementation report

## Changed

Extended the existing Godot game: continuous survival/time-distance progression; speed-aware traffic preview and physical row spacing; 8% matching traffic width/length increase and modest player footprint correction; mixed-speed overtaking with a reserved reachable corridor and per-tick physical following limits; Heat/radar risk consequences; sustained capture, gradual decay, real disengagement and up to three reused police roles; Apex anti-block draft/pass/adaptation and bounded throttle/merge prediction; complete live English/Romanian interface with persistent settings; capture critical feedback, speed milestones, wind/engine/camera progression and risk scoring.

The supplied logo, existing modes, boost fuel, countdown/race rewards, access/resume codes and saved scores are preserved. Old settings default to English. Player names never translate. No source-control publication was requested or performed.

## Important files

- `scripts/game.gd`: integration, survival time, synchronized pursuit dispatch, radar consequences and localized feedback.
- `scripts/difficulty_director.gd`, `stage_two_tuning.gd`, `heat_controller.gd`, `run_progress.gd`: progression, physical budgets, Heat and risk scoring.
- `scripts/obstacle_spawner.gd`, `obstacle.gd`, `traffic_models.gd`, `player_car.gd`, `road_manager.gd`: mixed traffic, physical safety, matching footprints, bounded world.
- `scripts/police_pursuit.gd`, `apex_race.gd`: pursuit roles/capture and rival navigation.
- `scripts/localization.gd`, `localization/en.gd`, `localization/ro.gd`, UI/settings scripts: localized persistent interface.
- `scripts/chase_camera.gd`, `drive_audio.gd`: smooth perceived speed and capture warning.
- `tests/stage_two_*.gd`, migrated existing regressions, `tests/run.ps1`: focused/integrated/world/render checks.
- Windows/Android build staging now includes localization; the exported-release verifier checks Romanian resources and sustained police arrest.

## Balance

Cruise km/h = `130 + 200*(1-exp(-minutes/4)) + 7*minutes`, where minutes blend 95% active driving time and 5% distance / 50 m/s reference time. The October 6 speed tuning runs at five times the original progression pace, including the endless tail. An integrated unboosted hour simulation measured 309.3/387.0/476.1/553.6/792.3 km/h at 5/10/20/30/60 minutes. Braking/damage override actual speed while progression continues. Boost adds 38 m/s. Actual player motion is bounded at a remote 7,140 km/h technical ceiling to retain 1.2 seconds of spawning room plus a footprint within the finite preview; the director target remains uncapped.

Traffic preview is at least 285 m, normally four seconds of current travel, within a 2,400 m spatial budget. Sixty-six 40 m road chunks and at most twenty traffic actors are allocated; no time-dependent node growth. Camera range follows current speed so early runs do not render the entire late-run road. All chunks use one double-precision phase to prevent accumulated seam drift. Spacing preserves 0.72 seconds plus footprint lengths. Mixed waves begin after ten minutes, keep a continuous outside corridor, and clear old static actors before switching. AI plans overtakes at 4 Hz; per-tick forward safety remains active near the player.

Police capture takes five seconds at strong pressure and decays 12%/s outside pressure. Escape needs every unit beyond 100 m, cleared capture, and five seconds of disengagement. Heat 0–6 dispatches one/two/three units at <2/2–3/4+. Closing targets follow actual player speed, including Boost, plus 4–8 m/s by role; posted limits do not cap pursuit. Finite 18 m/s² acceleration follows the real boost ramp. Formation matching, turning losses and traffic braking preserve physical capture and escape. Radar reinforces without moving existing units. Speeding costs `100 + ceil(10*excess km/h)` points. Radar warning includes physical braking distance plus one second of reaction.

Apex blocking detection uses <28 m distance, ≤3.5 m/s relative speed and about 0.7 seconds, shortened moderately by run age. Acceleration starts at 48 m/s² and scales from an 80 m launch-deficit budget; targets have 3 m/s forward headroom or 6 m/s chase headroom with a modest age bonus. Brief chase bursts reference actual player speed, including Boost, without obeying posted limits. Collision-safe emergency braking can exceed ordinary throttle deceleration. Recovery handles an active rival's speed loss and displacement; a player collision retains the existing mode collision outcome. Result metadata survives reset: only a real opposing lead says Apex won; unmet Boost, potholes, ties and interruptions have distinct English/Romanian messages.

## Validation evidence

- Speed regression first reproduced the old 223.2 km/h ceiling, then passed continuous growth and forward/reverse swept contacts at 250/300/350/400 km/h.
- Four accelerated 30-minute world simulations at those speeds passed seamless road, visible coverage, reachable mixed corridors and bounded pool checks; largest observed pool was twelve.
- An independent generated seed-11 review reproduced mixed traffic overlap near the player. The added natural mixed-traffic regression passed after per-tick following safety; independent re-review also passed four seeds, 96,000 ticks and 20,596 lane-change observations without physical overlap. Stale-Heat dispatch was independently reproduced and checked through both actual game dispatch paths.
- Focused police checks passed capture/decay, real boxing, no instant contact arrest, steering escapes without Boost at multiple Heat levels, radar/deferred state handling and high-speed traffic collision safety.
- Apex checks passed safe anti-block passing, blocked-lane release, traffic merge prediction, bounded recovery/acceleration and 250–400 km/h navigation. Eight generated races passed with finite fuel and legitimate close-pass refills.
- Localization checks passed key/format parity, persisted/legacy settings, live modal/results switching, player-name preservation and critical capture. Twenty EN/RO desktop/mobile views at 1280×720 were rendered and inspected; existing mobile, Secret, radar and Apex captures also passed.
- Rendered late-run benchmark: 600 physics frames, 603 drawn frames, 57.5 FPS on the NVIDIA RTX 2000 Ada laptop GPU, max 6,943 nodes and stable memory; actual Apex and police activity included. This is a short benchmark, not a 30-minute rendered soak.
- Windows export and extracted-ZIP verification passed for valid external configuration, invalid external configuration and bundled fallback; Romanian resources and sustained police arrest checked. ZIP: `.godot/releases/SynthwaveDrive-StageTwo-Windows64.zip` (38,262,581 bytes), SHA-256 `3b2dfceb8e39dd4cefd4a66c7669ea4eb9149e05bb738f142045ae27063126ae`.
- Before the tutorial follow-up, complete `tests/run.ps1` regression passed (exit 0, `VALIDATION PASS`); runner rejects engine/script errors and warnings. Fair, Infinite Boost and Secret each survived 10,800 actual physics frames with physics collisions enabled and real radar/Apex encounters, stable memory and bounded nodes. Both real-input radar-braking drives passed with zero fines. Save migration/recovery, restart/pause, controls and quit checks passed.

## Tutorial follow-up

Replaced the page guides in `scripts/tutorial_ui.gd` with live English/Romanian coaching over the moving road. Every new round begins practice, with no remembered completion state. Standard practice follows steering, braking, Boost, avoiding one marked car, radar braking and finish; its Secret mention refers players to the sySTEMatic Robotics team. Selecting the unlocked sySTEMatic level gives a separate steering, Boost, capture-pressure, escape and finish sequence.

Practice is excluded from normal records. Finishing, one click/tap on Skip, or Enter starts a clean normal run. Pause freezes practice. Title Tutorial replays the selected intro through the driver-name prompt. During paused practice, Tutorial resumes the existing lesson. During a normal paused run, it resumes driving with basic steering, braking and Boost coaching; dismissing it preserves the current run and earned progress.

Live tutorial checks passed automatic introductions on repeat rounds, real steering/braking/Boost, clean Skip/Enter starts, frozen practice during pause, safe lesson resumption and normal-run coaching that preserves earned progress. The permanent `tutorial_police` regression was reviewed, independently rerun and added to the runner: real police pressure reached 13.3%, followed by physical separation of 209.811 m and five seconds of disengagement. Practice completion, pause, Skip, repeat rounds and retry preserved clean scores, records and seeded random streams. Rendered checks passed 88 English/Romanian desktop/mobile views with 60 representative PNGs, including actual touch steering, braking, Boost and Skip.

The final Windows export and extracted-ZIP verification passed valid external configuration, invalid external configuration and bundled fallback. Earlier live-tutorial ZIP: `.godot/releases/SynthwaveDrive-StageTwo-LiveTutorial-Windows64.zip`, SHA-256 `00659dd7699ae12db29913c430cc21b6cb0146b1d3962a67af92faeeb55d21c8`. These receipts supersede the earlier page-guide tutorial build and captures.

The complete follow-up `tests/run.ps1` run finished with exit 0 and `VALIDATION PASS`. Fair, Infinite Boost and Secret each passed 10,800 actual physics frames; endurance passed eight seeds, 128 km and 200 restarts. Real-input radar braking passed three safe cameras in Fair and two in Infinite Boost, and quit checks passed. The final pause fix and newly added `tutorial_police` check were verified separately with fresh focused runs after the full runner had passed its earlier tutorial checks.
## October 6 faster-speed validation

The complete `tests/run.ps1` regression finished with exit 0 and `VALIDATION PASS` on Godot 4.6.1 after the speed, Apex, police and concurrent audit fixes were integrated. The runner rejected engine/script errors and warnings. SHA-256 snapshots of scripts, scenes, shaders, localization, tests and `project.godot` matched before and after the run.

Fresh checks passed no-input Apex overtakes on the rising curve through 120 minutes, truthful race outcomes and exact finish sampling, police pursuit of actual/boosted speed, front/rear traffic contact and police-aware merging. All eight generated Apex races passed with real steering, finite fuel and collisions. World/camera/traffic/radar checks passed at 300/600/1,000/1,600/2,000 km/h; combined Apex/radar/police/traffic ticks passed at 450/600/800/936.8 km/h. Endurance passed eight seeds, 128 km and 200 restarts; Fair, Infinite Boost and Secret each passed 10,800 physics frames with stable memory. Real-input radar braking passed four safe cameras in Fair and three in Infinite Boost without police dispatch. Window-close saving and clean shutdown passed. This receipt validates the Godot project source; package verification is separate.

## Remaining balance acceptance

Automated accelerated simulations establish state, collision, generation and resource behavior. They do not substitute for a human 30-minute skill/balance session or physical-phone performance. The October 6 follow-up checks road, camera, continuing traffic generation and reactive radar braking through 2,000 km/h; generation-only checks reach the 7,140 km/h technical motion ceiling and exercise the component at 8,000 km/h. Combined actual Apex/radar/police/traffic checks cover 450/600/800 km/h and 800 plus Boost. These component checks do not establish human playability at extreme speeds. Earlier ZIP and benchmark receipts above describe their original builds; they do not verify this follow-up source.

## Useful Stage Three work

Use player run telemetry to tune police positioning and late-run mixed-wave recovery frequency; test the expanded road budget on a physical Android device. Extend full gameplay interaction sessions beyond the current combined scenarios if players consistently survive that long.
