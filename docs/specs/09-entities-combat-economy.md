# Entities, Combat, and Economy Rules

Date: 2026-04-28
Project: War Buddy (Godot 4.6.x)
Status: Draft. Spec-only. **MVP does not implement this document.** 09 is the future contract that 06's gameplay vision instantiates as concrete entities, combat math, economy loop, tech tree, and match shape. Implementation lands as separate tasks after 07/08 stabilize.

Parents: 06.
Siblings: 07 (`OrderTypeRegistry` extension point that 09 fills), 08 (`BattlefieldSnapshotBuilder` reads 09's `GameState`; captain stat reinforcement seam).
Children: 10 (war-room authors pre-plans against 09's unit/building lists), 11 (collision-layer for 09 unit kinds), 12 (combat replay format).

## 1. Purpose and Relationship to 06

06 §2.3 mandates an `agency_tier` field on every unit definition. 06 §6 fixes a ~50-unit force composition. 06 §5 leaves match length, win condition, and faction count deliberately open. 09 closes those, plus everything else needed to make a game session run end-to-end:

- **Unit taxonomy** — what entities exist on the battlefield, their roles, agency tiers, combat properties
- **Combat math** — damage types, armor classes, the multiplier matrix, HP / DPS / range starting values
- **Economy** — resources, gather loop, worker behavior, base saturation
- **Tech tree** — three-tier progression and what each tier unlocks
- **Buildings** — production, supply, tech, defense
- **Match shape** — length target, win condition, pop cap mechanic
- **Captain ↔ squad binding** — how 08's captain personas attach to squad types
- **OrderTypeRegistry extensions** — the `gather` / `train` / `build` / `research` order types 07 §6 expects 09 to register

09 is **structure-first, numbers-second**. The matrices and tables here ship with explicit starting values (mostly cribbed from Starcraft 2 to inherit 15 years of free balance work), but every number is a starting point subject to playtest. 09 fixes the *fields*; the *values* live in `.tres` files designers can iterate without touching this doc.

## 2. Faction Model

### 2.1 v1: mirror

v1 ships with a single shared roster — both factions in a match draw from the same unit and building lists. Differentiation is cosmetic (color, captain persona variant) plus map-driven asymmetry (starting position, resource layout).

This is the smallest path that exercises the full system: 7 unit kinds × 2 factions = 14 unit instances, but only 7 unit *definitions* to author and balance.

### 2.2 Future: three-faction asymmetric

Locked-in long-term direction (recorded here so v1 architecture leaves room):

| Faction | Theme | Tone | First-pass keywords |
|---|---|---|---|
| **猫狗 (Cats & Dogs)** | Domestic-pet alliance | Spirited, scrappy, loyal | Mixed unit roles, balanced everyman |
| **鹅鸭 (Geese & Ducks)** | Waterfowl militia | Surprisingly aggressive, formation-heavy | Group buffs, strong frontline charges |
| **野生动物 (Wild Animals)** | Untamed third force | Anarchic, opportunistic, neutral-leaning | Asymmetric utility, cross-cutting tactics |

09+1 (a future revision) lands the three asymmetric rosters. The data layer described in §3–§7 must accommodate per-faction overrides without changing the schema — `unit_def.faction_id` and `build_def.faction_id` are mandatory fields from v1 even though v1 only ships `&"shared"`.

### 2.3 Captain persona theme alignment

The three captain persona archetypes from 08 §9 (`captain_combat`, `captain_econ`, `captain_scout`) get faction-specific voice variants in 09+1: a 猫狗派 `captain_combat` differs in tone and quirks from a 鹅鸭派 `captain_combat`. v1 ships shared variants only.

## 3. Unit Taxonomy

### 3.1 Unit categories

Seven categories. Every unit definition must belong to exactly one.

| # | Category | Role | Agency tier | Typical force share |
|---|---|---|---|---|
| 1 | `worker` | Mining, gas, building | regular | 8–16 |
| 2 | `frontline` | Melee tank, choke-blocker | regular | 8–15 |
| 3 | `ranged` | Kiting, focused damage | regular | 6–12 |
| 4 | `siege` | Anti-structure, splash | regular | 2–4 |
| 5 | `caster` | Heal, buff, debuff, control | regular | 1–3 |
| 6 | `scout` | Vision, harass | regular | 2–4 |
| 7 | `hero` | Player avatar | hero | 1 |

A captain leading a squad takes the same category as the squad's regulars (with `agency_tier = captain`), per §8.

### 3.2 `UnitDef` Resource

```gdscript
class_name UnitDef
extends Resource

# Identity
@export var unit_id: StringName                 # canonical, e.g. &"frontline_basic"
@export var display_name: String                # localized
@export var faction_id: StringName = &"shared"  # v1: always "shared"; 09+1 extends
@export var category: StringName                # one of §3.1 categories
@export var agency_tier: StringName             # &"hero" | &"captain" | &"regular"

# Combat
@export var max_hp: int
@export var armor: int = 0                      # flat reduction subtracted before multiplier
@export var armor_class: StringName             # see §4.2: light | medium | heavy | structure | hero
@export var dmg: int                            # base attack damage
@export var dmg_type: StringName                # see §4.1: normal | piercing | siege | magic
@export var attack_range: float                 # meters; 0 = melee
@export var attack_period_seconds: float        # time between attacks
@export var splash_radius: float = 0.0          # 0 = single-target

# Movement
@export var move_speed: float                   # m/s on level ground
@export var turn_speed_deg: float = 720.0       # degrees per second; high = snappy

# Vision & detection
@export var sight_range: float                  # meters in fog-of-war reveal
@export var detection: bool = false             # detector for stealthed units (caster archetype usually)

# Production
@export var produced_at: StringName             # build_id of the building that produces this unit
@export var supply_cost: int                    # contributes to pop cap (§7.4)
@export var mineral_cost: int
@export var gas_cost: int
@export var build_time_seconds: float
@export var tech_tier: int                      # 1 / 2 / 3 — see §6
@export var prerequisites: Array[StringName] = []  # other build_ids required

# Behavior hooks (consumed by 09 behavior trees, not 07 schema)
@export var auto_engage_range: float = 0.0      # 0 = match attack_range
@export var auto_pursuit_range: float = 0.0     # how far to chase
@export var idle_behavior: StringName = &"hold" # &"hold" | &"patrol" | &"return_to_squad"
```

### 3.3 v1 unit roster (one per category)

Numbers cribbed from Starcraft 2 same-role units. Marked **"playtest target"** — not final.

| `unit_id` | Category | Inspiration | HP | Armor / Class | DMG / Type | Range | Speed | Cost (M/G) | Build (s) | Tier |
|---|---|---|---|---|---|---|---|---|---|---|
| `worker_basic` | worker | SC2 SCV | 45 | 0 / light | 5 / normal | 0 (melee) | 2.81 | 50 / 0 | 12 | 1 |
| `frontline_basic` | frontline | SC2 Marauder | 125 | 1 / heavy | 10 / normal | 6 | 3.15 | 100 / 25 | 21 | 1 |
| `ranged_basic` | ranged | SC2 Marine | 45 | 0 / light | 6 / piercing | 5 | 3.15 | 50 / 0 | 18 | 1 |
| `siege_basic` | siege | SC2 Siege Tank | 175 | 1 / heavy | 35 / siege | 7 (13 sieged) | 2.62 | 150 / 125 | 45 | 2 |
| `caster_basic` | caster | SC2 Ghost | 100 | 0 / light | 10 / magic | 6 | 3.94 | 150 / 125 | 39 | 3 |
| `scout_basic` | scout | SC2 Reaper | 60 | 0 / light | 4×2 / piercing | 5 | 5.25 | 50 / 50 | 32 | 1 |
| `hero_commander` | hero | bespoke (no SC2 1:1) | 600 | 2 / hero | 25 / normal | 0 (melee) | 4.20 | n/a | n/a | n/a |

The hero is not produced — it spawns at match start at the player's main base. There is exactly one per faction. If killed, see §10.

### 3.4 Splash / area-of-effect

Splash damage uses `splash_radius` against all enemies inside the radius from the impact point. Splash applies the dmg-type-vs-armor multiplier per target individually. Friendly fire flag is **on** for `siege` units against `friendly_unit` and `friendly_structure`, **off** for everything else (rationale: siege misuse should hurt; ranged shouldn't accidentally kill workers).

## 4. Combat Math

### 4.1 Damage types (4)

| `dmg_type` | Reads as | Counters | Counter rationale |
|---|---|---|---|
| `normal` | Generic melee / kinetic | heavy | Crushing armor at close quarters |
| `piercing` | Bullets / arrows | light | Penetration shines vs unarmored |
| `siege` | Cannons / heavy ordnance | structure | Designed to bring down walls |
| `magic` | Spells / energy | light | Bypasses physical defenses |

### 4.2 Armor classes (5)

| `armor_class` | Examples | Notes |
|---|---|---|
| `light` | worker, ranged, caster, scout | Cheap, fragile |
| `medium` | (no v1 unit; reserved for 09+1 expansion) | Swing tier |
| `heavy` | frontline, siege | Tanky, slow |
| `structure` | all buildings | Static, high HP |
| `hero` | hero only | Special class to avoid hero-stomping by counters |

`medium` is reserved on purpose so 09+1 has room to expand the roster without re-balancing the whole matrix.

### 4.3 Multiplier matrix

| ↓ dmg \ armor → | light | medium | heavy | structure | hero |
|---|---|---|---|---|---|
| `normal` | 1.0× | 1.0× | 1.25× | 0.75× | 1.0× |
| `piercing` | 1.25× | 1.0× | 0.5× | 0.5× | 1.0× |
| `siege` | 0.5× | 0.75× | 1.0× | 1.25× | 0.5× |
| `magic` | 1.25× | 1.0× | 1.0× | 0.5× | 0.75× |

Stored as a Resource:

```gdscript
class_name DamageMatrix
extends Resource

@export var multipliers: Dictionary = {}  # {dmg_type: {armor_class: float}}

func multiplier(dmg_type: StringName, armor_class: StringName) -> float:
    return multipliers.get(dmg_type, {}).get(armor_class, 1.0)
```

A single `damage_matrix.tres` ships in `res://data/combat/`.

### 4.4 Damage formula

```
final_damage = max(0, (base_dmg * matrix(dmg_type, armor_class)) - armor)
```

- Multiplier applies before flat armor subtraction (so flat armor doesn't trivialize counters).
- `final_damage` floored at 0 (never heals).
- Critical hits, dodge, deflect, bonus-vs-tag — **out of scope for v1**. Reserved for 09+1.

### 4.5 No hero multiplier

Per brainstorm decision: heroes use the matrix table like every other unit (the `hero` armor class). There is **no** separate "hero takes 0.5× from everything" multiplier. Main-character feel comes from raw HP and DPS values (600 HP / 25 DPS in §3.3), not from a special-case rule.

Rationale: one matrix for the player to learn instead of two; LLM deputies don't need a separate inference pathway for hero damage.

### 4.6 Range, line-of-sight, and elevation

- Attack range is checked at center-to-center distance.
- Line-of-sight: required by `ranged`, `siege`, `caster`. Blocked by `structure` and impassable terrain. Not blocked by friendly units (no friendly-fire blocking).
- Elevation advantage: SC2-style — units on a high-ground tile attacking units on low-ground deal full damage; reverse direction has 50% miss chance unless attacker has vision of the high ground (provided by `scout`).

## 5. Economy

### 5.1 Resources

Two resource types. Both stored on the faction.

| Resource | Source | Worker round-trip |
|---|---|---|
| `mineral` | `mineral_patch` (8 patches per main base) | ~3 s |
| `gas` | `gas_geyser` (2 per main base, requires `refinery` building) | ~3 s |

### 5.2 `ResourceNode` Resource

```gdscript
class_name ResourceNode
extends Resource

@export var node_id: StringName
@export var resource_type: StringName       # &"mineral" | &"gas"
@export var initial_amount: int             # patches deplete; geysers don't
@export var current_amount: int
@export var harvest_amount_per_cycle: int   # default 5 mineral / 4 gas
@export var max_concurrent_workers: int     # default 3 per patch
@export var depletes: bool                  # mineral=true, gas=false
```

When a mineral patch reaches 0, it disappears and the surrounding workers re-queue automatically.

### 5.3 Worker behavior (the gather loop)

A `worker_basic` unit cycles through:

```
[idle / has command]
       │
       ▼
[move to assigned ResourceNode]
       │
       ▼
[harvest: 1.5 s animation, picks up harvest_amount_per_cycle]
       │
       ▼
[move to nearest deposit point (HQ or supply depot with deposit flag)]
       │
       ▼
[deposit: 0.2 s, adds to faction resource pool]
       │
       └─→ loop unless re-ordered
```

Saturation: a single main base with 8 mineral patches saturates around 16 workers (2 per patch). 24 workers per base is "over-saturated" with diminishing returns. The deputy's `captain_econ` should treat this as a soft target.

### 5.4 Building construction

Workers also build. Construction:

- Worker walks to placement location
- Worker enters "constructing" state, occupying its own collision body
- Building HP increases linearly over `build_time_seconds`
- Building becomes operational at 100% HP
- Worker is freed; the build cost (mineral + gas) was deducted at placement, not at completion
- If construction is cancelled, **75%** of cost is refunded (not 100%)

Multiple workers can stack on one construction site for **40% speed each additional worker** (so 2 workers = 1.4× speed, 3 = 1.8× speed). Cap at 5 workers.

## 6. Tech Tree (Three Tiers)

SC2-style three-tier progression.

### 6.1 Tier definitions

| Tier | Gating mechanism | Unlocks |
|---|---|---|
| **T1** | Default at match start | `worker_basic`, `frontline_basic`, `ranged_basic`, `scout_basic`, basic buildings |
| **T2** | Build a **Tier 2 Tech Building** (e.g. `forge`); upgrade HQ in parallel | `siege_basic`, defensive structures (turrets), Tier 2 production buildings |
| **T3** | Build a **Tier 3 Tech Building** (e.g. `arcanum`) and upgrade HQ to Tier 3 | `caster_basic`, ultimate buildings, expensive tech upgrades |

The hero (`hero_commander`) is always available — it does not gate by tier. It spawns at match start.

### 6.2 Tech-gating in `UnitDef`

The `UnitDef.tech_tier` field declares the tier required. The `prerequisites` array can additionally name specific buildings that must exist (e.g. `[&"barracks", &"engineering_bay"]`).

### 6.3 Snapshot impact

`BattlefieldSnapshotBuilder` (08 §7) gains a `tech_state` field:

```jsonc
"tech_state": {
  "current_tier": 2,
  "buildings_completed": ["hq", "barracks", "forge"],
  "research_complete": [],
  "next_unlock_eta_seconds": 45  // siege_basic enables when forge finishes
}
```

This lets the deputy LLM make informed "do we tech up or push now?" decisions — vision §2.2 specialization for the deputy.

## 7. Buildings

### 7.1 `BuildingDef` Resource

```gdscript
class_name BuildingDef
extends Resource

@export var build_id: StringName
@export var display_name: String
@export var faction_id: StringName = &"shared"
@export var category: StringName                # see §7.2
@export var max_hp: int
@export var armor: int = 1
@export var armor_class: StringName = &"structure"

# Construction
@export var mineral_cost: int
@export var gas_cost: int
@export var build_time_seconds: float
@export var tech_tier: int
@export var prerequisites: Array[StringName] = []
@export var size_grid: Vector2i                 # footprint in grid cells

# Production / function
@export var produces: Array[StringName] = []    # unit_ids this building produces
@export var supply_provided: int = 0            # for supply depots and HQs
@export var deposit_point: bool = false         # workers can deposit here
@export var research_options: Array[StringName] = []  # research_ids unlockable
@export var defensive: bool = false             # auto-attacks enemies in range
@export var defensive_range: float = 0.0
@export var defensive_dmg: int = 0
@export var defensive_dmg_type: StringName = &"normal"
```

### 7.2 Building categories

| Category | Examples | Tier |
|---|---|---|
| `hq` | Main base / town hall / nest | T1 (upgradable to T2/T3) |
| `supply` | Supply depot — provides pop cap | T1 |
| `production` | Barracks (frontline), range (ranged), factory (siege) | T1/T2 |
| `tech` | Forge (T2 unlock), arcanum (T3 unlock), engineering bay | T1/T2/T3 |
| `resource` | Refinery (over gas geyser) | T1 |
| `defense` | Turret, missile tower | T2 |

### 7.3 v1 building roster (minimum playable)

| `build_id` | Category | HP | Cost (M/G) | Build (s) | Provides |
|---|---|---|---|---|---|
| `hq` | hq | 1500 | 400/0 | 100 | +10 supply, deposit_point, produces `worker_basic` |
| `supply_depot` | supply | 400 | 100/0 | 21 | +8 supply |
| `barracks` | production | 1000 | 150/0 | 46 | produces `frontline_basic`, `ranged_basic`, `scout_basic` |
| `forge` | tech | 850 | 150/100 | 35 | T2 unlock, research_options for armor/weapon upgrades |
| `factory` | production | 1250 | 200/100 | 43 | T2-gated, produces `siege_basic` |
| `arcanum` | tech | 850 | 150/200 | 50 | T3 unlock |
| `temple` | production | 1000 | 150/150 | 50 | T3-gated, produces `caster_basic` |
| `refinery` | resource | 500 | 75/0 | 21 | enables gas extraction at a geyser |
| `turret` | defense | 250 | 100/0 | 30 | T2-gated, auto-attacks in 7-range, 12 dmg piercing |

Total: 9 building defs. This is the smallest set that exercises construction, supply, production-by-tier, tech-gating, gas, and defense.

### 7.4 Pop cap (supply system)

Soft cap mechanic, not hard. Each faction tracks:

```
supply_used = sum(unit.supply_cost) for all alive units
supply_max = sum(building.supply_provided) for all completed buildings
```

When `supply_used >= supply_max`:
- Production is blocked (production buildings refuse to start units that would exceed cap).
- Existing units continue functioning.
- The HUD surfaces a "supply blocked" warning.

Default supply costs:
- `worker_basic`: 1
- `frontline_basic`: 2
- `ranged_basic`: 1
- `siege_basic`: 3
- `caster_basic`: 2
- `scout_basic`: 1
- `hero_commander`: 0 (free, fixed)

Practical max under default: 1 hq (10) + 5 supply_depot (40) = 50 supply. Matches 06 §6's "~50 units per faction" target.

## 8. Captain ↔ Squad Binding

### 8.1 Squad type derives from category

A squad's category is determined by the regulars it contains. Mixed-category squads are not allowed in v1. Squads are formed implicitly: when a captain spawns and is assigned `n` regulars, those regulars all share the captain's category.

### 8.2 Captain persona category mapping

08 §9 ships three captain persona archetypes. 09 binds them to categories:

| Captain persona | Eligible squad categories |
|---|---|
| `captain_combat.tres` | `frontline`, `ranged`, `siege`, `caster` |
| `captain_econ.tres` | `worker` |
| `captain_scout.tres` | `scout` |

A captain with `captain_combat` cannot lead a worker squad and vice versa. Mismatch is enforced at spawn time by 09's `Squad` factory.

### 8.3 Captain stat reinforcement (the ≤15% rule)

Per 06 §2.3 and 08 §11.6, a captain has a `CaptainMemory.preferred_axis` and `reinforcement_pct` (clamped at 0.15). When 09 spawns a captain unit (which is a unit of the squad's category, not a separate captain unit kind), it reads the memory snapshot and applies the bonus to one axis:

| `preferred_axis` value | Effect on captain unit |
|---|---|
| `&"hp"` | `max_hp *= (1 + reinforcement_pct)` |
| `&"dps"` | `dmg *= (1 + reinforcement_pct)` and `attack_period_seconds /= (1 + reinforcement_pct)` |
| `&"sight"` | `sight_range *= (1 + reinforcement_pct)` |
| `&"speed"` | `move_speed *= (1 + reinforcement_pct)` |

Only one axis at a time; the cap stays in 08's writer (08 §11.6) so 09 trusts the input.

The captain unit is otherwise a regular of the same category with `agency_tier = captain` overridden, which gates the soul-on-death VFX in 11 §3.

## 9. OrderTypeRegistry Extensions

Per 07 §6, 09 registers additional order types at autoload boot. The v1 extension:

| `type_id` | Params | Allowed deputies | Notes |
|---|---|---|---|
| `gather` | `{node_id: StringName}` | combat, economy | Worker-only target check enforced at validation |
| `return_cargo` | `{}` | combat, economy | Forces a worker to deposit immediately |
| `build` | `{build_id: StringName, position: Vector3}` | combat, economy | Worker-only |
| `train` | `{unit_id: StringName, count: int = 1}` | combat, economy | Issued to a production building |
| `research` | `{research_id: StringName}` | combat, economy | Issued to a tech building |
| `set_rally` | `{position: Vector3}` | combat, economy | Production building rally point |
| `cancel_production` | `{queue_index: int}` | combat, economy | Cancel a queued unit |

Combined with 07's v1 core (`move`, `attack`, `stop`, `hold`, `use_skill`), the registry holds 12 order types after 09's registration. Future verbs (retreat, regroup, harass, ambush, scout, watch from the brainstorm verb list) are deferred — they all decompose into the existing 12 (e.g. `retreat = move` toward home + `posture = hold_fire`; `harass = attack` with low force commitment).

## 10. Match Shape

### 10.1 Length target

**~15 minutes per match** as the design target. This shapes resource availability, tech timing, and supply pacing.

T2 should be reachable around the 5-minute mark with reasonable play; T3 around 10 minutes. By 15 minutes both factions are at full tech with mature armies, and the win-or-lose decision should be imminent.

### 10.2 Win condition

**Destroy all enemy buildings.** Same as MVP (`MatchState.victory_triggered`). No alternative win conditions in v1.

This preserves the existing MVP architecture as-is — `MatchState.mark_destroyed` and victory trigger continue to work. 09 simply expands the building roster the system tracks.

### 10.3 Hero death

The hero can die. On death:
- Ragdoll corpse + soul VFX per 11 §3.
- A respawn timer starts (default **30 seconds**).
- Hero respawns at the main base.
- If main base is destroyed and no other `hq` exists, hero does not respawn — but at that point the faction is also approaching defeat by win condition.
- Hero death is **not a loss condition** by itself.

### 10.4 Pop cap

Soft cap via supply system (§7.4). Design target ~50 units per faction. Hardcoded ceiling to prevent runaway: `supply_max` clamped at 100 regardless of supply buildings (in case supply-depot spam becomes an issue).

### 10.5 Resource pacing

Match start: each faction begins with **50 mineral, 0 gas, 1 hq, 6 worker_basic, 1 hero_commander**. This matches SC2 starting conditions for a 1v1.

Total mineral on map per faction: 8 patches × 1500 mineral = 12000 mineral. Roughly 25 minutes of full-saturation mining before the main base depletes — matches the ~15 minute target with margin.

## 11. GameState Autoload

08 §7 mentions a future `GameState` autoload that `BattlefieldSnapshotBuilder` queries. 09 owns its definition.

```gdscript
class_name GameState
extends Node     # autoload

# Faction state (per-faction lookup)
func get_faction(faction_id: StringName) -> FactionState
func all_factions() -> Array[FactionState]

# Entity queries (cheap, group-based)
func units_in_radius(center: Vector3, radius: float, faction_id: StringName = &"") -> Array
func buildings_in_radius(center: Vector3, radius: float, faction_id: StringName = &"") -> Array
func resource_nodes(resource_type: StringName) -> Array

# Tech / production
func current_tier(faction_id: StringName) -> int
func is_unit_buildable(faction_id: StringName, unit_id: StringName) -> Dictionary
    # returns { ok: bool, missing_prereqs: [...], missing_supply: int, missing_resources: {} }

# Match
func match_elapsed_seconds() -> float
func is_victory_triggered() -> bool
```

```gdscript
class_name FactionState
extends Resource

@export var faction_id: StringName
@export var minerals: int
@export var gas: int
@export var supply_used: int
@export var supply_max: int
@export var current_tier: int
@export var alive_units: Array[int]              # node ids
@export var alive_buildings: Array[int]
@export var research_complete: Array[StringName]
@export var production_queues: Dictionary        # building_id -> Array[unit_id]
```

`GameState` is the single authoritative read source for the LLM snapshot. `BattlefieldSnapshotBuilder` queries it; nothing else owns this data.

## 12. Behavior Trees

09 owns the per-unit / per-squad behavior tree implementations that consume orders from `CommandBus.order_issued`. 07 §11 already names this seam.

Behavior tree authoring is **deferred to its own task** — 09 fixes only the contract, not the tree implementations:

- One BT class per unit category (`worker_bt.gd`, `frontline_bt.gd`, etc.) plus a `squad_bt.gd` for captain-led groups.
- BTs subscribe to `CommandBus.order_issued` filtered by `target_unit_ids` containing self.
- BTs report back via `EventBus`-style signals: `order_completed`, `order_failed`, `order_progress`.
- BT internals (selectors, sequences, decorators) are an implementation choice — Godot 4.6 doesn't ship a BT framework, so we either roll a small one or import a community plugin. Decision deferred to the implementation task.

## 13. Faction Roster Roadmap (Future)

Recorded as a long-term anchor; v1 ignores.

```
v1: shared mirror roster (this doc, §3.3 + §7.3)
   ↓
09+1: split into 3 factions
   ├─ 猫狗 (Cats & Dogs)
   ├─ 鹅鸭 (Geese & Ducks)
   └─ 野生动物 (Wild Animals)
```

Each faction at 09+1 will:
- Reuse the seven categories from §3.1 (kept stable across factions for LLM cognitive load)
- Override numeric values per `unit_def.faction_id` lookup
- Introduce 1–2 faction-unique units that lean into the faction theme without breaking the matrix
- Get faction-specific `captain_*` persona variants with tone, idioms, and quirks

## 14. Open Questions

- **Verbs the deputy can use beyond the core set** — verbs like `retreat`, `harass`, `ambush` from 07's brainstorm verb list are *not* `OrderTypeRegistry` entries in v1; 09 §9 absorbs them by decomposition. If playtest finds them awkward to express via composition, they get promoted to first-class types. → 09+1 review
- **Hero abilities** — the hero has 600 HP and 25 DPS but no special skills in v1. Skills (cooldown abilities, ult) belong to 09+1. → 09+1
- **Faction asymmetry concrete numbers** — per-faction overrides for §3.3 / §7.3. → 09+1
- **Behavior tree framework choice** — roll-our-own vs community plugin. → implementation task
- **Map authoring tooling** — how grids, landmarks, resource nodes get placed in the editor. → 10 (war-room) and a future map-editor sub-doc
- **Anti-griefing for captain reinforcement** — what stops a player from farming a captain's preferred-axis stat in trivial matches to break PvP balance? → 09+1 if PvP becomes priority

## 15. Verification (skeleton)

A 09 implementation is "skeleton-complete" when:
1. `UnitDef` and `BuildingDef` Resources parse and round-trip via `to_dict` / `from_dict`.
2. `damage_matrix.tres` loads and `multiplier()` returns expected values for all 4×5 combinations.
3. `GameState` autoload boots, exposes the API in §11, returns sane values for an empty match.
4. The 7 v1 unit `.tres` files (one per category) load without error.
5. The 9 v1 building `.tres` files load without error.
6. Headless boot: `gather` order issued via `CommandBus.submit_orders` reaches `worker_basic`'s behavior tree (when implemented).
7. A trivial integration test: starting state (50 minerals, 6 workers) issues a build order for `supply_depot`; after 21 seconds elapsed, faction's `supply_max` is 18.
8. Captain spawn applies `reinforcement_pct` to the correct axis from `MemoryStore.snapshot_captain_for(...)`.

09 is **not** required to ship behavior trees, victory animations, music, or art — those are downstream tasks. 09 ships the data layer and contracts.
