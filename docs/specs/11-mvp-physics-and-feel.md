# MVP Physics and Interaction Feel

Date: 2026-04-27
Project: War Buddy (Godot 4.6.x)
Status: Draft. Scoped to the current MVP graybox (`godot/scenes/main.tscn`). Independent of the post-MVP doc line (06–10, 12) but consistent with it.

## 1. Purpose

Lock down the **physical interaction layer** of the MVP so it can be tuned to a coherent feel target instead of drifting.

Two anchors:

- **MVP feel target = "B" (LoL / DOTA response-first)** — input is honored immediately, motion is direct, feedback is minimal but unambiguous.
- **Future feel target = "D" (modern action-RPG)** — leave numerical and architectural headroom so MVP values can be retuned upward toward a richer action-game feel without rewriting the systems.

Every spec line in this document is **quantitative target + subjective intent**. Numbers are starting points subject to playtest, not final values. The subjective intent is the contract — if a tuning pass keeps the number but loses the intent, the number should change.

## 2. Collision and Layer Matrix

### 2.1 Physics layers

Define the following Godot physics layers (numerical layer indices to be assigned in `project.godot`):

| Layer | Members | Purpose |
|---|---|---|
| `terrain` | static world geometry, NavObstacles | hard wall for everything |
| `hero` | the player hero | special priority entity |
| `friendly_unit` | future friendly captains, regulars | soft-collide with each other and with hero |
| `enemy_unit` | future enemy units | hard-collide with hero |
| `friendly_structure` | future friendly buildings + construction ghosts | hard wall, navigation obstacle |
| `enemy_structure` | enemy buildings (current MVP target) | hard wall, navigation obstacle |
| `corpse` | ragdoll bodies of dead units | soft-collide, pushable |
| `soul` | floating soul VFX for hero/captain deaths (deputy is off-field, not eligible) | no collision |
| `attack_hitbox_player` | melee/projectile volumes spawned by friendlies | passes through self side |
| `attack_hitbox_enemy` | enemy attack volumes | detects hero but does not block movement |
| `cursor_pick` | mouse-ray pickable targets | high-priority selection |

### 2.2 Hero collision matrix

| Other entity | Behavior | Notes |
|---|---|---|
| Enemy structure | **Hard collide + nav-blocking** | Already implemented in MVP. |
| Enemy unit (future) | **Hard collide** | Body-blocking is meaningful — chokepoints, tanking. |
| Friendly unit (future) | **Soft collide** | Mutual push, never deadlocks. |
| Friendly structure (future) | **Hard collide + nav-blocking** | Construction ghosts count from placement (see §2.4). |
| Terrain / nav-obstacle | **Hard collide + nav-blocking** | Includes cliffs, rivers, designer walls. |
| Self-side attack hitboxes | **Pass through** | Hero is not hit by own weapon. |
| Enemy attack hitboxes | **Detect, do not block** | Damage applied; movement unaffected. |
| Cursor pick ray | **Selectable, high priority** | Hero is always priority on pick if overlapping. |

### 2.3 Push priority among friendlies

When friendly units soft-collide with each other, the push resolution is:

> **Hero has invincible priority. Other friendlies always yield to hero.**

Subjective intent: reinforce the "main-character" feel. The hero never has to wait for the army; the army parts for them.

Implementation note: friendly-unit physics body has lower mass / higher push-receive multiplier when colliding with the hero entity, regardless of velocity state.

### 2.4 Construction ghosts

When a friendly building is placed (ghost / under-construction state), it becomes a `NavigationObstacle` **immediately** at the moment of placement, not at completion. The hero pathfinds around the ghost from the first frame.

Subjective intent: prevent the player from accidentally pathing through their own building site and getting boxed in by their own construction.

## 3. Death and Corpse Handling

All on-field units, when killed, leave a **ragdoll corpse** with a "Human Fall Flat" jelly-physics aesthetic. Corpses are on the `corpse` layer: soft-collide, pushable by any moving unit, no nav-blocking.

Additionally, on-field units of `agency_tier ∈ {hero, captain}` (see 06 §2.3 and 09's `agency_tier` field) spawn a **floating soul** VFX on the `soul` layer: no collision, drifts upward, fades over a few seconds.

The **deputy is not on the field** (06 §2.3) and is therefore not part of the corpse / soul pipeline at all. It has no collision body, no HP bar, and no death state. Its in-match presence is a HUD portrait + voice — see 06 §8 open question for the visual treatment, deferred to a later UX pass.

| agency_tier | On-field? | Ragdoll corpse | Floating soul |
|---|---|---|---|
| hero | yes | yes | yes |
| deputy | **no** | n/a | n/a |
| captain | yes | yes | yes |
| regular | yes | yes | no |

Subjective intent:

- The ragdoll layer gives the entire game a "physical comedy" undertone that contrasts with the seriousness of strategic command — emotionally legible, never sterile.
- Souls mark units the player has built or could build a bond with. A captain dying matters visually in a way a regular trooper does not.

## 4. Hero Movement Spec

All numbers below are **target values, subject to playtest**. Tunables are listed in §10.

### 4.1 Top speed (Q1)

- **Target:** hero crosses the map diagonal in **~45 seconds** at full speed, no obstacles.
- **Derivation:** `hero_max_speed = map_diagonal_meters / 45 s`. For the current MVP graybox, this resolves to roughly 2.0–2.5 m/s pending a measurement of `world.tscn` extents.
- **Subjective intent:** between DOTA (slow, deliberate) and old RTS (sluggish). The map should feel like a battlefield, not a corridor.

### 4.2 Acceleration (Q2)

- **Target:** 0 → top speed in **80–120 ms** (use 100 ms as starting point).
- **Derivation:** `accel ≈ max_speed / 0.1 s`.
- **Subjective intent:** input feels honored instantly, but a faint trace of mass remains. If the hero feels "weightless / hovercraft-like", acceleration is too high. If the hero feels "wading through mud", too low.

### 4.3 Turning (Q3)

- **Logic:** facing direction updates **immediately** when input changes. Movement direction follows input on the same frame.
- **Visual:** the mesh's visual rotation eases over **~100 ms** to the new logical facing.
- **Subjective intent:** the player never feels their input is being delayed by the turn animation. The animation is a courtesy, not a gate. This is the "B派 with a polish layer" choice.

### 4.4 Stopping (Q4)

- **Target:** instant deceleration on stop command or path-end (0 ms, single-frame snap to zero velocity).
- **Subjective intent:** when the player tells the hero to stop, the hero stops. No skating, no overshoot. Combined with §4.2's brief acceleration, the asymmetry (slow start, hard stop) gives a "responsive but grounded" signature that distinguishes from both DOTA (symmetric easing) and pure arcade (instant both ways).

### 4.5 Movement input model

Current MVP uses **left mouse button** as the primary command input (matching `hero_controller.gd`). The B-派 convention canonical to LoL/DOTA is right-click; migrating button assignment is a future option but not part of 11 (see §11).

- LMB on ground → move-to that point, pathfinding around obstacles.
- LMB on enemy → move-into-range and auto-attack.
- LMB on unreachable point → walk to **closest reachable** point on the same nav-mesh island (Q9 = c, see §6).

## 5. Camera

### 5.1 Default behavior (Q12)

- Camera follows the hero by default.
- Player can free-pan away at any time using §5.3 controls.
- Pressing **spacebar** (also: double-click hero portrait, when HUD exists) re-centers and re-locks on hero.
- A pan threshold beyond which "follow" is considered disengaged: 1.5× viewport diagonal worth of pan offset (tunable).

Subjective intent: hero-centric like LoL, but the player can scout freely whenever they want without fighting the camera.

### 5.2 Angle and projection (Q14)

- High-angle, near-orthographic top-down. Pitch ~70–80°, mild perspective.
- Subjective intent: classic RTS legibility. Despite the "commander on field" DNA, the camera POV stays strategic — the *unit* is on the field, not the *camera*.

### 5.3 Controls (Q13)

- **Edge-scroll** at the screen border (configurable speed, off-by-default toggle for users who hate it).
- **WASD / arrow keys** for keyboard pan.
- Mouse wheel for zoom (within a clamped range).
- LMB is the primary command button (see §4.5); not used for camera drag.
- RMB and MMB are unused in MVP. RMB is reserved for a future migration to B-派 convention or a context action; MMB is reserved for future map ping / quick-center.

## 6. Click and Target Feedback

### 6.1 Ground click (Q7 = a)

- **Visual:** cursor itself plays a brief ripple/pulse. **No on-ground "ping circle" or persistent flag.**
- **Action:** move command issued instantly on click.
- **Subjective intent:** the hero starting to move *is* the feedback. Minimalism reinforces the "the game trusts your intent" philosophy.

### 6.2 Hover over enemy (Q8 = b)

- A red ring appears beneath the hovered enemy unit / structure.
- Ring fade-in: ≤ 80 ms.
- Ring removed when hover leaves.
- Subjective intent: clear targeting affordance without the visual noise of full silhouette glow.

### 6.3 Unreachable click (Q9 = c)

- No error sound, no rejection visual.
- Hero pathfinds to the closest reachable point.
- Subjective intent: the game trusts the player's intent and does its best, rather than scolding them for misclicking. Pairs with §6.1's minimalism.

## 7. Combat Feedback

### 7.1 Hitstop (Q5 = b)

- On melee hit landing: **30–60 ms freeze** (use 45 ms as starting point) on both the attacker and victim's animation/movement.
- Projectiles: hitstop on the victim only.
- Subjective intent: weight without interruption. The player should feel the hit, not have their flow halted.

### 7.2 Screen shake (Q6 = b)

- Trigger only on **important events**:
  - Hero takes damage above a threshold (e.g. >10% max HP single hit)
  - Hero kill-confirms an enemy (last-hit feedback)
  - Friendly structure destroyed
  - Enemy structure destroyed (victory pump)
- Magnitude: subtle. Amplitude scales with severity. No shake on routine damage trades.
- Subjective intent: shake is rare and earns meaning. If shake is constant, it stops mediating attention and just becomes noise.

### 7.3 HP bar response

- HP bars (above unit, also on HUD for hero) animate with a two-layer model: instant red drop, delayed white "ghost" bar that catches up over ~400 ms.
- Subjective intent: the player can see *that* damage was taken instantly, and *how much* a moment later — the standard MOBA convention.

## 8. Navigation Edge Cases

### 8.1 Hero displaced off nav-mesh (Q10 = b)

- Each frame, check the hero's distance to the nearest nav-mesh vertex.
- If displacement > **1.5 m** for > **3 frames**, teleport hero to the nearest valid nav-mesh point.
- Subjective intent: hard floor against "stuck in geometry" bugs. A 3-frame buffer prevents false positives during legitimate ragdoll-push events.

### 8.2 Path target on isolated island (Q11 = b)

- If the requested target is unreachable (different nav island, fully enclosed):
- Hero pathfinds to the point on the hero's island that is **straight-line closest** to the target.
- No error feedback. Same philosophy as §6.3.

### 8.3 Path completely fails (Godot returns empty path even on local island)

- Hero remains stationary.
- Log a warning to console (developer-facing, not player-facing).
- This case should not occur in correctly authored maps; the log catches authoring bugs early.

## 9. Push Resolution Among Corpses

- Living units pushing through corpse layer: corpse takes velocity from push, dampens over ~1.5 s, settles.
- Corpses do not push each other (avoid simulation cascade).
- Corpses despawn on a fade after a tunable lifetime (default: 60 s, or earlier under entity budget pressure).

## 10. Tunables Table

Centralized so playtest tuning has a single touch surface. All values **starting points**, not final.

| Key | Default | Unit | Source |
|---|---|---|---|
| `hero.cross_map_time` | 45 | seconds | §4.1 |
| `hero.acceleration_time` | 0.10 | seconds | §4.2 |
| `hero.visual_turn_ease` | 0.10 | seconds | §4.3 |
| `hero.stop_time` | 0.0 | seconds | §4.4 |
| `camera.follow_break_threshold` | 1.5 | viewport diagonals | §5.1 |
| `camera.pitch` | 75 | degrees | §5.2 |
| `feedback.hover_ring_fade_in` | 0.08 | seconds | §6.2 |
| `combat.hitstop_duration` | 0.045 | seconds | §7.1 |
| `combat.shake_hp_threshold` | 0.10 | fraction of max HP | §7.2 |
| `hp_bar.ghost_delay` | 0.40 | seconds | §7.3 |
| `nav.off_mesh_displacement_max` | 1.5 | meters | §8.1 |
| `nav.off_mesh_grace_frames` | 3 | frames | §8.1 |
| `corpse.settle_time` | 1.5 | seconds | §9 |
| `corpse.default_lifetime` | 60 | seconds | §9 |

These should be exposed as `@export` constants on a single `feel_tunables.gd` resource (or autoload) once 11 is approved, so designers can tune without code edits.

## 11. Out of Scope

The following are deliberately not part of 11; they belong to later docs:

- Animation rigging / mesh assets (graybox stays graybox)
- Sound design beyond placeholder slots (`_sfx_hit`, `_sfx_unreachable`, etc.)
- Particle FX beyond named placeholder slots (`_vfx_soul`, `_vfx_corpse_settle`)
- Skill abilities, ability targeting, ability cooldowns (09's territory)
- Hero combat math beyond placeholder values needed to test feel (HP, damage numbers come from 09)
- Camera cinematics, intro/outro framing, victory cam (later UX doc)
- Mouse-button reassignment (LMB → RMB primary, full B-派 alignment) — possible future migration, requires a separate task

## 12. Verification

A spec-line is verified when:
1. The numerical target is implemented in code or `feel_tunables.gd`.
2. A short subjective playtest note is added to a verification log confirming the *intent* is met.
3. Both can be diffed independently — number tuning never silently changes the intent contract.

The verification log lives at `docs/specs/11-feel-verification-log.md` (created when implementation begins).
