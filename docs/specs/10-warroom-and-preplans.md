# War-Room UI and Pre-plan System

Date: 2026-04-28
Project: War Buddy (Godot 4.6.x)
Status: Draft. Spec-only. **MVP does not implement this document.** 10 covers everything the player touches *outside* a live match — the main-menu shell, the pre-plan editor, the player-region authoring tool, the deputy/captain camp, and the settings panel.

Parents: 06.
Siblings: 07 (consumes `PrePlan` / `PlayerRegionSet` Resources from this doc), 08 (this doc edits `DeputyPersona` / `DeputyMemory` / `CaptainMemory` written by 08), 09 (this doc reads unit/building lists for editor dropdowns).
Children: future 10+1 (timeline pre-plan editor, deeper camp visualization).

## 1. Purpose and Scope

10 is the player's "everything-not-the-match" surface. It is where:
- Pre-plans (07 §7) are authored and shared
- Player-defined regions (07 §3.3) are drawn over the grid
- Deputy persona is selected (08 §9) and the autonomy dial is adjusted (08 §11.8)
- Captains' accumulated memory is inspected
- The control policy (07 §8) is configured
- Quick-match and lobby flow live

Out of scope for 10:
- In-match HUD (separate UX doc; current MVP `hud_root.gd` covers MVP slice)
- Voice STT/TTS surface (deferred to a future sub-doc)
- Online matchmaking, account, monetization (deferred)
- Map editor for designer-authored landmarks (separate sub-doc)

10 is **structure-and-flow first**, not pixel-mockup-first. Every screen described below is a layout intent + the data it touches; concrete visual design lives in a Figma doc later.

## 2. Top-Level Information Architecture

The main menu is a **four-tab shell**:

```
┌──────────────────────────────────────────────────────┐
│  War Buddy                                           │
│  ┌──────┬───────┬─────┬─────────┐                   │
│  │ Match│ WarRm │Camp │ Settings│                   │
│  └──────┴───────┴─────┴─────────┘                   │
│                                                      │
│  [tab content]                                       │
│                                                      │
└──────────────────────────────────────────────────────┘
```

| Tab | Owner | Primary purpose |
|---|---|---|
| **Match** | 10 §3 | Quick-launch a game; pick map and faction; show the deputy you'll bring; show currently-active pre-plans |
| **War Room** | 10 §4 | Pre-plan editor; player-region authoring; share-code import/export |
| **Camp** | 10 §5 | Deputy persona selection; autonomy dial; captain roster + memory inspector; bond traits readout |
| **Settings** | 10 §6 | Control policy; input bindings; audio/video; language |

The four-tab split is load-bearing: it separates **short-term action** (Match) from **long-term assets** (War Room / Camp) from **system config** (Settings). New players can ignore everything but Match; veterans live in War Room and Camp between matches.

## 3. Match Tab

### 3.1 Layout intent

```
┌────────────────────────────────────────────────────┐
│ Match                                              │
│  ┌────────────────────┐  ┌───────────────────────┐│
│  │ Map preview        │  │ Faction & deputy      ││
│  │  [grid overlay]    │  │  Faction: shared (v1) ││
│  │  [resource layout] │  │  Deputy: veteran ▼    ││
│  │  thumbnails of     │  │  Autonomy: ●●●○○ 0.5  ││
│  │  authored regions  │  │  Lock: 3/5 matches    ││
│  └────────────────────┘  └───────────────────────┘│
│                                                    │
│  Active pre-plans for this map:                    │
│   ☑ B Plan — "alpha attacks B4 defensive"          │
│   ☑ Eco Boost — "build supply at +60s"             │
│   ☐ Cheese Rush — "scout rush before 2:00"         │
│                                                    │
│  [ Start Match ]                                   │
└────────────────────────────────────────────────────┘
```

### 3.2 Data shown

| Element | Data source |
|---|---|
| Map preview | `res://data/maps/<map_id>.tscn` thumbnail; grid + landmark overlays from doc 07 |
| Faction | v1: `&"shared"`; 09+1 will list 猫狗/鹅鸭/野生 |
| Deputy dropdown | List of `DeputyPersona` resources from 08; the *currently-bound* persona (per 10 §5.2) is pre-selected and locked unless §5.2 swap conditions met |
| Autonomy slider | Reads / writes `DeputyPersona.deputy_autonomy` ∈ [0, 1] (08 §9). Slider has 5 detents for visual clarity (0.1 / 0.3 / 0.5 / 0.7 / 0.9), continuous underneath |
| Lock counter | "N/5 matches" — the persona-swap cooldown counter (10 §5.2) |
| Active pre-plans | List of `PrePlan` resources whose `map_id` matches selected map; checkboxes toggle each plan's `enabled` field |
| Start Match | Bootstraps the match scene; commits the current selections to the in-match config |

### 3.3 Quick-match shortcut

A "Quick Match" button at the top of the tab skips this screen entirely: re-uses the last match's selections and immediately starts. Discoverable on second-and-later sessions; first-session player must visit the screen at least once so "what is a deputy" is exposed before they bypass it.

## 4. War-Room Tab

The most complex tab. Two columns: **plan list** on the left, **editor** on the right.

### 4.1 Plan list

```
┌─────────────────────┐
│ War-Room            │
│ Map: forest_lake ▼  │
│  ┌───────────────┐  │
│  │ B Plan        │  │
│  │ Eco Boost  ★  │  │
│  │ Cheese Rush   │  │
│  │ + new plan    │  │
│  │ ↓ import code │  │
│  └───────────────┘  │
└─────────────────────┘
```

Filters by selected map. Each row shows plan `display_name` and indicators:
- ★ — set as a default for this map (auto-loads on Match tab)
- ⚠ — validation failure (07 §8.5)
- 🔗 — has a share code generated

Buttons:
- **+ new plan** — creates a blank `PrePlan` scoped to the current map
- **↓ import code** — opens share-code paste modal

### 4.2 Form-based plan editor (v1)

Brainstorm decision Q2 = A: ship form editor first; defer timeline view to 10+1.

```
┌───────────────────────────────────────────────────┐
│ Editing: B Plan                          [save]   │
│                                                   │
│ display_name:    [ B Plan                       ] │
│ trigger_phrases: [ b plan, plan b, execute b    ] │
│                                                   │
│ Trigger:         [ on_match_start            ▼  ] │
│   conditions:                                     │
│     within_seconds_of_start: [_60_]               │
│     enemy_count_at_least:    [__3_]               │
│     cooldown_seconds:        [__0_]               │
│                                                   │
│ Orders:                                           │
│  ┌──────────────────────────────────────────┐    │
│  │ #1 verb=defend  target=B4  force=alpha×6 │    │
│  │     posture=stand_ground  duration=120s  │    │
│  │     priority=routine                     │    │
│  │     [edit] [duplicate] [delete] [↑] [↓] │    │
│  └──────────────────────────────────────────┘    │
│  [ + add order ]                                  │
│                                                   │
│ [ generate share code ]   [ delete plan ]         │
└───────────────────────────────────────────────────┘
```

### 4.3 Order edit modal

Adding or editing one order opens a modal with structured fields, all dropdown-or-typed:

| Field | Source | UI |
|---|---|---|
| `type_id` | `OrderTypeRegistry.list_for_deputy(plan.deputy)` | dropdown |
| `target_kind` | enum from 07 §3.3 | dropdown |
| `target_*` | depends on `target_kind` | grid picker / landmark dropdown / region dropdown / param dropdown |
| `force.captain_id` | list of captain personas (08 §11.6) | dropdown w/ "deputy chooses" option |
| `force.count_min` / `count_max` | int input | numeric |
| `force.unit_types` | unit categories from 09 | multi-select |
| `posture` | aggressive / stand_ground / hold_fire | radio |
| `priority` | routine / high / emergency | radio |
| `duration_seconds` | int (-1 = permanent) | numeric + "permanent" toggle |

Validation (07 §8.5) runs on save: invalid plans cannot be saved; the editor surfaces the failing fields with inline error messages.

### 4.4 Parametric placeholders (07 §8.4)

When `target_kind = param` is selected in the order modal, the value field becomes a dropdown with the four allowed placeholders:

```
< my_main_base >
< closest_enemy_base >
< hero_position >
< deputy_focus >
```

A short tooltip explains each. No free-form text — the four values are the entire vocabulary.

### 4.5 Player region tool

Accessed from the War-Room tab's secondary toggle (above the plan list): "**Edit Regions**" mode swaps the editor pane for a grid-cell painter.

```
┌───────────────────────────────────────────────────┐
│ Regions for: forest_lake                          │
│                                                   │
│   ┌───────────────────────────┐                   │
│   │   A1  A2  A3  ... A8      │                   │
│   │   B1  ▓▓  ▓▓  B4  ...     │  ▓ = selected     │
│   │   C1  ▓▓  ▓▓  C4  ...     │  cells (this      │
│   │   D1  D2  D3  ...         │  region)          │
│   │   ...                     │                   │
│   └───────────────────────────┘                   │
│                                                   │
│   Region name: [ alpha_corner          ]          │
│   Aliases:     [ corner, the corner    ]          │
│                                                   │
│   [save region]  [delete]  [+ new region]         │
└───────────────────────────────────────────────────┘
```

Per Q3 = B brainstorm decision: grid-cell click as the authoring primitive. Click toggles a cell's membership in the currently-edited region. No rectangle-drag, no brush — those are 10+1 quality-of-life additions if testing shows pure click is too slow.

Per Q3a = (i): no unlock gating. The tool is available from match 1.

Storage: `user://player_regions/<player_id>/<map_id>.tres` per 07 §3.3.

### 4.6 Share codes

Two interactions:

**Generate:** "generate share code" button on a saved plan produces an opaque alphanumeric string (07 §8.5). UI:

```
┌──────────────────────────────────┐
│ B Plan — share code              │
│                                  │
│   WB1·a8f2x9d3kp7m...            │
│                                  │
│   [ copy ]   [ regenerate ]      │
│                                  │
│   This code includes:            │
│    • the plan structure          │
│    • the regions it references   │
│   But NOT:                       │
│    • your deputy memory          │
│    • your faction unlocks        │
└──────────────────────────────────┘
```

**Import:** paste a share code into the import modal. The system validates the schema-version prefix, decodes, and shows a preview before commit:

```
┌──────────────────────────────────┐
│ Importing: "Cheese Rush"         │
│                                  │
│ Schema version: 1 ✓              │
│ Map: forest_lake ✓               │
│ Bundled regions:                 │
│   • alpha_corner — name conflict │
│     ◉ rename to alpha_corner_2   │
│     ○ overwrite mine             │
│     ○ skip (plan needs it!)      │
│ Captain refs:                    │
│   • captain:alpha — ok           │
│ Orders: 3                        │
│                                  │
│   [ import ]   [ cancel ]        │
└──────────────────────────────────┘
```

Conflict resolution per 07 §8.5: regions with name collisions get a rename suffix; if a captain reference is unknown locally, the plan still imports with a warning ("this plan references a captain you haven't played; deputy will fall back to choosing one").

The share-code encoder/decoder itself is deferred (07 §8.5) — 10's UI calls a single `ShareCodeService.encode(plan) -> String` / `decode(code) -> ImportPreview` API and trusts it.

### 4.7 Validation surface

A plan is invalid if any of the conditions in 07 §8.5 fail. The editor surfaces failures inline at the failing field plus a summary banner at the top:

```
⚠ This plan has 2 issues:
  • Order #2 references landmark "old_north_mine" which no longer exists on this map.
  • Order #3 force.captain_id "delta" is not a registered captain persona.
```

Saving is blocked until 0 issues. "Save as draft" override is **not** offered — drafts that wouldn't run are worse than no plan.

## 5. Camp Tab

The "long-term assets" view. Mostly read-only with two specific edit points (persona swap, autonomy dial).

### 5.1 Layout intent

```
┌────────────────────────────────────────────────────┐
│ Camp                                               │
│                                                    │
│ ┌─ Deputy ────────────────────────────────────┐   │
│ │ Veteran   [portrait]                         │   │
│ │  Trust:        ████░ 0.8                    │   │
│ │  Frustration:  █░░░░ 0.1                    │   │
│ │  Bond:         █████ 1.0                    │   │
│ │  Matches:      27 (W 18 / L 9)               │   │
│ │  Recent:                                     │   │
│ │   "I told you to hold." (loss, match 26)     │   │
│ │   "Cleanest opening I've seen." (win, m 25)  │   │
│ │  Autonomy:    ●●●●○ 0.7                      │   │
│ │  [ change persona ] (4/5 lock)               │   │
│ └──────────────────────────────────────────────┘   │
│                                                    │
│ ┌─ Captains ──────────────────────────────────┐   │
│ │  alpha (combat)  appearances: 12  axis: hp  │   │
│ │  bravo (econ)    appearances: 8   axis: -   │   │
│ │  charlie (scout) appearances: 4   axis: speed│  │
│ │  + 3 retired                                 │   │
│ └──────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
```

### 5.2 Deputy persona swap

Brainstorm decision Q4 = (b): **persona is bound for 5 consecutive matches before swap.**

UI surfaces:
- The current persona's portrait + name + memory summary (read-only; memory consolidation happens after each match per 08 §8)
- A "matches since swap: N/5" counter
- A `[change persona]` button — disabled with tooltip when N < 5; enabled and opens persona-picker modal at N ≥ 5

Persona picker modal:
```
┌──────────────────────────────────┐
│ Change deputy persona            │
│                                  │
│  ◉ Veteran   (current — 27 matches) │
│  ○ Aggro    (12 matches)          │
│  ○ Pedant   (3 matches)           │
│                                  │
│  Each persona keeps its own      │
│  memory. Swapping does not       │
│  reset Veteran.                  │
│                                  │
│   [ confirm ]   [ cancel ]       │
└──────────────────────────────────┘
```

Swap is non-destructive — each `DeputyPersona` keeps its own `DeputyMemory` file (08 §8.1). Swapping resets the lock counter to 0.

Override path for testing: a debug build (`debug=true` in `project.godot`) bypasses the lock. v1 ships with the lock active; "let me change every match" is a player-requested settings toggle in 10+1.

### 5.3 Autonomy dial

Reads/writes `DeputyPersona.deputy_autonomy` (08 §9). Slider with three labeled bands per 08 §11.8:

```
Cautious  Balanced  Bold
  0.0       0.5      1.0
   ●─────────●─────────●
              ▲ current
```

A short prose explainer:
> "Bold deputies act on best-effort and clarify only when a command is dangerous. Cautious deputies ask first when anything is ambiguous."

Changes apply on save and propagate to the next match.

### 5.4 Captain roster

Read-only table of captains with persistent memory (`MemoryStore.list_captains()`).

Columns:
- **name** (`captain_persona_id`)
- **role** (combat / econ / scout)
- **appearances** (`match_appearances`)
- **co-wins** (`matches_won_alongside`)
- **deaths**
- **preferred axis** (— / hp / dps / sight / speed)
- **reinforcement** (e.g. "+8% hp")

Click a row → captain detail modal showing the captain's anecdotes (last 12) and an "explain this captain" button that triggers a small LLM call summarizing the captain's style.

"Retired" captains are those whose persona hasn't appeared in the last 10 matches. They remain in `MemoryStore` but are visually de-emphasized; deleting a captain's memory is a deliberate destructive action behind a confirm.

## 6. Settings Tab

Standard settings panel layout. Sections:

| Section | Settings |
|---|---|
| **Gameplay** | Control policy (FullControl / HeroOnly / AssistMode / ArchonControl from 07 §8); persona-swap lock (default 5 matches, override here); pre-plan auto-load default |
| **Input** | Mouse buttons (LMB primary per 11 §4.5); keybinds for camera (WASD/edge-scroll toggle per 11 §5.3); voice push-to-talk key (deferred — placeholder) |
| **Audio** | Master / SFX / music / deputy voice volume; voice pack (placeholder, deferred) |
| **Video** | Resolution; window mode; UI scale; camera pitch override (per 11 §5.2 default 75°) |
| **Language** | English / 中文; affects display strings only — internal `StringName` IDs unchanged |
| **Developer** | (debug builds only) replay mode, mock LLM, log verbosity, `--archon-attach` shortcut |

Setting writes go to `user://settings.cfg` via `ConfigFile`. Most settings are read at boot and on tab leave; control policy is read at match start (07 §8).

## 7. Lobby Flow (v1: local single-player)

v1 ships **no online lobby**. The Match tab → Start Match path goes directly into a single-player match against scripted/MVP-style enemy buildings (06 §5 deferred — until 09's full executor lands, the enemy faction is the current MVP enemy buildings).

The lobby surface area is documented for future expansion (10+1 networked play, 12 replay viewer):
- **Local replay viewer** — opens a saved `<match_id>.ndjson` (07 §9) and plays it back against a stub world. Belongs to 12.
- **Networked lobby** — joins a remote match. Deferred to 12 networking sub-doc.
- **Archon attach** — local-only F2 toggle in v1 per 08 §11.7; full networked archon deferred.

Three lobby states are reserved as `enum LobbyState { OFFLINE, IN_MATCH, REPLAY, NETWORK_LOBBY }` in code from v1, even though only OFFLINE and IN_MATCH are wired.

## 8. Memory Inspector (Reading 08's Memory Files)

The Camp tab reads `DeputyMemory` and `CaptainMemory` (08 §8 / §11.6) but never writes them mid-match. Per 08 §8 the only mutation point is `MemoryStore.consolidate_after_match(...)`.

10's Camp UI thus operates as **read-only-during-match, read-write-between-matches** for the memory editing affordances:
- **Between matches:** anecdote pruning ("delete this memory"), trait nudges (debug only), preferred-axis manual override (debug only)
- **During match:** Camp tab is *visible* if the player alt-tabs back, but all writes are blocked with a "save in progress" overlay

The "delete memory" button on a captain triggers a two-step confirm + writes to a `user://deputies/<id>.tres.bak` file before nuking — a soft-delete safety net.

## 9. Faction Future Hooks

09 §13 locks in the 3-faction roadmap (猫狗 / 鹅鸭 / 野生动物). 10's faction dropdown on the Match tab and the persona-list filter on the Camp tab are designed today to accommodate it:

```
Faction: [ shared (v1)        ▼ ]
         ──────────────────────
         · shared (v1)
         · 猫狗 (Cats & Dogs) — locked
         · 鹅鸭 (Geese & Ducks) — locked
         · 野生动物 (Wild) — locked
```

Locked entries are visible but greyed-out with tooltips referring to 09+1's future content. This bakes in the long-term promise without committing v1 work to it.

## 10. Resource and Persistence Map

Where every UI state lives:

| Surface | Storage |
|---|---|
| Pre-plans (player) | `user://preplans/<player_id>/<map_id>/*.tres` (07 §7.2) |
| Pre-plans (designer) | `res://data/preplans/<map_id>/*.tres` (07 §7.2) |
| Player regions | `user://player_regions/<player_id>/<map_id>.tres` (07 §3.3) |
| Deputy memory | `user://deputies/<deputy_id>.tres` (08 §8) |
| Captain memory | `user://captains/<captain_persona_id>.tres` (08 §11.6) |
| Settings | `user://settings.cfg` (10 §6) |
| Persona-swap lock counter | inside `user://settings.cfg` |

10's UI **never invents** new persistence locations — every file path above is owned by a sibling spec (07 / 08 / 06 / this section). UI is a reader/writer, not an author of new state shapes.

## 11. Boundaries

- **10 ↔ 07:** 10 reads `OrderTypeRegistry`, writes `PrePlan` and `PlayerRegionSet` resources, calls `ShareCodeService.{encode,decode}`. 10 imports no other 07 internals.
- **10 ↔ 08:** 10 reads `DeputyMemory` / `CaptainMemory` between matches. 10 writes `DeputyPersona.deputy_autonomy` (a v1 mutation point on `DeputyPersona` resources). 10 calls `MemoryStore.list_captains()` / `MemoryStore.delete_captain(...)` (a new method this doc requires).
- **10 ↔ 09:** 10 reads `UnitDef.category` / `BuildingDef.category` for editor dropdowns; reads `MapGrid` / `Landmark` lists for the region tool.
- **10 ↔ 11:** No direct dependency. 11 governs in-match feel; 10 is between-match.

## 12. Files

### New files (this spec defines)

- `godot/scripts/ui/main_menu.gd` — root tab shell
- `godot/scripts/ui/match_tab.gd`
- `godot/scripts/ui/warroom_tab.gd`
- `godot/scripts/ui/camp_tab.gd`
- `godot/scripts/ui/settings_tab.gd`
- `godot/scripts/ui/preplan_editor.gd`
- `godot/scripts/ui/order_edit_modal.gd`
- `godot/scripts/ui/region_painter.gd`
- `godot/scripts/ui/share_code_modal.gd`
- `godot/scripts/ui/persona_picker_modal.gd`
- `godot/scripts/ui/captain_detail_modal.gd`
- `godot/scripts/ui/share_code_service.gd` — interface; encoder deferred per 07 §8.5
- `godot/scenes/main_menu.tscn` — root menu scene; replaces direct boot to `main.tscn` once 10 ships
- `godot/scenes/ui/*.tscn` — one per modal/tab
- `godot/tests/test_main_menu.gd`
- `godot/tests/test_preplan_editor.gd`
- `godot/tests/test_region_painter.gd`
- `godot/tests/test_share_code_service.gd`

### Modified files

- `godot/project.godot` — change `run/main_scene` from `main.tscn` to `main_menu.tscn` (only when 10 implementation lands; not as part of this doc)
- `godot/scripts/bootstrap.gd` — accept lobby state at construction, branch into match scene only on Start Match
- `docs/specs/05-godot-smoke-test-checklist.md` — add main-menu boot section after implementation

## 13. Verification (Skeleton)

A 10 implementation is "skeleton-complete" when:

1. `main_menu.tscn` boots; the four tabs render without script error.
2. Match tab: opening it shows the current `DeputyPersona` and at least one map in the dropdown.
3. War-Room tab: creating a new plan, editing one order with each `target_kind` value, and saving produces a valid `.tres` file under `user://preplans/`.
4. War-Room tab: invalid plans surface inline errors and block save.
5. War-Room tab: the four parametric placeholders appear in the param dropdown when `target_kind = param`.
6. Region painter: clicking 5 grid cells, naming the region, saving produces a valid `.tres` file under `user://player_regions/`.
7. Share-code: generate a code, paste into import on the same player, conflict-resolve, and the imported plan appears identically in the plan list.
8. Camp tab: deputy persona dropdown is locked when `match_count_since_persona_swap < 5` and unlocks at 5.
9. Camp tab: autonomy slider movement persists to `DeputyPersona.deputy_autonomy` and survives a restart.
10. Settings tab: changing control policy persists to `settings.cfg` and is read at next match start by `CommandBus`.

10 ships **no in-match changes** — its work is entirely outside the match loop. Until 10 lands, the player drops directly into a match per current MVP boot; no regressions there.

## 14. Open Questions

- **Visual mockups** — Figma file deferred. v1 implementation should pass through a designer review before final styling.
- **Match length on the Match tab** — should we surface the ~15 min target somewhere? Probably yes, near the map preview, but not load-bearing.
- **Deputy "memory deletion" UX** — currently 10 §8 allows captain memory delete; should deputy memory delete also be allowed? Vision §2.3 implies persistent identity, so deleting a deputy's memory is conceptually killing them — handle in 10+1.
- **Pre-plan "test run"** — letting the player simulate a pre-plan against a frozen battlefield snapshot to verify before saving. Powerful but heavy; deferred to 10+1.
- **Multilingual deputy voice pack** — beyond display strings, the deputy speaks in language. v1 ships English + Chinese personas as separate `.tres` files; cross-language switching is a deferred feature.
- **Tutorial flow** — first-launch onboarding walks the player through Match → War-Room → Camp. Specifies in 10+1 (a tutorial sub-doc).

## 15. Future Roadmap

10+1 deliberate enrichments, recorded so v1 doesn't accidentally architect them out:
- Timeline-mode pre-plan editor (Q2 = B)
- Camp 3D visualization (Q1 = D in original brainstorm — show the deputy in a war-tent)
- Networked lobby + matchmaking
- Replay viewer integration with 12
- Tutorial flow
- Persona deletion UX
- Pre-plan test-run sim
- Player ratings on shared codes (community share index)
