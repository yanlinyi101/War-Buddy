# RTS MVP Design for 团结中国 hub1.8.4 scene

Date: 2026-04-01
Project: `war-of-agents`
Status: Approved for spec writing, pending final written-spec review

## 1. Goal

Validate a minimum playable RTS/PVP commander prototype inside the 团结中国 hub1.8.4 scene.

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
1. enter the hub1.8.4 verification scene
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
- enemy buildings are pre-placed in the scene and can be destroyed
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

Voice is not implemented yet, but the UI must clearly indicate where it belongs in the future experience.

## 4. System Design

The implementation should be split into five focused modules.

### 4.1 Hero Control Module

Responsibilities:
- receive default mouse input
- support hybrid-control extensibility
- move the hero
- select targets
- perform basic attack / interaction actions
- expose current hero state to the UI and match systems

Non-responsibilities:
- parsing deputy commands
- match victory rules
- AI execution logic

### 4.2 Command Console Module

Responsibilities:
- provide explicit channels for combat and economy deputies
- accept text command input
- log command metadata
- maintain command lifecycle states
- expose recent command history to the HUD
- expose a voice-entry placeholder state

Minimum command states:
- submitted
- received
- pending execution

Minimum command object fields:
- `id`
- `channel`
- `text`
- `createdAt`
- `status`

Non-responsibilities:
- natural-language understanding
- deputy execution
- multi-agent orchestration

### 4.3 Match State Module

Responsibilities:
- define factions
- register enemy buildings
- track building destruction
- determine when all enemy buildings are destroyed
- trigger victory
- lock match-end state when needed

Minimum building object fields:
- `id`
- `faction`
- `hp`
- `isDestroyed`

Minimum match-state fields:
- `enemyBuildingsRemaining`
- `isVictory`
- `isMatchLocked`

Non-responsibilities:
- networking
- enemy AI
- real economy simulation

### 4.4 Scene Adapter Module

Responsibilities:
- connect the MVP systems into the 团结中国 hub1.8.4 scene
- bind the hero instance
- bind enemy building targets
- bind HUD anchors and command UI anchors
- keep scene modifications localized and reversible

Non-responsibilities:
- redesigning the entire scene
- introducing unrelated scene refactors

### 4.5 MVP HUD / UI Layer

Responsibilities:
- show minimum hero status
- show deputy command channels
- provide text input UI
- provide voice-entry placeholder UI
- show command log and command state
- show victory prompt

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
- hero state has minimum visual or UI feedback

### 5.2 Command System

Must include:
- combat and economy channels are visible and distinct
- player can enter a text command
- player can submit a command to a selected channel
- command appears in command history
- command status is visible

### 5.3 Voice Placeholder

Must include:
- visible voice button / entry affordance
- clear non-deceptive placeholder message, such as:
  - “Voice command coming soon”
  - or “Current MVP supports text commands only”

### 5.4 Fake PVP Battlefield

Must include:
- enemy buildings exist in the scene
- enemy buildings can take damage
- enemy buildings can be destroyed
- match state updates when buildings are destroyed
- victory triggers when all enemy buildings are gone

### 5.5 Victory Feedback

Must include:
- clear victory message or panel
- post-victory state lock for core match actions

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

## 7. Error Handling and Edge Cases

### 7.1 Hero Control

Handle:
- clicking unreachable terrain
- clicking invalid targets
- control input after victory
- missing hero binding on scene load

Expected behavior:
- invalid or unreachable actions fail safely with light feedback
- post-victory control is locked or suppressed
- missing binding fails early and visibly during initialization

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
- command history is driven from one authoritative data source
- submissions remain ordered and visible

### 7.3 Voice Placeholder

Handle:
- player clicking voice input expecting functionality

Expected behavior:
- clear placeholder messaging
- no fake recording flow
- no misleading “active” interaction state

### 7.4 Victory Logic

Handle:
- last building destroyed but victory not triggered
- destroyed building still counted as alive
- enemy building missing faction registration
- multiple victory triggers firing

Expected behavior:
- one authoritative destruction update path
- one authoritative building registry
- one-shot victory trigger lock
- initialization checks for enemy-building registration problems

## 8. Testing Strategy

### 8.1 Initialization Tests

Verify on scene load:
- hero object exists and is bound
- HUD appears
- deputy command UI appears
- enemy buildings are registered
- victory monitor is active

### 8.2 Interaction Tests

Verify during play:
- mouse-driven hero movement works
- targeting and attack against buildings works
- text command submission works for both channels
- command log updates correctly
- voice placeholder button shows correct placeholder state

### 8.3 Match Closure Tests

Verify the minimum loop:
- enemy buildings update state when damaged / destroyed
- destroying the final building triggers victory
- victory UI appears
- post-victory input enters a controlled locked state

### 8.4 Recommended Test Order

Recommended validation order:
1. initialization
2. hero control
3. command input
4. building destruction and victory

This reduces debugging ambiguity and keeps the minimum loop testable.

## 9. Logging and Debug Visibility

Minimum debug events recommended for MVP:
- hero input event
- command submitted
- command status updated
- enemy building destroyed
- victory triggered
- scene binding success / failure

The goal is not full telemetry. The goal is enough observability to debug the future AI-integration path.

## 10. Acceptance Criteria

The MVP is accepted when the following full flow works in the hub1.8.4 scene:

1. the scene loads correctly
2. the player sees the hero and minimal HUD
3. the player can control the hero with mouse-first interaction
4. the player can send a text command to either deputy channel
5. the system shows that command as received / pending execution
6. the hero can damage and destroy enemy buildings
7. all enemy buildings can be removed from play
8. victory triggers when the enemy building count reaches zero

## 11. Follow-On Work After MVP

After this MVP, the most natural next steps are:
1. connect Command Console to real AI-agent input processing
2. add execution stubs for combat deputy behavior
3. add execution stubs for economy deputy behavior
4. only then evaluate whether real networking is worth adding

**Priority rule:** integrate AI-facing command behavior before introducing networking complexity.

That preserves the product’s unique value instead of turning the project into a generic multiplayer prototype.
