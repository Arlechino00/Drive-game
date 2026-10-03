# agents.md

# Agent Operating Guide — Synthwave Endless Driving Game

This file defines how AI coding agents should work on this repository.

The goal is to keep development fast, coordinated, testable, and maintainable while avoiding duplicated work, conflicting edits, speculative rewrites, and unnecessary complexity.

The primary implementation target is the **Godot 4.x + GDScript synthwave endless driving game** described in the project prompt and README.

---

# 1. PRIMARY AGENT RESPONSIBILITY

The primary agent owns the repository-level result.

It is responsible for:

- understanding the current project state
- planning implementation order
- deciding what should and should not be delegated
- integrating work from other agents
- resolving conflicts
- running validation/tests
- checking Godot errors
- updating documentation
- ensuring the repository is left in a working state

The primary agent must not blindly accept output from another agent.

All delegated work must be reviewed before integration.

The primary agent remains accountable for correctness.

---

# 2. WHEN TO USE SUB-AGENTS

Use sub-agents when parallel work will clearly improve speed or quality.

Good delegation candidates include tasks that are:

- reasonably independent
- clearly scoped
- easy to verify
- unlikely to require simultaneous edits to the same files
- specialized enough to benefit from focused attention

Examples:

## Gameplay agent

Can work on:

- player steering
- arcade movement
- collision behavior
- speed progression
- game-over logic
- near-miss architecture
- input handling

## Endless-world agent

Can work on:

- road chunk spawning
- road recycling
- object pooling
- obstacle spawning
- lane generation
- spawn safety rules

## Visual/environment agent

Can work on:

- neon materials
- synthwave sun
- sky/background
- fog
- glow
- road markings
- decorative scenery
- camera visual effects

## UI agent

Can work on:

- HUD
- score display
- speed display
- pause menu
- game-over menu
- restart flow
- visual UI polish

## Audio agent

Can work on:

- audio bus setup
- engine sound hooks
- pitch logic
- SFX routing
- music integration placeholders

## Code review / debugging agent

Can inspect:

- GDScript errors
- architecture problems
- race/state issues
- duplicated logic
- bad signal wiring
- node lifecycle problems
- performance problems
- scene dependency issues

## Documentation agent

Can update:

- README.md
- controls
- architecture notes
- development notes
- current features
- known issues

---

# 3. WHEN NOT TO USE SUB-AGENTS

Do not delegate merely because agents are available.

Keep a task with the primary agent when:

- it is very small
- it requires constant awareness of many project systems
- multiple files are tightly coupled
- integration cost would be greater than implementation cost
- another agent would likely edit the same files simultaneously
- the issue is already understood and straightforward
- delegating would slow down debugging

Examples of tasks usually better handled directly:

- changing one constant
- renaming one node
- fixing one obvious parser error
- adjusting a single signal connection
- modifying a small function
- resolving a simple scene path issue

---

# 4. AVOID CONFLICTING PARALLEL EDITS

Do not assign multiple agents to edit the same files at the same time unless there is a strong reason.

Before delegation, define ownership.

Example:

Agent A:
- `scripts/player_car.gd`
- `scenes/player/`

Agent B:
- `scripts/road_manager.gd`
- `scenes/road/`

Agent C:
- `scripts/ui_manager.gd`
- `scenes/ui/`

This is preferable to three agents all editing `main.gd`.

When possible, divide work by subsystem.

---

# 5. GIVE AGENTS NARROW, CONCRETE TASKS

Delegated instructions should specify:

- objective
- relevant files
- allowed scope
- constraints
- expected result
- validation requirements

Bad delegation:

> Improve the game.

Good delegation:

> Inspect the current road generation system. Fix visible gaps between recycled road chunks without changing player movement or UI. Keep the existing RoadManager API where possible. Run any available validation and report exactly which files were changed.

Agents should not expand scope without a clear reason.

---

# 6. REQUIRE AGENTS TO INSPECT BEFORE EDITING

An agent should first inspect the relevant implementation.

It must not assume:

- node names
- scene hierarchy
- input action names
- autoload names
- file locations
- signal names
- project architecture

Use the repository as the source of truth.

Do not rewrite functioning systems simply because a different architecture would also work.

---

# 7. PREFER SMALL, REVIEWABLE CHANGES

Agents should prefer incremental changes over large rewrites.

Good:

- fix obstacle spawning
- test it
- then add pooling
- test it
- then tune difficulty

Bad:

- replace the road system, player controller, game manager, and UI simultaneously

Large rewrites are acceptable only when the existing design is fundamentally blocking progress.

If a rewrite is necessary, document why.

---

# 8. TEST AFTER EVERY MEANINGFUL CHANGE

Every agent should verify its own work where possible.

For Godot work, validation may include:

- launching the project
- opening affected scenes
- running the main scene
- checking Godot output/errors
- checking parser warnings
- verifying input
- verifying collisions
- verifying restart flow
- verifying scene instancing
- checking node counts during endless generation

Do not report a feature as working solely because the code looks correct.

If execution is unavailable, say so explicitly.

---

# 9. PRIMARY AGENT REVIEW PROCESS

After receiving delegated work, the primary agent should check:

1. Does it solve the requested problem?
2. Does it preserve existing working behavior?
3. Does it follow project conventions?
4. Did it introduce unnecessary dependencies?
5. Are scene paths and node references correct?
6. Are signals connected correctly?
7. Are gameplay constants tunable?
8. Are there obvious performance problems?
9. Does the project still run?
10. Does documentation need updating?

Only then should the work be treated as complete.

---

# 10. AGENT COMMUNICATION

When agents report back, prefer concise technical summaries.

Reports should include:

- what was changed
- files changed
- assumptions made
- tests performed
- remaining risks
- anything the primary agent should verify

Avoid long speculative essays.

---

# 11. USE SPECIALIST AGENTS FOR DIFFICULT PROBLEMS

For hard problems, a specialist agent may be asked to investigate without immediately modifying files.

Examples:

- intermittent collision bugs
- road chunks occasionally overlapping
- player movement jitter
- unexpected physics behavior
- scene lifecycle problems
- shader issues
- performance degradation over time

A useful pattern is:

1. Ask one agent to investigate.
2. Ask another agent to review the proposed diagnosis if the issue is severe.
3. Let the primary agent choose the fix.
4. Test the integrated result.

This is especially useful when the cause is uncertain.

---

# 12. DEBUGGING ESCALATION POLICY

When stuck, do not repeatedly make random changes.

Use this escalation process.

## Step 1 — Reproduce

Identify:

- exact error
- exact steps that trigger it
- relevant logs
- affected scene/script
- whether it is deterministic

## Step 2 — Inspect

Read the surrounding code and scene configuration.

Check:

- node paths
- signal connections
- lifecycle timing
- input mappings
- physics process vs process usage
- null references
- resource loading
- scene ownership
- state transitions

## Step 3 — Form a hypothesis

State the likely cause before changing code.

Prefer one controlled fix at a time.

## Step 4 — Test the hypothesis

Apply the smallest plausible change.

Run the project again.

If the hypothesis fails, revert or reassess instead of stacking unrelated changes.

## Step 5 — Use another agent

If the primary agent has made reasonable attempts and the issue remains unclear, delegate investigation to a debugging/review agent.

Give that agent:

- symptoms
- logs
- relevant files
- attempted fixes
- observed behavior

## Step 6 — External model escalation

If the problem remains genuinely difficult after reasonable attempts, and the environment provides access to **Claude Opus 5.5**, the primary agent may consult:

**Claude Opus 5.5 — Medium reasoning**

Use it as a second-opinion debugging/design consultant.

Good cases include:

- a difficult architecture dead-end
- a persistent Godot engine issue
- confusing physics behavior
- a bug with no obvious source
- a complex procedural-generation failure
- a subtle state-management issue
- a difficult shader/rendering problem
- a design tradeoff where multiple solutions have serious consequences

Do not call it for trivial work.

---

# 13. HOW TO USE CLAUDE OPUS 5.5

When consulting Claude Opus 5.5 Medium, provide a focused technical brief.

Include:

- the concrete problem
- relevant architecture
- relevant code
- exact error output
- what has already been attempted
- constraints that must be preserved
- the specific question to answer

Example:

> We have a Godot 4 endless-road system that reuses six road chunks. Every few minutes, one chunk appears with a visible gap of approximately 0.5–1 meter. The chunks are repositioned using global_position.z based on the furthest active chunk. Here is RoadManager.gd and the RoadSegment scene structure. We already ruled out inconsistent mesh lengths. Identify the most likely causes and propose the smallest robust fix.

Do not provide the entire repository unless necessary.

---

# 14. CLAUDE OUTPUT IS ADVICE, NOT AUTHORITY

Never copy external-model advice directly into the repository without review.

The primary agent must independently verify:

- APIs exist in the installed Godot version
- proposed syntax is valid GDScript
- node types are correct
- assumptions match this project
- changes do not break existing systems

Claude may be wrong.

Codex may be wrong.

The repository and actual runtime behavior are the final source of truth.

Use external consultation to generate hypotheses, not unquestioned answers.

---

# 15. NEVER HIDE FAILED ATTEMPTS

If an agent attempted a fix that did not work, preserve that knowledge in the active reasoning/context where useful.

Do not repeatedly try the same failed solution.

For difficult bugs, keep a short record such as:

- symptom
- attempted fix
- result
- current hypothesis

This prevents cycling.

---

# 16. PROJECT-SPECIFIC ARCHITECTURAL PRINCIPLES

For this game, prefer:

- modular Godot scenes
- GDScript over unnecessary native extensions
- reusable road chunks
- pooling/recycling over uncontrolled spawning
- signal-based communication where useful
- simple arcade motion
- tunable exported parameters
- visually strong but inexpensive effects
- deterministic game-state transitions

Avoid:

- giant manager scripts
- unnecessary singletons
- deeply nested inheritance
- overly realistic vehicle physics
- dependency-heavy frameworks
- procedural systems that are impossible to debug
- premature online/backend architecture

---

# 17. GAMEPLAY SAFETY RULES FOR PROCEDURAL GENERATION

Agents modifying obstacle generation must preserve playability.

The generator should avoid:

- fully blocked road states
- obstacles spawning directly on the player
- unavoidable combinations
- sudden impossible difficulty spikes
- overlapping collision shapes
- invisible hazards

When randomness is used, prefer seeded/debuggable randomness where practical.

A future debug mode may expose the active seed.

---

# 18. PERFORMANCE RULES

When an agent changes endless systems, verify that resources remain bounded.

Watch for:

- road chunks continually increasing
- obstacles never being freed/recycled
- timers multiplying
- signals connected repeatedly
- particles accumulating
- orphaned nodes
- per-frame allocations
- expensive scene-tree searches inside `_process()`

Endless gameplay should not imply endless node growth.

---

# 19. VISUAL AGENT RULES

Visual polish must not reduce readability.

Gameplay-critical objects should remain easy to identify.

Do not let:

- bloom obscure obstacles
- fog hide hazards unfairly
- emissive road markings overwhelm the screen
- camera effects make steering difficult
- motion effects create nausea
- decorative geometry look like collision hazards

A synthwave aesthetic is important, but gameplay clarity has priority.

---

# 20. KEEP THE MVP FIRST

Do not allow agents to derail the project with speculative feature expansion.

Before adding major extras, the game should reliably support:

- start game
- drive
- steer
- endless road
- obstacles
- collision
- scoring
- game over
- restart
- stable performance

Features such as:

- upgrades
- unlockable cars
- achievements
- online leaderboards
- advanced traffic
- police systems
- multiple biomes
- music-reactive environments

come later.

---

# 21. DOCUMENT IMPORTANT DECISIONS

When an agent makes a non-obvious architectural decision, document it briefly.

Good examples:

- why the world moves instead of the car
- why lanes are used for obstacle spawning
- why a specific pooling system exists
- why a particular node owns difficulty progression

Do not over-document trivial code.

---

# 22. SOURCE CONTROL BEHAVIOR

When source control is available:

- inspect current changes before editing
- avoid overwriting unrelated user work
- keep changes scoped
- do not revert user edits without explicit reason
- review the diff after substantial work

Do not assume uncommitted changes are disposable.

---

# 23. IF THE REPOSITORY ALREADY DIFFERS FROM THE ORIGINAL PLAN

The repository is authoritative.

If implementation has evolved beyond the original prompt:

- inspect what exists
- preserve working systems
- adapt instructions intelligently
- do not force the initial architecture onto a mature codebase

The original project prompt describes intent, not an immutable implementation.

---

# 24. AUTONOMY

Agents may make reasonable implementation decisions without asking the user about minor details.

Do not stop development for choices such as:

- exact variable names
- minor node organization
- small tuning values
- placeholder mesh dimensions
- internal helper functions

Ask only when a decision has major product consequences and cannot reasonably be inferred.

Otherwise choose a sensible default, implement it, and document it.

---

# 25. DEFINITION OF DONE

A task is complete when:

- the requested behavior exists
- implementation is integrated
- obvious regressions are checked
- available tests/validation pass
- no new critical Godot errors remain
- affected documentation is updated when appropriate
- temporary debugging hacks are removed or clearly marked
- the primary agent has reviewed the result

Code existing in a file is not enough.

The feature must work in the project.

---

# 26. DEFAULT WORKFLOW

For substantial tasks, use this loop:

1. Inspect repository.
2. Identify relevant subsystem.
3. Decide whether delegation helps.
4. Assign clearly separated work if useful.
5. Implement the main dependency first.
6. Review delegated results.
7. Integrate.
8. Run/test.
9. Fix failures.
10. Review diff.
11. Update README/docs if needed.
12. Continue to the next milestone.

Keep the repository playable whenever practical.

---

# 27. FINAL PRINCIPLE

Agents exist to reduce uncertainty and parallelize useful work.

They should not create coordination overhead for its own sake.

Use them when they make the project faster, safer, or better.

If stuck:

- reproduce
- inspect
- reason
- test
- ask another agent
- and, when genuinely useful and available, consult **Claude Opus 5.5 on Medium reasoning**

Then independently verify the result before changing the project.
