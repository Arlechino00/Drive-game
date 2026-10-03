# Codex Prompt — Synthwave Endless Driving Game

I want you to build a playable 3D synthwave endless driving game from scratch.

Use **Godot 4.x with GDScript** unless the existing repository already clearly uses another appropriate engine/framework. The game should be designed as a small, clean, expandable arcade project rather than a realistic driving simulator.

## High-level concept

Create a 3D endless arcade driving game with a strong synthwave / retro-futuristic visual identity.

The player controls a car driving continuously forward along an endless neon highway. The objective is to survive as long as possible, avoid obstacles and traffic, and achieve a high score.

The game should feel fast, responsive, visually striking, and easy to understand.

Think:

- neon highway
- dark purple/night environment
- glowing road markings
- retro grid
- synthwave sun
- low-poly distant mountains/city silhouettes
- obstacles appearing ahead
- increasing speed
- endless procedural road
- arcade handling rather than realistic vehicle physics

Do not attempt a realistic racing simulator.

The first goal is a polished playable MVP.

---

# CORE GAMEPLAY

The basic gameplay loop should be:

1. Player starts driving automatically.
2. The car constantly moves forward.
3. Player steers left and right to avoid obstacles.
4. Obstacles and/or traffic appear ahead.
5. Score increases based primarily on distance survived.
6. Game gradually becomes faster and more difficult.
7. Collision with a major obstacle causes Game Over.
8. Player can immediately restart.

Controls:

- A / Left Arrow = steer left
- D / Right Arrow = steer right
- optionally support controller left stick
- Escape = pause/menu
- R = restart after death

The controls should feel responsive and arcade-like.

Do not make steering overly realistic or sluggish.

---

# PLAYER CAR

Create a simple player car controller.

The player car should:

- automatically move forward
- move smoothly left/right
- remain constrained to the road
- have acceleration in lateral movement rather than snapping instantly
- smoothly return/settle after steering
- have an arcade feeling

You may implement the illusion of forward movement either by:

A. moving the player forward through the world,

or

B. keeping the player relatively stationary and moving road/environment objects toward the player.

Choose whichever architecture is cleaner for an endless runner.

Prefer a system that makes endless road generation and floating-point stability easy.

The car should have:

- collision detection
- visible body/model
- headlights or neon accents
- subtle suspension/body lean when steering if easy to implement
- optional wheel animation if practical

Use primitive geometry or generated placeholder meshes if there are no art assets.

Do not block development waiting for external assets.

---

# ENDLESS ROAD SYSTEM

Create an endless road using modular road segments.

Road segments should:

- spawn ahead of the player
- recycle or despawn after passing behind the player
- support object pooling where reasonable
- connect seamlessly
- contain spawn points for obstacles

Prefer reusable road chunks rather than creating unlimited geometry.

Example structure:

RoadSegment
- Road mesh
- Road markings
- Left boundary
- Right boundary
- ObstacleSpawnPoints
- DecorationSpawnPoints

Initially the road can be mostly straight.

Architecture should allow future additions such as:

- curves
- hills
- intersections
- tunnels
- bridges
- special sections

But do NOT implement all of those now.

The MVP should prioritize reliability.

---

# OBSTACLES

Create an obstacle spawning system.

Initial obstacle types can include:

- road barriers
- stationary vehicles
- neon blocks
- construction objects

Obstacle placement must always leave a theoretically survivable route.

Avoid impossible obstacle layouts.

Use either:

- lanes

or

- controlled random X positions

depending on whichever produces more reliable gameplay.

Start simple.

Obstacle density should increase gradually with difficulty.

---

# OPTIONAL TRAFFIC

If it can be implemented without destabilizing the MVP, add simple traffic cars.

Traffic cars:

- move in the same general direction
- travel slower than the player
- can occupy different lanes
- count as collision obstacles

Traffic AI does not need realistic driving behavior.

If traffic significantly complicates the first implementation, finish stationary obstacles first.

---

# COLLISIONS AND GAME OVER

When the player hits a major obstacle:

- stop normal gameplay
- show a Game Over UI
- display final score
- display best score if implemented
- allow instant restart

Add a short impact effect if easy:

- camera shake
- brief slowdown
- particle burst
- screen flash

Do not create elaborate destruction physics for the MVP.

---

# SCORE SYSTEM

Score should primarily be based on distance/time survived.

Display:

- current score
- current speed
- optional high score

Example:

SCORE 012450
SPEED 184 KM/H

Store the high score locally using Godot's save/config system.

Do not require an online backend.

---

# DIFFICULTY PROGRESSION

Difficulty should increase gradually.

Possible variables:

- forward speed
- obstacle spawn frequency
- number of simultaneous obstacles
- traffic frequency

Use a clear difficulty curve.

For example:

Initial speed:
moderately fast but manageable.

Over time:
speed slowly increases.

Eventually:
speed reaches a reasonable cap.

Difficulty should not become impossible after only a few seconds.

Create tunable constants/configuration values rather than scattering magic numbers throughout the code.

---

# SYNTHWAVE VISUAL STYLE

The visual identity is important.

Create a synthwave aesthetic using Godot materials, lighting, world environment, and post-processing.

Target look:

- dark nighttime background
- purple/pink/cyan neon
- emissive road markings
- glowing obstacles
- retro grid elements
- distant mountains or city silhouette
- large stylized synthwave sun near horizon
- bloom/glow
- atmospheric fog if appropriate

Avoid requiring expensive custom assets.

Procedural/simple meshes are acceptable.

Create a visually coherent scene using:

- emissive materials
- WorldEnvironment
- glow/bloom
- fog
- directional or ambient lighting
- sky/background gradient

The game should remain readable.

Gameplay obstacles must stand out clearly from decorative scenery.

Do not sacrifice gameplay visibility for visual effects.

---

# ROAD VISUAL DESIGN

The highway should ideally have:

- dark road surface
- glowing lane markings
- neon edges
- several lanes
- repeating visual elements that emphasize speed

Possible roadside elements:

- glowing poles
- geometric shapes
- wireframe grids
- low-poly mountains
- neon billboards

Keep decorative objects inexpensive to render.

They may be recycled alongside road chunks.

---

# CAMERA

Use a third-person chase camera positioned behind and above the vehicle.

The camera should:

- clearly show upcoming obstacles
- feel fast without being uncomfortable
- smoothly follow player lateral movement
- slightly react to steering
- optionally increase FOV slightly as speed increases

Do not use excessive camera shake.

Add subtle shake only for collisions or major events.

---

# GAME FEEL

Prioritize game feel.

Useful effects include:

- steering body tilt
- speed-based FOV
- road streaks
- particles
- wheel trails
- neon glow
- slight camera lag
- near-ground motion cues

Keep them modular so they can be tuned or removed easily.

Do not over-engineer them before the core loop works.

---

# AUDIO ARCHITECTURE

Set up audio support even if actual music assets are not available.

Create logical audio channels/buses for:

- Music
- Engine
- SFX
- UI

Possible sounds:

- engine hum
- acceleration pitch change
- collision
- menu selection
- score/bonus effect

If no suitable audio files are available, leave clear placeholders and document where assets should be added.

Do not download copyrighted music.

---

# UI

Create a clean synthwave HUD.

During gameplay show:

- Score
- Speed

Optional:

- multiplier
- distance

Game Over screen:

GAME OVER

Score: XXXXX
Best: XXXXX

Press R to Restart

Initial menu can be minimal:

SYNTHWAVE DRIVE

START

EXIT

Do not spend excessive development effort on menus during the first pass.

---

# PAUSE SYSTEM

Add a simple pause screen.

Escape should:

- pause gameplay
- show Resume
- Restart
- Main Menu or Quit if appropriate

---

# PROJECT ARCHITECTURE

Keep the project modular.

A suggested structure:

res://
  scenes/
    main/
    player/
    road/
    obstacles/
    environment/
    ui/
  scripts/
  materials/
  audio/
  assets/
  shaders/
  resources/

Example scene architecture:

Main
├── GameManager
├── World
│   ├── RoadManager
│   ├── ObstacleManager
│   ├── Player
│   └── Environment
├── Camera
└── UI

Use signals/events where appropriate instead of tightly coupling every script.

Potential responsibilities:

GameManager:
- game state
- score
- speed progression
- restart
- game over

PlayerCar:
- steering
- collision
- visual tilt

RoadManager:
- spawn/recycle road segments

ObstacleSpawner:
- obstacle generation
- difficulty scaling

UIManager:
- HUD
- menus
- score display

---

# GAME STATES

Use clear game states.

For example:

MENU
PLAYING
PAUSED
GAME_OVER

Avoid systems continuing to spawn or score while paused or dead.

---

# PERFORMANCE

The game should run smoothly on an ordinary desktop PC.

Use reasonable optimization practices:

- reuse road chunks
- reuse obstacles where practical
- avoid creating thousands of nodes
- avoid expensive per-frame allocations
- keep shaders relatively simple
- use visibility ranges where appropriate

Do not prematurely optimize tiny details.

Focus on correct architecture.

---

# DEBUGGING TOOLS

Create useful debugging options where helpful.

Examples:

- toggle collision shapes
- display current speed
- display number of active road chunks
- optionally show FPS
- difficulty level/debug value

Keep debug features easy to disable.

---

# CODE QUALITY

Write clean, maintainable GDScript.

Requirements:

- meaningful variable names
- comments where logic is non-obvious
- typed variables/functions where practical
- configurable gameplay constants
- small focused scripts
- avoid one giant GameManager script
- avoid unnecessary abstraction

Prefer straightforward code over clever code.

---

# DEVELOPMENT APPROACH

Work iteratively.

Do not try to build every feature simultaneously.

Use this order:

PHASE 1 — BASIC PROTOTYPE

Create:

- Godot project
- test road
- placeholder car
- camera
- forward movement
- left/right steering
- collision boundaries

Verify that driving feels correct.

PHASE 2 — ENDLESS WORLD

Create:

- reusable road segments
- spawning/recycling
- endless movement
- road boundaries

Verify there are no visible gaps or runaway node counts.

PHASE 3 — OBSTACLES

Create:

- obstacle scenes
- obstacle spawner
- collision
- Game Over
- restart

Ensure generated layouts remain playable.

PHASE 4 — GAME SYSTEMS

Create:

- score
- speed display
- difficulty progression
- high score
- pause state

PHASE 5 — SYNTHWAVE VISUAL PASS

Add:

- environment
- glow
- neon materials
- synthwave sun
- distant scenery
- road decorations
- camera effects

PHASE 6 — POLISH

Add appropriate:

- particles
- impact effects
- steering tilt
- speed FOV
- audio hooks
- UI improvements

---

# IMPORTANT DEVELOPMENT RULE

After each major phase, run/test the project before continuing.

Fix errors immediately rather than stacking new features on top of broken systems.

If the environment allows you to run Godot or automated validation, use it.

Inspect error logs.

Do not claim something works without checking it when testing is possible.

---

# PLACEHOLDER ASSETS

You have permission to use:

- primitive meshes
- generated geometry
- simple materials
- procedural environment pieces

Do not stop and ask me for models unless they are genuinely required.

Build a functional prototype first.

External assets can replace placeholders later.

---

# FUTURE SYSTEMS — ARCHITECT FOR THEM, BUT DO NOT IMPLEMENT YET

The architecture should not make these difficult to add later:

- near-miss scoring
- score multipliers
- boost meter
- collectible energy
- multiple cars
- unlockable vehicles
- vehicle stats
- different environments
- procedural road variations
- tunnels
- ramps
- police/chase mode
- moving hazards
- power-ups
- daily challenges
- achievements
- Steam integration
- leaderboards
- music-reactive visuals

Do NOT implement these unless the MVP is already complete and stable.

---

# POSSIBLE FUTURE NEAR-MISS MECHANIC

Leave collision/detection architecture capable of eventually detecting when the player passes extremely close to another vehicle or obstacle without hitting it.

Future behavior could be:

NEAR MISS
+250
MULTIPLIER x2

Do not prioritize this over the core game.

---

# DESIGN PHILOSOPHY

The game should follow this principle:

Simple mechanics + strong game feel + strong visual identity.

I would rather have:

- one polished road
- good steering
- satisfying speed
- reliable endless generation
- readable obstacles
- beautiful synthwave atmosphere

than twenty partially functioning mechanics.

---

# FIRST DELIVERABLE

Start by inspecting the repository/environment.

Then create the initial playable prototype.

The first meaningful milestone should allow me to:

1. launch the project
2. enter gameplay
3. see a synthwave-style road
4. control a car left/right
5. continuously drive forward
6. encounter obstacles
7. collide and die
8. see a score
9. restart immediately

Once that works reliably, continue polishing the MVP.

---

# DOCUMENTATION

Maintain a small README.md containing:

## How to Run
Exact instructions for opening/running the game.

## Controls
Keyboard/controller controls.

## Architecture
Brief description of major scenes/scripts.

## Current Features
What is currently implemented.

## Next Improvements
Good next steps.

Update the README as the project changes.

---

# AUTONOMY

You can make reasonable implementation decisions without asking me about minor details.

When choosing between approaches:

1. favor simplicity
2. favor maintainability
3. favor good game feel
4. favor a working MVP
5. avoid unnecessary dependencies

If something is ambiguous, choose a sensible default and document the decision.

Do not repeatedly stop to ask for approval.

Proceed with implementation, test what you create, fix issues you encounter, and leave the repository in a clean playable state.
