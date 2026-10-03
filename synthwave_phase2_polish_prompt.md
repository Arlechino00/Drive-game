# Codex Prompt — Phase 2 Polish, Content & Game Feel

Continue development of the existing synthwave endless driving game.

The basic MVP should already exist or be mostly functional.

Do NOT rebuild the project from scratch.

First inspect the repository, understand the existing architecture, read `README.md`, `agents.md`, and the current implementation, then improve the existing game incrementally.

The goal of this phase is to turn the functional prototype into a polished, satisfying arcade game with stronger game feel, more varied gameplay, better procedural generation, traffic, near-miss mechanics, boost systems, and a much stronger synthwave presentation.

Preserve working systems unless there is a clear technical reason to replace them.

---

# PRIMARY GOAL

Transform the current prototype from:

> basic endless driving demo

into:

> polished synthwave arcade endless racer

The game should feel:

- fast
- responsive
- readable
- stylish
- satisfying
- replayable
- progressively more intense

Do not prioritize feature count over quality.

Every system added should improve one of:

- moment-to-moment gameplay
- visual feedback
- sense of speed
- risk/reward
- replayability
- atmosphere

---

# BEFORE MAKING CHANGES

Inspect:

- current scene structure
- player controller
- road generation
- obstacle spawning
- scoring system
- difficulty system
- UI
- save system
- environment
- camera
- materials
- audio setup
- current project settings
- `agents.md`

Identify:

- what already works
- what feels unfinished
- obvious bugs
- architectural weaknesses
- opportunities for polish

Do not assume the original design is still exactly correct.

The current repository is the source of truth.

---

# DEVELOPMENT ORDER

Use roughly this order:

1. Stabilize existing systems
2. Improve driving feel
3. Improve traffic and obstacles
4. Add near-miss gameplay
5. Add boost / risk-reward mechanics
6. Improve procedural variation
7. Improve difficulty pacing
8. Improve visuals
9. Improve camera and motion feedback
10. Improve UI feedback
11. Improve audio architecture
12. Optimize and clean up

Test after every major subsystem.

---

# 1. DRIVING FEEL

Improve the player controller without turning it into a simulator.

The car should feel precise and responsive.

Focus on:

- smooth steering
- responsive lateral acceleration
- controlled deceleration
- subtle inertia
- stable road positioning
- predictable handling at high speed

Avoid:

- excessive sliding
- sluggish steering
- physically realistic tire simulation
- unpredictable momentum

Add visual steering feedback such as:

- body roll
- slight yaw
- wheel steering angle
- subtle suspension response
- camera offset
- lateral lean

The visual body may move slightly differently from the collision/control body if that produces better game feel.

Gameplay precision has priority over realism.

---

# 2. SPEED FEEL

Improve the sensation of speed.

Possible techniques:

- dynamic FOV
- stronger roadside parallax
- repeating neon markers
- road-line animation
- speed streaks
- particles
- stronger environmental motion
- engine pitch scaling
- subtle camera vibration at high speed

The player should clearly feel the difference between:

- low speed
- cruising speed
- high speed
- boost speed

Do not rely only on the displayed speed number.

---

# 3. TRAFFIC SYSTEM

Implement or improve moving traffic.

Traffic should create interesting decisions rather than random clutter.

Possible traffic types:

- normal car
- slow vehicle
- fast vehicle
- vehicle changing lane
- wide vehicle
- paired vehicles
- occasional dangerous traffic pattern

Traffic should:

- remain readable
- avoid spawning unfairly
- avoid teleporting visibly
- respect lane logic
- avoid impossible walls unless intentionally creating a reaction window

Use pooling where appropriate.

Traffic should be cheaper and simpler than realistic AI.

It only needs enough behavior to create believable highway motion.

---

# 4. TRAFFIC BEHAVIOR

Add limited behavioral variety.

Potential behaviors:

- stay in lane
- slowly change lane
- drift between lanes
- spawn as a small convoy
- temporarily block one route
- move slower or faster than nearby traffic

Lane changes must be telegraphed enough to remain fair.

Avoid chaotic random switching.

The game should reward attention, not luck.

---

# 5. NEAR-MISS SYSTEM

Implement a proper near-miss mechanic.

A near miss happens when:

- the player passes very close to a traffic vehicle or obstacle
- there is no collision
- the relative movement confirms that the player has actually passed the object

Do not repeatedly trigger a near miss while the player remains beside an object.

Each eligible object should award at most one near-miss event per pass.

Possible scoring:

Near Miss:
+100

Very Close:
+250

Extremely Close:
+500

Exact values are tunable.

Provide strong feedback:

- HUD text
- small score popup
- sound effect hook
- brief visual pulse
- multiplier increase

Avoid intrusive full-screen effects.

---

# 6. COMBO / MULTIPLIER SYSTEM

Add a combo system based primarily on risky but successful driving.

Actions that can increase combo:

- near misses
- consecutive close passes
- driving at high speed
- maintaining boost
- passing groups of traffic cleanly

Example:

x1.0
x1.5
x2.0
x3.0
x5.0

The multiplier should decay or reset when the player:

- drives safely for too long
- slows dramatically
- hits something
- crashes

Tune it so skilled aggressive driving is rewarded.

Do not make ordinary survival worthless.

---

# 7. BOOST SYSTEM

Add an arcade boost system.

Preferred concept:

The player earns boost by taking risks.

Possible boost sources:

- near misses
- high-speed driving
- combo chains
- collecting energy pickups

Avoid requiring pickups as the only method.

Boost input:

- Shift
- Space
- controller trigger/button if supported

When boosting:

- speed rises clearly
- FOV increases slightly
- engine/audio intensity rises
- visual streaks intensify
- neon effects become stronger
- boost meter drains

Boost should feel exciting but controllable.

---

# 8. BOOST RISK

Boost should introduce additional risk.

Examples:

- reduced steering margin
- faster obstacle approach
- increased difficulty maintaining combo
- harder lane changes

Do not make controls artificially bad.

The risk should come primarily from speed.

---

# 9. PROCEDURAL ROAD VARIATION

Improve road generation while keeping it reliable.

Add controlled variety such as:

- straight sections
- wide sweeping curves
- slight elevation changes
- tunnel sections
- bridge sections
- neon gate sections
- city-edge sections
- open-grid desert sections

Do NOT generate arbitrary spline chaos.

Procedural generation must remain predictable and testable.

Prefer authored modular chunks assembled procedurally.

---

# 10. ROAD CHUNK SYSTEM

Expand road chunks into reusable categories.

Possible categories:

- Straight
- CurveLeft
- CurveRight
- Tunnel
- Bridge
- City
- OpenLandscape
- HazardSection
- RestSection

Each chunk may define:

- length
- lane layout
- spawn points
- decoration points
- allowed obstacle types
- difficulty weight
- biome/style tag

Avoid hardcoding every road chunk into one manager.

Use metadata/resources where appropriate.

---

# 11. FAIR PROCEDURAL GENERATION

Generation must never create impossible situations.

Before spawning obstacle layouts, validate that:

- at least one valid path remains
- traffic combinations are avoidable
- player reaction time is reasonable
- lane changes are physically possible
- boost does not become mandatory for survival

Difficulty should come from pressure, not unfairness.

---

# 12. DIFFICULTY DIRECTOR

Upgrade the difficulty system from simple speed scaling to a broader difficulty director.

Possible difficulty variables:

- player speed
- traffic density
- obstacle density
- traffic behavior complexity
- lane-change frequency
- special sections
- spacing
- recovery windows

Do not increase everything simultaneously.

Create waves of intensity.

Example pacing:

Calm
→ Moderate
→ Intense
→ Short recovery
→ More intense
→ Special section
→ Recovery
→ Escalation

This produces better flow than permanently increasing density.

---

# 13. DIFFICULTY CURVE

Aim for:

Early game:
- easy to understand
- forgiving
- establishes rhythm

Mid game:
- faster
- more traffic
- frequent near-miss opportunities
- more complex patterns

Late game:
- high speed
- dense but fair traffic
- more advanced combinations
- boost becomes strategically valuable

Avoid sudden unexplained spikes.

Use tunable values.

---

# 14. SYNTHWAVE VISUAL PASS

Improve the visual identity significantly.

The game should immediately communicate synthwave.

Use a coherent visual language:

- deep dark sky
- purple/magenta
- cyan
- orange/sunset accents
- emissive materials
- neon highway
- glowing grid
- retro sun
- distant silhouettes
- atmospheric haze

Do not simply make everything glow.

Use contrast.

Dark surfaces make neon elements more effective.

---

# 15. SYNTHWAVE SUN

Create a large stylized sun on the horizon.

Desired style:

- orange/pink gradient appearance
- horizontal slicing/banding if practical
- positioned low on the horizon
- visually dramatic but not distracting

It may be implemented using:

- billboard mesh
- shader
- layered geometry
- viewport texture

Choose the simplest robust implementation.

---

# 16. DISTANT ENVIRONMENT

Improve distant scenery.

Possible elements:

- low-poly mountains
- futuristic skyline
- glowing towers
- grid plane
- distant pylons
- floating geometric structures
- giant neon signs

Use silhouettes and repetition efficiently.

Distant scenery should create depth without heavy geometry.

---

# 17. ROADSIDE DECORATION

Add reusable roadside props.

Examples:

- neon pillars
- holographic signs
- glowing arrows
- light gates
- pylons
- roadside grids
- geometric sculptures
- synthwave palms if appropriate

Use controlled randomization.

Avoid visual clutter.

---

# 18. VISUAL BIOMES

If architecture allows, introduce a small number of visual themes.

For example:

## Neon Desert
- grid landscape
- mountains
- sunset

## Cyber City
- skyscraper silhouettes
- neon billboards
- denser lighting

## Neon Tunnel
- enclosed geometry
- repeating lights
- strong speed sensation

Do not build many biomes.

Two or three strong themes are better than many weak ones.

---

# 19. TRANSITIONS BETWEEN SECTIONS

Avoid abrupt visual changes.

Use transition chunks when needed.

Examples:

- highway entering tunnel
- desert approaching city
- bridge leading into open highway

Transitions should feel intentional.

---

# 20. MUSIC-REACTIVE VISUAL ARCHITECTURE

Prepare a system for visuals reacting to music.

Actual advanced beat detection is optional.

A simple implementation may use:

- audio spectrum data
- amplitude
- predefined beat events
- BPM timing

Possible reactions:

- road lights pulse
- grid intensity changes
- sun brightness changes
- roadside gates pulse
- UI glow subtly reacts

Do not make flashing excessive.

Do not compromise accessibility or visibility.

---

# 21. AUDIO FEEDBACK

Improve audio hooks.

Important sounds:

- engine loop
- engine pitch by speed
- boost sound
- near miss
- combo increase
- collision
- UI selection
- restart
- tunnel ambience

If assets are unavailable, create the architecture and placeholder hooks.

Do not download copyrighted music.

---

# 22. CAMERA POLISH

Improve the chase camera.

Possible behaviors:

- smooth lateral follow
- slight steering lag
- dynamic FOV
- subtle pitch adjustment
- boost pullback
- collision shake
- speed vibration

Avoid excessive smoothing that causes input latency.

The car must still feel directly controlled.

---

# 23. CAMERA SHAKE

Use camera shake sparingly.

Good events:

- collision
- boost activation
- heavy near miss
- high-speed environmental event

Avoid continuous aggressive shake.

Create reusable shake logic rather than duplicate implementations.

---

# 24. CRASH FEEDBACK

Improve crash feedback.

Possible sequence:

1. impact
2. brief camera shake
3. quick slowdown
4. sparks/particles
5. short freeze or time scale effect
6. Game Over UI

Keep it short.

Restart should be fast.

Do not create long unskippable crash animations.

---

# 25. PARTICLE EFFECTS

Use particles for:

- wheel trails
- boost
- sparks
- road dust
- collision
- speed effects

Particles should be inexpensive.

Pool or reuse effects where useful.

---

# 26. HUD POLISH

Improve HUD readability.

Display:

- score
- speed
- multiplier
- boost meter
- near-miss notifications

Use synthwave styling without sacrificing clarity.

Avoid overly decorative fonts if they reduce readability.

---

# 27. FEEDBACK POPUPS

Create subtle world/HUD feedback such as:

NEAR MISS
+250

COMBO x3

BOOST READY

NEW BEST

Animate using:

- scale
- fade
- slight movement

Do not create large intrusive popups during intense driving.

---

# 28. HIGH SCORE

Ensure persistent high score works reliably.

Consider tracking:

- best score
- longest distance
- highest combo
- top speed

Do not require an account or backend.

Use local storage.

---

# 29. GAME OVER SCREEN

Improve Game Over screen.

Show:

- final score
- best score
- distance
- top combo
- optional near-miss count

Provide:

- Restart
- Main Menu

Keyboard restart should remain fast.

---

# 30. START SCREEN

Improve the initial menu enough to establish atmosphere.

Possible elements:

- title
- moving background road
- synthwave skyline
- start button
- controls
- settings
- quit

Do not spend excessive effort on menu systems yet.

---

# 31. SETTINGS

Add simple settings if practical.

Useful settings:

- master volume
- music volume
- SFX volume
- screen shake strength
- bloom/effects quality
- fullscreen
- resolution if relevant

Persist settings locally.

---

# 32. ACCESSIBILITY

Avoid overly aggressive flashing.

If strong screen effects are used, expose settings such as:

- screen shake amount
- bloom intensity
- flashing effects
- motion effect intensity

Controls should remain understandable.

---

# 33. RANDOM SEEDS AND DEBUGGING

Add support for reproducible procedural seeds if practical.

This is useful when debugging impossible or broken sequences.

A debug mode may display:

- current seed
- difficulty
- active road chunk
- traffic count
- current speed
- combo
- FPS

Do not expose debug UI in normal gameplay unless toggled.

---

# 34. PERFORMANCE

Review performance after visual polish.

Watch for:

- too many active nodes
- too many materials
- shader complexity
- excessive particles
- unnecessary process callbacks
- repeated scene-tree searching
- road chunks not recycling
- traffic accumulation
- audio instances accumulating

The game should remain stable during long runs.

Test several minutes of continuous gameplay.

---

# 35. OBJECT POOLING

Use pooling for frequently spawned objects when beneficial.

Candidates:

- traffic
- obstacles
- road chunks
- particles
- score popups

Avoid building a giant generic pooling framework if simple local pools are enough.

---

# 36. SIGNAL / EVENT ARCHITECTURE

Use events/signals where appropriate for:

- near miss
- collision
- combo change
- boost activation
- speed change
- game over
- score update

Avoid hard dependencies where every system directly searches for every other system.

---

# 37. CODE CLEANUP

After implementing features:

- remove dead code
- remove abandoned experiments
- consolidate duplicated constants
- fix warnings
- simplify overcomplicated functions
- rename confusing variables
- document non-obvious systems

Do not refactor unrelated working code purely for style.

---

# 38. USE AGENTS APPROPRIATELY

Follow `agents.md`.

For substantial independent work, use sub-agents where this improves speed or review quality.

Good candidates include:

- procedural road system
- traffic system
- visual environment
- UI
- debugging
- performance review

Avoid overlapping edits.

The primary agent must review and test all delegated work.

If stuck after reasonable debugging attempts, follow the escalation process in `agents.md`.

If available and genuinely useful, Claude Opus 5.5 Medium may be consulted as a second opinion.

Any external recommendation must be independently verified before integration.

---

# 39. DO NOT DESTABILIZE THE MVP

At every stage, preserve the core loop:

Launch
→ Start
→ Drive
→ Avoid traffic
→ Score
→ Crash
→ Restart

If a new system breaks this loop, fix it before continuing.

Do not stack polish on broken fundamentals.

---

# 40. SUCCESS CRITERIA

This phase is successful when the game:

- feels substantially faster and more responsive
- visually reads as synthwave immediately
- contains moving traffic
- contains fair procedural variation
- rewards near misses
- has a combo/multiplier system
- has a satisfying boost mechanic
- has stronger camera feedback
- has polished HUD feedback
- has clear difficulty progression
- maintains stable performance
- remains easy to restart and replay

The result should feel like a small but coherent arcade game rather than a technical demo.

---

# 41. OPTIONAL STRETCH GOALS

Only attempt these after the core polish pass is stable:

- alternate player cars
- vehicle color selection
- unlockable cosmetics
- drifting-style bonus sections
- special challenge segments
- score attack mode
- timed mode
- procedural weather
- rain reflections
- police chase event
- rare high-speed supercar traffic
- giant moving hazards
- collectible synthwave cassette tapes
- achievements
- controller rumble
- Steam-ready save structure

Do not prioritize stretch goals over stability.

---

# 42. FINAL REVIEW

Before considering this phase complete:

1. Run the game from a clean launch.
2. Verify menus.
3. Verify steering.
4. Verify collisions.
5. Verify procedural generation.
6. Verify traffic.
7. Verify near misses.
8. Verify combo behavior.
9. Verify boost.
10. Verify pause.
11. Verify Game Over.
12. Verify restart.
13. Verify high score persistence.
14. Test a longer continuous run.
15. Check for node/resource growth.
16. Review Godot errors/warnings.
17. Review source-control diff.
18. Update README.md.

Do not claim completion if major runtime errors remain.

---

# FINAL DESIGN PRINCIPLE

The player should constantly feel:

> "I can safely survive... but I could go faster."

Risk should create reward.

Speed should create excitement.

Near misses should feel intentional and satisfying.

The synthwave aesthetic should amplify the gameplay rather than replace it.

Build toward a game that encourages the player to immediately press Restart after crashing.
