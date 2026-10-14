# Radar and braking implementation plan

**Goal:** Implement the user's feedback: gradual brakes, 360 km/h boost, randomized unlimited/30/50/70/80/90/120/130/200 km/h sectors, ordinary traffic following limits, occasional radar warnings, fine score points, and 8–16 second police chases. Excessive approach speed must leave too little braking distance even when braking immediately at the warning.

**Architecture:** A small distance-based SpeedEnforcement owns a separate seeded random stream and once-only radar checks. Game owns braking and score/pursuit integration. A reusable RadarDisplay owns HUD and roadside props. Existing collision and Secret pursuit rules remain available.

**Tech stack:** Existing Godot 4.6.1, GDScript; no added dependencies.

- [x] Add rule checks before implementation; validate exact-limit passes, speeding, swept readings, seed replay and random ranges.
- [x] Add braking with priority over boost, reachable 30 km/h speed, pause/restart safety and signed traffic travel at low speed.
- [x] Integrate radar fines as additive score points in all modes; timed pursuits preserve capture priority and deferred outcome ordering.
- [x] Add compact readable HUD, upcoming restriction, radar distance, brake hint, and bounded roadside signs/camera.
- [x] Run integrated input, police, pause, replay and low-speed generation checks; existing regression suite and rendered captures.
- [x] Review changes independently, update controls/README/changelog and report verified results.

**Tuning:** S/down/LT brake to 8 m/s (28.8 km/h), deceleration 7 m/s²; boost gain 38 m/s, maximum 100 m/s (360 km/h). Braking from 300 to 30 km/h takes about 10.7 seconds and 491 m. Warnings stay exactly 320 m before the camera, independent of speed, and do not guarantee a legal pass. Every restriction follows an unlimited recovery sector with at least 1,200 m before the sign. Radar 80–120 m after the sign, present in about 65% of restricted sectors. Ordinary traffic approaches the posted speed at 8 m/s²; unlimited road returns it to 14 m/s. Fine = 100 + ceil(10 × excess km/h). Radar chases use elapsed driving time, sampled uniformly from 8–16 seconds; mistakes close the gap but do not extend the deadline. Police may catch before the deadline. Existing impact chases use their clean-driving/gap escape routes.

**Review focus:** Very low speeds and reverse traffic; crossing radar during braking; simultaneous capture/escape; pause and held brake/boost; overlapping Apex/radar events; deterministic seeded resets; bounded props and obstacle pools.

**Verification:** The initial radar implementation passed 44 checks before the user's extended limits/high-speed braking feedback. Updated real-input checks measured 10.72 seconds and 490.5 m from 300 to 30 km/h and confirmed an immediate brake press at 320 m still triggers radar police. Three-minute runs at the final tuning exercised five police chases per speeding mode, with stable memory; the Fair brake-input run cleared four radars, while the Infinite brake-input run still received five radar pursuits. Complete updated suite and rendered capture results are recorded in README after verification.

**Final result:** All 46 checks passed without Godot errors/warnings; fifteen radar captures passed. Traffic rows now use 80 m minimum spacing and static rows 96 m to retain a 0.7-second footprint steering window at 360 km/h. Both player and actor lateral motion are swept together: the reproduced Apex false collision is covered alongside a genuine collision. Final HUD checks confirm no radar report or visible camera beyond 320 m at maximum speed. README records the complete results.
