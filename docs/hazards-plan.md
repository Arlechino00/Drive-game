# Potholes, roadworks and police aftermath

User-requested behavior: add road holes and work sites closing at most two lanes; the first hole deducts points and speed, another within ten driving seconds ends the run; entering roadworks invalidates the score; traffic crashes leave both vehicles stopped while police arrive alongside.

Implementation defaults: potholes deduct up to 500 points, reduce speed by 18 m/s, and impose a four-second recovery period. The ten-second repeat-hit timer advances only during gameplay, including Infinite Boost, and freezes during pause. Roadworks invalidate only the current run; saved records are preserved. Existing steering, collision sizes, modes, and branding remain intact.

1. Extend pooled obstacle encounters with recognizable potholes and orange roadworks. Keep physical road hazards stationary relative to the road, retain moving traffic, and isolate hazard waves with sufficient spacing so different movement speeds cannot close all escape routes. Keep deterministic seeds and bounded pools.
2. Test and implement score penalties, strict repeat-hit timing, speed recovery, and invalidation. Route distinct hazard events through the game state; no repeated collision rewards or penalties per activation.
3. Add a reusable police aftermath scene: preserve the struck traffic type and stopped player, approach from behind with alternating emergency lights, and park alongside. Animation continues after gameplay ends and resets on restart/menu.
4. Explain hazard warnings and ending reasons in the HUD/results, and frame the stopped vehicles visibly beside the results panel. Records are saved only for valid runs.
5. Validate actual collisions, timer boundaries and pause, both modes, records, reachable mixed encounters, long-run resource bounds, restart during police arrival, and rendered views of hazards and both police endings. Update README.

Ownership: primary agent owns game state, progression, UI, integration tests and docs; encounter agent owns obstacle generation/models and encounter tests; aftermath agent owns the police scene and its focused tests. All delegated output is independently reviewed and run together before completion.

Completed on 2026-10-03. The full Godot 4.6.2 suite and 39 rendered captures pass without script/engine errors or warnings. Actual hazard contacts, strict timer boundaries (including individual physics ticks), paused timers, four-second speed/boost recovery, score-file preservation, both modes, camera framing, and reset behavior are covered. Mixed-speed encounter checks cover 149.6 km and 200 resets; three-minute physics runs retain at most 3,995 scene nodes with stable monitored memory. Police actors retain 149 nodes across reuse. A 600-frame uncapped Infinite Boost render benchmark averaged 261.6 FPS on this laptop GPU. README documents the mechanics and architecture.

Independent read-only review found no critical or important defects. Its minor coverage finding led to explicit restart/menu checks while police are still approaching, including hidden actors, stopped siren, and cleared run invalidation. Sound balance by ear and hands-on difficulty remain subjective play-session checks.
