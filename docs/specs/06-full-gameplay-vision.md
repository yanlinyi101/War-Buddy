# Full-Gameplay Vision and Core Loop

Date: 2026-04-26
Project: War Buddy (Godot 4.6.x)
Status: Draft. North-star vision document for post-MVP gameplay. Parents docs 07–12.

## 1. Purpose

Define the long-term gameplay vision War Buddy is steering toward, so that every subsequent design decision (command system, AI deputy architecture, entity rules, war-room UI, MVP feel tuning) traces back to a single set of product pillars.

This document is the **north star**, not the implementation contract. It is intentionally light on numbers, rosters, and concrete schemas — those live in 07–12. What is fixed here is *what kind of game this is* and *what differentiates it*.

01–05 describe the Godot MVP slice. 06 starts the post-MVP design line.

## 2. Product DNA

These five pillars are load-bearing. A change to any of them invalidates parts of 07–12 and must be re-brainstormed, not edited in isolation.

### 2.1 Commander-on-the-Field, Not Omniscient Operator

The player is a commander present in the battlefield, directly controlling one hero unit. The player is **not** a top-down omniscient operator framing 50 workers and queuing 12 production buildings.

Implication: the input vocabulary the player uses to influence the rest of their faction is *commands to subordinates*, not direct unit micro. Multi-select, drag-box, and production queues are explicitly out of scope as primary input.

### 2.2 Real LLM-Driven AI Deputies as the Primary Input Channel

The player commands the rest of their faction through two AI deputies — a combat officer and an economy officer — using **voice as the primary input** and **real LLM reasoning** as the execution backbone. Text input exists only as an MVP-stage validation channel and is not part of the shipped player-facing experience.

Implication: command latency, cost, and unpredictability of LLM inference are first-class system constraints. The architecture must absorb them, not pretend they don't exist.

### 2.3 AI Deputies are Characters, Not Tools

Players are meant to form an emotional bond with their AI deputies across matches. Deputies have persistent identity, personality, memory of past matches with this player, evolving competence, and reactions to success and failure.

Implication: doc 08 is half systems engineering, half character design. A deputy that forgets you between matches breaks the pillar; a deputy that has no failure modes also breaks the pillar.

### 2.4 Three-Tier Command System

Commands enter the system at one of three layers, each with a different execution path:

| Tier | Where authored | Path | Latency | Predictability |
|---|---|---|---|---|
| **Pre-plans** (战术预案) | War-room UI before match | Structured schema → behavior tree | Instant | Fully deterministic |
| **Tactical orders** (战术指令) | In-match voice/text | Intent classifier → behavior tree | Low | High |
| **Strategic intent** (战略意图) | In-match voice | LLM planner → decomposes into tactical orders → behavior tree | High | Bounded by LLM |

The three tiers share **one tactical-order schema** as their common substrate. Pre-plans serialize to it directly; the LLM planner emits it; the behavior tree consumes it. This shared schema is the most important artifact in doc 07.

### 2.5 Hybrid Deputy Modes: AI Primary, Human Archon Secondary

The default and headline mode is two AI deputies. As a supplementary mode, a human player may take over a deputy seat in a Starcraft-2-Archon-style configuration — sharing one faction's controls with the commander. Human-deputy mode is a feature, not a fallback for broken AI.

Implication: the command bus must accept input from both AI handlers and human controls without branching the rest of the game logic.

## 3. Core Gameplay Loop

A match is structured around a continuous loop, not discrete phases:

1. **Read the battlefield** (commander observes via direct camera + minimap + deputy reports)
2. **Form intent** (commander decides what should happen next)
3. **Issue command** at the appropriate tier (pre-plan invocation / tactical / strategic)
4. **Deputies execute** with varying autonomy by tier
5. **Commander acts directly** with the hero unit in parallel — fighting, scouting, contesting key points
6. **Receive feedback** from deputies (status, completion, problems, asks for clarification)
7. **Adjust**

The hero unit is what keeps the commander mechanically engaged while deputies handle the macro layer. Without the hero, the player would be a spectator; without the deputies, the player would be a conventional RTS micro-manager. Both halves are required.

## 4. Spatial Vocabulary

Maps are addressed at three levels (full schema in doc 07):

- **Grid** — canonical A1–H8 (or similar) overlay every map shares. Used by pre-plan schemas and any precise reference.
- **Designer landmarks** — named features the map author placed (e.g. "north mine", "B4 high ground"). Aliases over grid cells.
- **Player-defined regions** — opt-in advanced feature in the war room. Players name their own regions per map and the AI deputy learns this private vocabulary. Treated as unlockable depth, not core infrastructure.

## 5. Match Shape (deferred)

Match length, faction count, victory conditions, asymmetry, single-player vs. PvP vs. PvAI configurations — all intentionally **left open** in this document. They are constrained by the pillars above but not specified here. Doc 09 will land them once entity and economy rules are scoped.

What is fixed at the vision level: *whatever a match looks like, the commander always controls a hero, always has at least one deputy, and always issues commands through the three-tier system.*

## 6. In Scope / Out of Scope

### In scope for the full game (covered across 07–12, built incrementally)

- One commander + one hero + two deputy seats (AI or human)
- Voice as primary command channel
- Three-tier command system with shared tactical schema
- Persistent AI deputy identity across matches
- War-room pre-match planning UI with pre-plan editor
- Player-defined named regions (advanced)
- Economy and combat units sufficient to give deputies meaningful autonomous work

### Explicitly out of scope (DNA-violating, do not propose without re-opening 06)

- Player-side multi-select, drag-box selection, control groups
- Direct production queue management by the player
- Commander framing/micro-ing arbitrary units (only the hero is directly controlled)
- AI deputies without persistent identity ("forget the player every match")
- Replacing voice with hotkey-driven command shells in the shipped product
- Mocked/scripted deputies sold as AI in shipped builds (MVP-only allowance)

### Deferred (later docs may reopen)

- Networked PvP, matchmaking, ranking
- Modding / custom-deputy authoring
- Non-Earth-RTS settings, narrative campaign

## 7. Documentation Roadmap

This document parents the following. Numbering continues from 01–05.

| Doc | Title | Depends on | Notes |
|---|---|---|---|
| 06 | Full-Gameplay Vision and Core Loop | — | This doc. |
| 07 | Command System Specification | 06 | Three-tier data structures; **shared tactical-order schema is the keystone artifact**; spatial vocabulary schema; pre-plan resource format; command lifecycle. |
| 08 | AI Deputy Architecture | 06, 07 | Two halves: (a) layered execution — LLM planner / intent classifier / behavior tree, tool-calling contract, battlefield snapshot format; (b) deputy-as-character — personality framework, cross-match memory model, growth, bond system, failure reactions. |
| 09 | Entities, Combat, and Economy Rules | 06, 07 | Unit / building taxonomies, resource types, gather-and-produce loops, combat math (HP / DPS / armor / range), vision and fog. **Skeleton first (categories + field definitions), numbers iterated later.** |
| 10 | War-Room UI and Pre-plan System | 07 | Main-menu flow, pre-plan editor UX, player-region authoring tool, per-map storage format. |
| 11 | MVP Physics and Interaction Feel | — (parallel to 06) | Near-term, scoped to current Godot MVP graybox. Collision-layer table, hero movement feel, attack feedback, click feedback, navigation edge cases. Each spec line quantified with numbers + subjective intent. |
| 12 | Test and Replay Strategy | 07, 08, 09 | Cross-cutting: GUT unit tests for behavior trees, fixture-based intent-classifier tests, command-replay format, LLM behavior benchmarks. |

### Authoring order

1. **06** (this doc) — first, blocks 07/08/09/10
2. **11** — can be drafted in parallel with 06 since it's MVP-scoped; needs its own brainstorming pass before drafting
3. **07, 08** — parallel after 06 lands
4. **09, 10** — after 07 lands
5. **12** — last, integrates 07–09

## 8. Open Questions Tracked Elsewhere

The following are deliberately not answered in 06 and will be resolved in the named doc:

- **What is the tactical-order schema, concretely?** → 07
- **What does the LLM planner's tool-calling contract look like?** → 08
- **How do deputies remember the player across matches, and what do they remember?** → 08
- **What units, buildings, resources exist in v1?** → 09
- **What is a match's win condition and length?** → 09
- **How is the war-room pre-plan editor structured?** → 10
- **What does the hero feel like to drive?** → 11
- **How do we regression-test LLM-driven gameplay?** → 12

## 9. Change Control

The five pillars in section 2 are the contract this document offers to 07–12. Edits to section 2 require explicit re-brainstorming and notification to any in-flight downstream doc. Editorial improvements to other sections do not.
