# Game Audit Improvements Implementation Plan

> For agentic workers: use subagent-driven-development for independent work and executing-plans for integration.

**Goal:** Fix the four reproduced bugs and complete the approved gameplay clarity, performance, validation, release, and repository improvements.

**Architecture:** Preserve the current Godot scenes and subsystem APIs. The primary agent owns game integration and settings; independent agents own persistence, Apex/pursuit logic, and release tooling.

**Tech stack:** Godot 4.6.1, GDScript, PowerShell, GitHub Actions.

**Spec:** User approved the preceding audit recommendations with “ok, start these”. Earlier Apex requirements and supplied AGENTS.md remain binding.

**Global constraints:** Preserve original logo artwork, existing modes, random 4–7 second boost requirement and 30 second race. Protect player profiles during validation. Preserve damaged saves before recovery. No backend or unnecessary framework. Keep every subsystem bounded. License choice requires user preference; all other work can proceed.

**Review focus:** Deferred collision ordering, multi-instance saves, fail-closed access codes, actual release contents, real steering and fuel in Apex coverage, cold-start performance, settings persistence.

## Task 1 — Persistence and exported event configuration

- [x] Reproduce corrupted records preventing play and stale leaderboard rows.
- [x] Add safe corruption recovery with preserved backup and atomic cache refresh.
- [x] Resolve external editable event configuration beside exported executable, with bundled fallback and fail-closed invalid configuration.
- [x] Add focused persistence/configuration tests; report integration APIs.

## Task 2 — Apex and police behavior

- [x] Reproduce same-frame close pass incorrectly granting police escape.
- [x] Defer escape confirmation until queued contact results complete, with reset protection.
- [x] Smooth initial Apex acceleration and add a brief countdown while retaining 30 seconds of racing.
- [x] Explain finite-fuel refills in the challenge UI.
- [x] Add generated, multiple-seed Apex victory tests using actual steering and earned finite fuel.

## Task 3 — Release tooling and repository checks

- [x] Add bounded process timeouts to the validation runner and register new tests.
- [x] Add push/PR CI pinned to Godot 4.6.1.
- [x] Add reproducible Windows export preset, build/package script, exported unlock/resume validation, and release workflow.
- [x] Add contributor instructions, changelog, and separate branding asset notice.

## Task 4 — Primary integration and settings

- [x] Fix double pressure for the impact that starts an Apex-loss police chase.
- [x] Refresh leaderboard on opening and integrate recovered/unsaved play as required.
- [x] Add optional rendering quality/resolution settings and persistence tests.
- [x] Add cold normal-traffic frame-time benchmark without prewarming the catalog.
- [x] Curate screenshots and update README; apply chosen source license.

## Task 5 — Verify and publish

- [x] Review each agent change against spec and code quality.
- [x] Run full validation, visual checks, and cold benchmark.
- [x] Build Windows release, exercise exported configuration/unlock/resume, inspect package.
- [x] Independent final review; resolve material findings and rerun affected checks.
- [x] Commit and push authorized work; publish validated Windows package and verify remote checks where available.

## Ownership and integration

| Owner | Files | Interface |
|---|---|---|
| Persistence agent | player_records.gd, secret_access.gd, associated tests | root consumes safe recovery/reload API; release consumes exported config selection |
| Gameplay agent | apex_race.gd, apex_race_ui.gd, police_pursuit.gd, associated tests | root integrates countdown/active race state and deferred escape |
| Release agent | tests/run.ps1, export preset, tools/release scripts, workflows, CONTRIBUTING, CHANGELOG, asset notice | root supplies new test names and validated artifacts |
| Primary | game.gd, game_settings.gd, game_ui.gd, settings/cold benchmark tests, README, docs assets, LICENSE | coordinates all shared interfaces |

Ruling: use the existing project checkout for integration, as requested by the user; do not copy or reset ongoing shared agent work. Keep progress in .godot/validation/audit-improvements-progress.md, a Windows-friendly ignored scratch location.

## Completion evidence

Completed 2026-10-04. Game commit: a10e4bcd9c5497a128adbe4c2cb0c6af9eace70d. Local 39-check suite and independent reviews passed. GitHub validation runs 37164604415 and 37164666322 passed; release run 37164666324 passed and published v0.1.0. The downloaded GitHub Windows ZIP was checksum-verified and passed all three exported configuration/unlock/resume scenarios. Published ZIP SHA256: 0298e05cc2e9554927dfc83b476b04b8542c939b28ffb9b1e423e52b699e17a5.
