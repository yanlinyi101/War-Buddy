# RTS MVP Design (Godot 4.x)

Date: 2026-04-01 (initial), revised 2026-04-23 for Godot migration
Project: `war-of-agents` → `War Buddy` (Godot 4.6.x)
Status: Approved. Implementation is the Godot path under `godot/`.

## 1. Goal

Validate a minimum playable RTS/PVP commander prototype inside a Godot 4.x graybox scene (`godot/scenes/main.tscn` → `world.tscn`).

This MVP is not a full RTS and not a full AI-agent gameplay loop. It is a validation slice for the core product idea:

**The player acts as the main commander, directly controls one hero unit, and issues commands to future AI agents (combat squad leader and economy officer) through text and voice-entry UI.**

For this MVP, we validate:
- direct hero control
- command input and command logging
- fake PVP battlefield skeleton
- victory-condition closure

We explicitly do **not** validate:
- real multiplayer networking
- AI command execution
- full economy / construction / production systems
- real voice recognition or voice output

## 2. MVP Scope

### 2.1 Core Experience

The MVP succeeds if a player can:
1. launch the Godot project and enter the graybox battlefield (`main.tscn`)
2. directly control a hero unit, with mouse as the default input
3. move, target, and attack enemy buildings
4. send a text command to either:
   - combat squad leader
   - economy officer
5. see the command recorded and marked as received / pending execution
6. destroy all enemy buildings
7. trigger victory when all enemy buildings are gone

### 2.2 Match Structure

This is a **two-faction fake PVP skeleton**, not real networked PVP.

Included:
- player faction and enemy faction exist in-scene
- enemy buildings are pre-placed in `world.tscn` and can be destroyed
- the match has a clear win condition

Excluded:
- real second player
- enemy AI behavior
- autonomous economy behavior
- autonomous unit production

### 2.3 Win Condition

**Victory condition: destroy all enemy buildings.**

No alternate win conditions are in scope for this MVP.

## 3. Player Interaction Model

### 3.1 Commander Role

The player is not a classic RTS omniscient top-down operator. The player is the **main commander on the field**.

The player:
- directly controls one hero unit
- issues high-level commands to future AI deputies
- experiences both direct action and command-layer interaction

### 3.2 Hero Control Model

The hero uses a **hybrid control model**, with **mouse as the default**.

Required for MVP:
- mouse-first movement / target selection / attack interaction
- compatibility hooks for hybrid keyboard + mouse control
- basic combat interaction against enemy buildings

Not required for MVP:
- advanced combo systems
- final skill kit design
- inventory or progression systems
- multiple hero switching

### 3.3 Deputy Command Channels

Two explicit deputy channels are required:
- **Combat Squad Leader**
- **Economy Officer**

The MVP only needs the command-entry framework, not actual deputy execution.

### 3.4 Voice and Text Input

The MVP must support:
- **text command input** as a functional path
- **voice command entry** as a visible placeholder path

Voice is not implemented yet, but the HUD must clearly indicate where it belongs in the future experience.

## 4. System Design

The implementation is split into five focused Godot modules, each one a single `.gd` script (plus its scene where applicable) under `godot/`.

### 4.1 Hero Control Module (`scripts/hero_controller.gd` + `scenes/commander_hero.tscn`)

Responsibilities:
- receive default mouse input (raycast from `RtsCamera`)
- support hybrid-control extensibility
- move the hero (`CharacterBody3D`)
- select targets via `target_selected` signal
- perform basic attack / interaction actions
- expose current hero state to the HUD and match systems

Non-responsibilities:
- parsing deputy commands
- match victory rules
- AI execution logic

### 4.2 Command Console Module (`scripts/command_log_model.gd` + HUD bindings in `hud_root.gd`)

Responsibilities:
- provide explicit channels for combat and economy deputies
- accept text command input
- log command metadata
- maintain command lifecycle states (timed progression, not instant)
- expose recent command history to the HUD
- expose a voice-entry placeholder state
- emit `command_added` / `command_status_changed` signals

Minimum command states:
- submitted
- received
- pending execution

Minimum command object fields (Dictionary entries):
- `id`
- `channel`
- `text`
- `created_at`
- `status`

Non-responsibilities:
- natural-language understanding
- deputy execution
- multi-agent orchestration

### 4.3 Match State Module (`scripts/match_state.gd`)

Responsibilities:
- register enemy buildings
- track building destruction (one-shot per id)
- determine when all enemy buildings are destroyed
- trigger victory via `victory_triggered` signal
- lock match-end state when needed

Minimum building state fields:
- `id`
- `faction`
- `hp`
- `is_destroyed`

Minimum match-state fields:
- `enemy_buildings_remaining`
- `is_victory`
- `is_match_locked`

Non-responsibilities:
- networking
- enemy AI
- real economy simulation

### 4.4 Scene Bootstrap Module (`scripts/bootstrap.gd`, attached to `scenes/main.tscn`)

Responsibilities:
- wire the MVP systems together on scene load
- instance and bind the hero
- register enemy buildings from `world.tscn`
- connect HUD anchors and command UI anchors
- validate required references and fail loudly on missing bindings

Non-responsibilities:
- redesigning the entire scene
- introducing unrelated scene refactors

### 4.5 MVP HUD / UI Layer (`scripts/hud_root.gd` + `scripts/hero_state.gd`)

Responsibilities:
- show minimum hero status (HP, target, action) via `hero_state.gd`
- show deputy command channels
- provide text `LineEdit`/`Button` command submission
- provide voice-entry placeholder button
- show command log and command status
- show victory overlay and lock input after victory

Non-responsibilities:
- final art polish
- full RTS production UI
- full chat system
- minimap or advanced overlays

## 5. In-Scope Features

### 5.1 Hero Gameplay

Must include:
- hero is present and bound on scene load
- hero can be controlled with mouse-first interaction
- hero can move
- hero can acquire a target
- hero can attack enemy buildings
- hero state has minimum HUD feedback

### 5.2 Command System

Must include:
- combat and economy channels are visible and distinct
- player can enter a text command
- player can submit a command to a selected channel
- command appears in command history
- command status is visible and advances over time

### 5.3 Voice Placeholder

Must include:
- visible voice button / entry affordance
- clear non-deceptive placeholder message, such as:
  - "Voice command coming soon"
  - or "Current MVP supports text commands only"

### 5.4 Fake PVP Battlefield

Must include:
- enemy buildings exist in `world.tscn`
- enemy buildings take damage (`hp_changed` signal)
- enemy buildings can be destroyed (`destroyed` signal)
- match state updates when buildings are destroyed
- victory triggers when all enemy buildings are gone

### 5.5 Victory Feedback

Must include:
- clear victory overlay on the HUD
- post-victory state lock for hero input

## 6. Explicitly Out of Scope

The following are intentionally excluded from this MVP:
- real multiplayer / real two-player sync
- autonomous AI deputy behavior
- command interpretation by LLMs
- full economy loop
- construction loop
- autonomous harvesting
- production / barracks / unit training
- advanced combat systems
- complete hero skills
- voice recognition
- TTS or spoken deputy responses
- full HUD production-grade presentation
- NavigationAgent3D pathfinding (currently direct-move raycast)

## 7. Error Handling and Edge Cases

### 7.1 Hero Control

Handle:
- clicking unreachable terrain
- clicking invalid targets
- control input after victory
- missing hero binding on scene load
- clicks over HUD elements (must not leak into world orders)

Expected behavior:
- invalid or unreachable actions fail safely with light feedback
- post-victory control is locked or suppressed
- missing binding fails early and visibly during bootstrap
- HUD consumes input before raycast is issued

### 7.2 Command Console

Handle:
- empty input
- no channel selected
- overlong text
- rapid consecutive submissions
- UI state not refreshing after submission

Expected behavior:
- empty command cannot be submitted
- channel selection is explicit (preferred) or has a deterministic default
- command history is driven from one authoritative model (`CommandLogModel`)
- submissions remain ordered and visible

### 7.3 Voice Placeholder

Handle:
- player clicking voice input expecting functionality

Expected behavior:
- clear placeholder messaging
- no fake recording flow
- no misleading "active" interaction state

### 7.4 Victory Logic

Handle:
- last building destroyed but victory not triggered
- destroyed building still counted as alive
- enemy building missing registration in `MatchState`
- multiple victory triggers firing

Expected behavior:
- one authoritative destruction path (`EnemyBuilding.destroyed` → `MatchState.mark_destroyed`)
- one authoritative building registry
- one-shot victory trigger lock
- initialization checks for enemy-building registration problems

## 8. Testing Strategy

### 8.1 Initialization (boot) checks

Verify on scene load:
- hero node exists and is bound
- HUD appears
- deputy command UI appears
- enemy buildings are registered
- victory monitor is active

Headless boot:
```bash
godot4 --headless --path godot --quit
```
must exit with no missing-script or missing-node errors.

### 8.2 Interaction Tests

Verify during play:
- mouse-driven hero movement works
- targeting and attack against buildings works
- text command submission works for both channels
- command log updates correctly
- voice placeholder button shows correct placeholder state
- HUD clicks do not issue world orders

### 8.3 Match Closure Tests

Verify the minimum loop:
- enemy buildings update HP/state when damaged / destroyed
- destroying the final building triggers victory
- victory overlay appears
- post-victory input enters a controlled locked state

### 8.4 Recommended Test Order

1. initialization
2. hero control
3. command input
4. building destruction and victory

## 9. Logging and Debug Visibility

Minimum debug events recommended for MVP (printed via `print()` or `push_warning()`):
- hero input event
- command submitted
- command status updated
- enemy building destroyed
- victory triggered
- scene binding success / failure

## 10. Acceptance Criteria

The MVP is accepted when the following full flow works in `main.tscn`:

1. the scene loads correctly in Godot 4.6.x
2. the player sees the hero and minimal HUD
3. the player can control the hero with mouse-first interaction
4. the player can send a text command to either deputy channel
5. the system shows that command as received / pending execution
6. the hero can damage and destroy enemy buildings
7. all enemy buildings can be removed from play
8. victory triggers when the enemy building count reaches zero

## 11. Follow-On Work After MVP

1. replace direct raycast movement with `NavigationAgent3D`
2. connect Command Console to real AI-agent input processing
3. add execution stubs for combat deputy behavior
4. add execution stubs for economy deputy behavior
5. only then evaluate whether real networking is worth adding

**Priority rule:** integrate AI-facing command behavior before introducing networking complexity.
