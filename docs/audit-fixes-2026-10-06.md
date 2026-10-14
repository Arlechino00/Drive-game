# October 6 audit fixes

The follow-up preserves the faster survival curve and integrates corrections for the reproduced audit issues.

- Legal radar braking and low posted limits stay ranked. Crawling below the lesser of 72 km/h and 55% of cruise outside radar/limit/recovery exemptions has 20 seconds of accumulated grace; a warning appears at 15 seconds. Five seconds of normal pace restores grace. Exceeding grace leaves driving and Boost usable but excludes that round from personal and named records, with a persistent localized HUD badge and result explanation.
- Valid rounds settle once before Menu, Restart and Quit, as well as on game over. Practice, disqualification and unranked rounds cannot write records. A resumed Secret round retains its separate partition and the prior partition stays unchanged.
- Desktop window/application focus loss pauses the round and clears held touch inputs and steering momentum. Returning requires explicit resume. Controller D-pad/A/B/Start support menus, accepting, tutorial Skip, Back and pause/resume while preserving keyboard mappings.
- Each round still starts live coaching, with a separate gated sySTEMatic introduction. Brake/Boost demonstrations and the finish delay are shorter. Skip/finish preserve the car, camera and road pose while resetting practice scores, normal encounter seeds and the driving clock. Public Secret guidance directs players to the sySTEMatic Robotics team.
- Capture danger, fines and impacts take priority over routine bonus text. A 64-beat, 34.91-second synthesized arrangement varies harmony and melody across eight phrases; one reused tension layer responds to speed, Heat, capture and Apex. Generated music is cached rather than rebuilt on restart.
- The finite road/traffic/camera budget remains 2,400 m with 66 road chunks and at most 20 traffic actors. The growing target curve remains uncapped, while actual player motion is limited to 7,140 km/h, retaining 1.2 seconds plus footprint room inside that budget. Spawn placement remains productive even when the component is directly tested beyond this bound. AI receives the bounded cruise baseline and retains its real closing advantage.
- Apex wave-drain fixes from the concurrent speed work allow fresh traffic and earned fuel during a race. Both seeds pass all 4–7-second requirements with finite fuel, real near misses, positive winning lead and the original countdown/race duration. Finish-frame ordering prevents later hazards from changing an already finished race.
- Police handle swept front and rear traffic bumper contacts and reconstruct the correct traffic endpoint for each internal substep. Rear impacts transfer velocity at physical contact. Incoming mixed-traffic merges also check active police footprints. Capture/escape timers, role speeds and finite steering/throttle behavior are preserved.

## Validation

The complete `tests/run.ps1` suite finished with exit 0 and `VALIDATION PASS`: 67 fresh engine logs, no script/engine errors or warnings. A before/after hash comparison of scripts, scenes, shaders, localization, tests and project configuration confirmed that the source stayed unchanged throughout validation. Fair, Infinite Boost and Secret each passed 10,800 physics frames; endurance covered eight seeds, 128 km and 200 restarts. Real-input braking cleared four radars in Fair and three in Infinite Boost with no fines. The actual window-close path persisted the valid round before stopping audio and exiting.

All eight generated Apex races passed with ordinary finite fuel and earned refills, including both seven-second targets. Combined actual game ticks passed at 450/600/800/936.8 km/h with simultaneous Apex, fresh traffic, a swept radar fine and pursuit. Generation continued at the technical ceiling and in the directly exercised 8,000 km/h component case. Police regressions cover front/rear contacts, substeps, incoming merges and retry after clearance.

Controller and UI/audio checks passed headless and rendered. Coaching captures passed 88 English/Romanian desktop/mobile views with 60 images; four additional 854×480 views verified the localized ranking badge and critical warning. Representative desktop and mobile captures were inspected.

Windows export and extracted-ZIP checks passed valid external event configuration, invalid configuration and bundled fallback. Delivered package: `.godot/releases/SynthwaveDrive-AuditFixes-Windows64.zip` (executable, PCK, configuration, instructions and notices). SHA-256: `8b09cc26697f7c8e6675fe3cb7e40766db52cc3c15f1df3900c705dc8e7012db`.

Automated input and desktop-rendered phone layouts do not verify physical controller feel, native phone performance or sound balance by ear. A human 30-minute balance session remains useful.
