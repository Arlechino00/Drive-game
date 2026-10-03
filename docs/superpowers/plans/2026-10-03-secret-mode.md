# sySTEMatic Secret Mode Implementation Plan

> Follow-up requirement: resume codes are now reusable and manually edited beside `access_code` in `config/secret_mode.cfg`. The original one-time issuer/consumption steps below record the initial implementation; they have been replaced by current config validation, updated tests and `docs/local-event-setup.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add named local rankings, an unlockable finite-boost police-chase level, and manually issued one-time resume codes.

**Architecture:** Keep the existing state machine and integrate three focused modules: persistent player/access data, pursuit simulation/visuals, and additional UI. The primary agent owns game state, run damage rules, captures and integration checks. Agents own separate files; all output is reviewed and tested together.

**Tech Stack:** Godot 4.6.2, GDScript, Compatibility renderer, procedural meshes and existing audio.

**Spec:** `docs/superpowers/specs/2026-10-03-secret-mode-design.md`

## Global Constraints

- Existing Fair and Infinite Boost modes retain their current rules and score saves.
- Ranked entries retain the best score for each normalized player name, mode and assistance status, with deterministic ties and a bounded collection.
- Visible Unicode names up to 24 characters are supported.
- Secret Mode is a distinct level of the same endless highway, with stronger police/night accents and earned boost.
- One code-assisted continuation is available per Secret run.
- No deployment, external message, social login or online score service is introduced.

## Review Focus

- Focused text fields must prevent Enter/R/F8 from starting or resetting gameplay unexpectedly.
- Consuming a code must save before gameplay resumes, and never consume a code while ineligible.
- A first high-speed mistake must leave a clean-driving escape path rather than cause unavoidable capture.
- Reused collision objects must not immediately repeat the same impact or multiply police nodes.
- Resumed Secret scores and new driver names must never overwrite ordinary mode rankings or legacy records.

## Tasks and file ownership

### 1. Persistent records and local access (data agent)

Create `scripts/player_records.gd`, `scripts/secret_access.gd`, `tools/issue_resume_code.gd`, focused tests `tests/player_records.gd`, `tests/secret_access.gd`. All tests use their own injected save paths.

Interfaces: records expose `player_name`, `load_records()`, `save_player_name(raw: String) -> Error`, `normalize_name(raw: String) -> String`, `record_run(name: String, mode: int, score: int, distance: float, resumed: bool = false, escapes: int = 0) -> Error`, `top_entries(mode: int, resumed: bool = false, limit: int = 10) -> Array[Dictionary]`. Entries have name, mode, score, distance, resumed and escapes. Access exposes `secret_unlocked`, `configuration_error`, `load_access()`, `unlock(code: String) -> bool`, `issue_resume_code() -> String`, `consume_resume_code(code: String) -> bool`. Read access phrase only from `config/secret_mode.cfg`; no code fallback, fail closed if absent/empty, revoke unlock if config phrase changes. Resume codes are random and single-use. The user confirmed local rankings/manual issuance and hidden access entry.

- [x] Write failing tests for name validation, ordering/partitions/bounds, corrupt saves, correct/incorrect access, issued/consumed/replayed codes and persistence.
- [x] Implement the interfaces, native ConfigFile storage, and the issuer's `--count=1` argument.
- [x] Run focused checks without modifying personal profiles; report exact files and evidence.

### 2. Police pursuit (pursuit agent)

Create `scripts/police_pursuit.gd` and `tests/pursuit.gd`; do not edit existing scripts. Reuse `PoliceAftermath` for police visuals through its public start/reset/advance API. Keep camera/viewport nodes fixed and inactive rendering disabled.

Interfaces: Node3D with signals `caught`, `escaped`; fields `active`, `gap_m`, `clean_seconds`; `begin(player_at: Vector3)`, `advance(delta: float, player_at: Vector3, speed: float, base_speed: float, effects: float = 1.0)`, `register_mistake()`, `register_close_call()`, `reset_pursuit()`, `get_rearview_texture() -> Texture2D`. Root owns player damage and boost; pursuit uses actual speed and finite clean-time/gap thresholds. Begin supplies an approach grace period. Sixteen clean seconds or a gap of 100 m escapes; gap at/below 7 m catches. Start gap 55–70 m as tuned by survivability tests.

- [x] Write failing tests for clean escape, boost gap escape, repeated slowdown capture, close-call resets, deterministic pause by not advancing, effects-off visuals, and 200 reuses.
- [x] Implement tunable pursuit and rear-facing viewport camera that shares the current world; no police collision actors.
- [x] Validate clean recovery curves at both cruise speeds and strong repeat-hit losses. Do not run competing rendered captures.

### 3. Player/access/leaderboard UI (UI agent)

Own `scripts/game_ui.gd`, new `scripts/community_ui.gd`, focused `tests/community_ui.gd`; extend responsive checks only in this agent's tests. Preserve existing method defaults and signals. Add secret mode card hidden until `configure_secret(unlocked: bool)`; mode index 2 gets earned-boost HUD/caption. Add Leaderboard to title. Prefer focused extension rather than substantially growing the existing UI.

Community Node attaches with `attach(base_ui: GameUI)`. Signals: `name_submitted(name: String)`, `secret_code_submitted(code: String)`, `resume_code_submitted(code: String)`, `leaderboard_requested(mode: int, resumed: bool)`. Methods: `request_name(prefill: String)`, `request_access()`, `show_name_error(message: String)`, `show_access_error(message: String)`, `show_resume_error(message: String)`, `set_resume_available(enabled: bool)`, `show_leaderboard(entries: Array[Dictionary], mode: int, resumed: bool = false)`, `set_rearview_texture(texture: Texture2D)`, `update_pursuit(active: bool, gap_m: float, clean_seconds: float)`, `dismiss()`. Public fields include `name_input`, `access_input`, `bribe_input`, name/access/bribe/leaderboard dialogs for integration tests. F8 is routed by root only on title; text modals consume unrelated game shortcuts. Do not assume storage implementation or write game integration.

- [x] Test blank/Unicode names, visible secret card, all modal input/focus, finite Secret HUD, mode ranking tabs/resumed filter, ten long-name rows and responsive bounds at six existing sizes.
- [x] Build the dialogs, leaderboard and rear-view HUD in the existing theme. Resume offer is hidden until eligible; explanatory copy describes manual code issuance.
- [x] Validate headless UI behavior and report API, exact files and remaining visual checks.

### 4. Gameplay integration (primary)

Modify `scripts/game.gd`, `run_progress.gd`, `visual_world.gd` minimally; add `tests/secret_mode.gd`, `tests/secret_capture.gd`; update `tests/smoke.gd`, `tests/run.ps1`, README and operator docs.

- [x] Write guarded failing integration tests before adding modules to the state machine.
- [x] Route title Start/Enter through name entry, validate/save submitted names, then start the existing internal run transition. Restart keeps name.
- [x] Add SECRET = 2; locked selection cannot start Secret; initialize finite boost, distinct lighting, separate record/ranking sections and pursuit reset.
- [x] Route Secret fatal mistakes to a recoverable impact and chase, and repeated mistakes/near misses into pursuit. Permit finite boost during Secret recovery. Pause and state transitions freeze/reset all active modules.
- [x] On escape give 1,000 points, track escapes, stop siren and continue. On catch use the existing police result scene; expose a resume offer only after arrival and before assistance.
- [x] Consume eligible one-time codes, mark assisted, preserve score/distance/name/remaining fuel, clear hazards/police/damage, and continue. Test invalid/replayed/ineligible submissions.
- [x] Run all focused tests, the complete runner and captures, inspect images, check bounded three-minute driving and rendered performance, request a read-only review, fix material findings, document defaults/limitations.

No Git repository is present; pre-change sources are backed up under `.godot/validation/secret_before`. Preserve all unrelated assets and original branding.
