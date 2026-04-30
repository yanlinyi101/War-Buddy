# Test and Replay Strategy

Date: 2026-04-28
Project: War Buddy (Godot 4.6.x)
Status: Draft. Spec-only. Cross-cutting strategy doc — does not introduce product features. Defines how 06–11's behavior gets verified and replayed.

Parents: 06.
Cross-references: 07 (`.ndjson` order log = the replay input format), 08 (`MockClient` interface for LLM testing), 09 (behavior trees per unit), 10 (UI smoke), 11 (feel verification log).

## 1. Purpose

War Buddy combines four classes of behavior that are unusually hard to test together:
- Deterministic Godot game logic (movement, collision, command bus)
- Non-deterministic LLM output (deputy / captain plans)
- Physics-coupled feel (11)
- Multi-screen UI flow (10)

12 names how each class gets verified, how the layers compose into integration and E2E, and how a saved match becomes a replayable artifact. It is *not* a doc about adding features; it is a doc about not regressing them.

12 is structurally minimal in v1 — just enough scaffolding to keep the lights on while 07–10 implementations land. Heavier surfaces (perf benchmarks, prompt-drift fixtures, fuzzers) are documented as 12+1 entries.

## 2. The Test Pyramid (Three Layers)

```
                    ┌──────────────┐
                    │ E2E (~5)     │   manual + occasional headless
                    └──────────────┘
                ┌──────────────────────┐
                │ Integration (~30)    │   GUT, multi-node scene fixtures
                └──────────────────────┘
        ┌──────────────────────────────────┐
        │ Unit (~200+)                     │   GUT, per-script
        └──────────────────────────────────┘
```

| Layer | Count target | Runtime | Where |
|---|---|---|---|
| **Unit** | ~200+ (one `test_*.gd` per script) | < 5 s each | `godot/tests/unit/` |
| **Integration** | ~30 (one per cross-module path) | < 30 s each | `godot/tests/integration/` |
| **E2E** | ~5 (full match flows) | < 3 min each | `godot/tests/e2e/` |

Total runtime targets: unit suite < 90 s; integration < 10 min; E2E run on a knob, not every PR.

## 3. Unit Testing (GUT)

### 3.1 File-per-script convention

For every script under `godot/scripts/<area>/foo.gd` there is a `godot/tests/unit/<area>/test_foo.gd`. New scripts without a sibling test file fail a CI lint check.

Test file scaffold:

```gdscript
extends GutTest

const Foo := preload("res://scripts/area/foo.gd")

var _foo: Foo

func before_each() -> void:
    _foo = Foo.new()

func after_each() -> void:
    _foo.queue_free()

func test_default_state() -> void:
    assert_eq(_foo.some_field, expected_default)
```

### 3.2 Coverage rules

- **Pure functions** (validators, math, parsers): 100% line + branch
- **Resource classes** (`TacticalOrder`, `UnitDef`, etc.): 100% on `to_dict` / `from_dict` round-trip + invariant checks
- **Stateful nodes** (`CommandBus`, `Deputy`, etc.): 100% on signal-emitting paths; ≥70% line on the rest
- **UI scripts** (10): basic instantiation + signal wire-up only; visual rendering is not unit-tested

### 3.3 Disallowed patterns

- No live HTTP calls (use `MockClient` from 08 §5)
- No `await get_tree().create_timer(...)` in unit tests — use `gut.simulate(node, frames, delta)` for time-dependent paths
- No reading `user://` paths unless mocked (`use_themed_resource_path = true` in tests)
- No depending on order-of-loaded autoloads — instantiate directly with `Foo.new()`

### 3.4 GUT command-line invocation

```bash
godot4 --headless --path godot -s addons/gut/gut_cmdln.gd \
   -gdir=res://tests/unit -gexit -gjunit_xml_file=res://test-results-unit.xml
```

CI consumes the JUnit XML to surface failures.

## 4. Integration Testing

Integration tests verify cross-module paths. Each lives in `godot/tests/integration/test_<path>.gd` and exercises:

| Path | Modules involved |
|---|---|
| `test_utterance_to_order` | ClassifierRouter (mock) → Deputy → CommandBus → recent buffer |
| `test_pre_plan_match_start` | PrePlanRunner → CommandBus → recent buffer |
| `test_strategic_decomposition` | LLM mock returning multi-order plan → CommandBus accepts each + parent_intent_id chain |
| `test_archon_attached_rejects_llm` | ArchonControlPolicy + LLM Deputy plan → rejected with `&"archon_attached"` |
| `test_captain_reinforcement_applied` | MemoryStore returns reinforcement → 09 squad spawn applies axis bonus |
| `test_supply_blocks_production` | Faction at supply cap → `train` order rejected with reason |
| `test_command_lifecycle` | submit → classifying → dispatched → executing → completed |
| `test_persona_swap_lock` | match counter → swap blocked < 5 / unlocked ≥ 5 |

Each integration test boots a minimal scene fixture (just the autoloads needed) and drives a single end-to-end path with mocks at the LLM boundary. They do not run a full match.

## 5. End-to-End Testing

E2E covers full match flows. v1 E2E targets are deliberately small (5 scenarios), driven manually most of the time:

| Scenario | What it verifies |
|---|---|
| `e2e_quick_match_default_persona` | Boot → Match tab → Start → 5 second match → no script errors |
| `e2e_pre_plan_invocation` | Pre-plan triggers `match_start`, deputy executes, orders reach buildings |
| `e2e_voice_text_command` | Type "go to B4" → mock deputy emits move plan → unit moves |
| `e2e_archon_handoff` | F2 attach → human types command → CommandBus accepts under archon policy |
| `e2e_match_victory` | Destroy all enemy buildings → MatchState.victory_triggered → menu returns |

E2E uses a special `--e2e-mode` boot flag that:
- Pre-binds `MockClient` for all LLM seats with deterministic canned responses
- Disables `Time.get_unix_time_from_system()` in favor of a tick counter (deterministic)
- Records every signal emission to `user://e2e_log.ndjson` for later assertion

Manual E2E is a checklist run before each release tag. Automated headless E2E is a 12+1 enrichment (Godot's --headless can drive scenes but UI assertions are awkward).

## 6. LLM Testing Strategy

### 6.1 CI-only mock policy

Per Q2 brainstorm decision: **CI never calls real LLM providers.** All tests use `MockClient` (08 §5) with explicitly configured canned responses.

```gdscript
# example mock setup in an integration test
var mock := MockClient.new()
mock.queue_response(SubmitPlanResponse.new({
    "plans": [some_action_plan],
    "elapsed_seconds": 0.05,
}))
classifier.set_llm_client(mock)
```

This makes CI:
- Fast: no network, no token cost
- Stable: zero flakiness from API outages
- Free: no spend on every PR
- Limited: blind to prompt drift (08's prompt change that subtly degrades quality won't fail CI)

### 6.2 Manual smoke with real LLM

A `manual/smoke_real_llm.md` checklist documents the 6–10 utterance scenarios that should be sanity-checked against a real provider before each release. The tester:
1. Sets `DEEPSEEK_API_KEY` (or fallback `ANTHROPIC_API_KEY`)
2. Boots with `--smoke-real-llm`
3. Walks through each utterance, eyeballs the response
4. Notes deviations in the smoke checklist

### 6.3 Mock fixture library

Common test scenarios get reusable mock responses in `res://tests/fixtures/mock_plans/`. Examples:

```
res://tests/fixtures/mock_plans/
├── attack_b4.tres            # ActionPlan: deputy=combat, single move+attack order
├── eco_boost.tres            # ActionPlan: deputy=combat, build supply_depot
├── ambiguous_high_ground.tres  # ActionPlan with target_kind=ambiguous
├── refusal_hold_fire.tres    # ActionPlan with rationale only, no orders
└── ...
```

Fixtures load via `preload(...)` in tests; they must round-trip through `to_dict` / `from_dict` so any 07 schema break catches them.

## 7. Replay System

### 7.1 Replay = stub playback (Q3 = B decision)

Replay is **not** a re-simulation. It is a viewer that ingests the NDJSON command log (07 §9) and renders the temporal sequence of plans, orders, and state transitions against a stub world.

What replay shows:
- Every accepted plan (timestamp, deputy, rationale)
- Every accepted order (timestamp, type, target, force, status)
- Status transitions through the 8-state lifecycle
- Rejection reasons for declined orders

What replay does **not** show:
- Re-simulated unit movement (no behavior tree execution)
- LLM calls (the recorded plans are used as-is)
- Physics, particles, audio
- Live victory triggers (replay reads the recorded victory event, doesn't re-derive it)

### 7.2 Replay file structure

The 07 §9 NDJSON files (one per match):

```
user://order_log/<match_id>.ndjson         # accepted orders, one per line
user://order_log/<match_id>.rejected.ndjson  # rejected orders + reason
user://order_log/<match_id>.plans.ndjson   # full plans before order extraction
user://order_log/<match_id>.events.ndjson  # 09 EventBus events (unit_died, victory, etc.)
```

Plus a manifest:

```json
// user://order_log/<match_id>.manifest.json
{
  "match_id": "match_2026_04_28_abc",
  "started_at": "2026-04-28T14:32:00Z",
  "ended_at": "2026-04-28T14:47:12Z",
  "outcome": "victory",
  "schema_version": 1,
  "deputy_persona": "deputy_veteran",
  "map_id": "forest_lake"
}
```

### 7.3 Replay viewer scene

`godot/scenes/replay_viewer.tscn` — a minimal scene with:

- Map preview (cosmetic — same map asset as in-match)
- Timeline scrubber (drag through match time)
- Play / pause / 1× / 2× / 4× speed controls
- Plan log (left panel) — shows plans in chronological order
- Order log (right panel) — shows orders with state transitions
- "Jump to next failure" button

The viewer instantiates a stub `CommandBus` and re-emits signals from the NDJSON in timestamp order; HUD components subscribe normally so the visual experience matches in-match HUD.

### 7.4 Replay invocation

```bash
godot4 --path godot scene_replay_viewer.tscn -- --replay <match_id>
```

In editor: a custom dock lists matches under `user://order_log/` with a "play" button per match.

### 7.5 What replay does **not** solve (12+1)

- Bug repro for physics-coupled bugs (would need full re-sim — Q3 = A territory)
- Networked replay sync (PvP era)
- Forking ("what if I did X at the 5-minute mark?") — needs re-sim
- Compressing long replays (NDJSON gets verbose)

## 8. CI Strategy

Three tiers per Q4 = C decision:

### 8.1 Per-PR CI (every push, < 5 min)

`.github/workflows/ci.yml` (existing, extended):

- Headless boot (existing)
- Docs lint: forbid Unity terminology + verify every NN-name.md has a NN-name.zh.md sibling (new)
- GUT unit suite (`tests/unit/`) — fail on any failure
- GUT integration suite (`tests/integration/`) — fail on any failure
- Coverage threshold check: line ≥70%, branch ≥60% (per Q5)
- Lint: every `.gd` script under `scripts/` has a sibling test file

Failures block merge.

### 8.2 Nightly CI (cron `0 3 * * *`)

`.github/workflows/nightly.yml` (new):

- Per-PR suite (above) — re-run for clean slate
- Headless E2E suite (`tests/e2e/`) — runs the 5 scenarios with `--e2e-mode`
- Build artifacts: Linux, Windows, Web export — verify build succeeds (don't ship)
- Memory leak check: 10-minute headless run, watch RSS curve

Failures notify the team (issue auto-opened) but don't block ongoing PRs.

### 8.3 Weekly CI (cron `0 5 * * 0`)

`.github/workflows/weekly.yml` (new):

- Performance benchmarks: target match scenario, measure tick rate, frame time, LLM-mock latency, memory peak
- Multi-platform E2E: Linux + Windows + macOS (the latter is a stretch; v1 may skip)
- Coverage report: full HTML report uploaded as artifact
- 12+1 hooks: prompt-drift fixture run when added (currently empty)

Weekly results land in a tracked dashboard (deferred — for now, opens an issue with summary).

### 8.4 What CI does **not** run

- Real LLM calls (per Q2)
- Networked tests (no networking yet)
- GPU rendering tests (CI runners are headless / software-rendered)
- Steam Deck / mobile validation (deferred)

## 9. Coverage Targets

Per Q5 = (b):

- **Line coverage:** ≥ 70% across all `godot/scripts/`
- **Branch coverage:** ≥ 60% across all `godot/scripts/`
- **Per-module floor:** Core modules (`scripts/command/`, `scripts/ai/deputy.gd`, `scripts/ai/classifier_router.gd`) ≥ 85% line

Lower tiers tolerated:
- **UI scripts (`scripts/ui/`):** ≥ 50% line — much of this is visual, hard to test meaningfully
- **Persona / data resources:** no coverage target — they are data, not code
- **HTTP clients (`scripts/ai/*_client.gd`):** ≥ 60% — error paths are hard to mock, but happy paths are required

CI lint checks per-module floor and fails if violated. The aggregated target is informational (warns but doesn't fail) so a refactor that legitimately drops coverage temporarily isn't blocked.

## 10. Test Data and Fixtures

### 10.1 Fixture directory layout

```
godot/tests/fixtures/
├── mock_plans/                 # ActionPlan fixtures (§6.3)
├── battlefield_snapshots/      # frozen snapshots for testing the LLM mock-pipeline
├── pre_plans/                  # PrePlan resources for regression tests
├── replays/                    # checked-in replay NDJSON files for replay-viewer tests
└── personas/                   # frozen persona resources (test variants of 08's three)
```

### 10.2 Fixture maintenance rules

- Fixtures must round-trip through current schema (`to_dict` / `from_dict`)
- Schema changes break fixtures; the breaking PR also fixes fixtures
- Fixtures are **not** auto-regenerated — humans review them
- Each fixture has a sibling `.notes.md` explaining the scenario in 1–3 sentences

### 10.3 Mock LLM canned responses

Mock responses are paired with the utterance they answer:

```gdscript
# tests/fixtures/mock_plans/attack_b4_response.gd
const UTTERANCE := "alpha 进攻 B4"
const RESPONSE := preload("res://tests/fixtures/mock_plans/attack_b4.tres")
```

`MockClient.from_fixture_dir(...)` loads all such pairs, allowing tests to use natural utterances:

```gdscript
mock_client.from_fixture_dir("res://tests/fixtures/mock_plans/")
classifier.handle_utterance("alpha 进攻 B4", &"text_input")
# response auto-resolved
```

## 11. Test Infrastructure Files

### New files (this spec defines)

- `godot/tests/unit/` — directory; one `test_*.gd` per script
- `godot/tests/integration/` — 8 integration tests per §4
- `godot/tests/e2e/` — 5 E2E scripts per §5
- `godot/tests/fixtures/` — fixture tree per §10
- `godot/scenes/replay_viewer.tscn` + `godot/scripts/replay/replay_viewer.gd`
- `godot/scripts/replay/replay_loader.gd` — parses NDJSON into in-memory stream
- `godot/scripts/replay/stub_command_bus.gd` — drop-in CommandBus that re-emits from log
- `.github/workflows/nightly.yml`
- `.github/workflows/weekly.yml`
- `manual/smoke_real_llm.md` — manual real-LLM smoke checklist
- `addons/gut/` — GUT plugin (existing — referenced)

### Modified files

- `.github/workflows/ci.yml` — extend with unit + integration GUT runs, coverage check, sibling-test-file lint
- `godot/scripts/bootstrap.gd` — accept `--e2e-mode` flag and `--replay <match_id>` flag
- `docs/specs/05-godot-smoke-test-checklist.md` — cross-reference 12 for the checklist source

## 12. Boundaries

- **12 ↔ 07:** 12 reads the NDJSON formats 07 §9 specifies. 12 does not modify the order log format.
- **12 ↔ 08:** 12 uses `MockClient` (08 §5) for all CI tests. The fixture library lives under 12.
- **12 ↔ 09:** 12 tests behavior trees and unit definitions via integration tests. 09 owns the data; 12 owns "did it work".
- **12 ↔ 10:** UI scripts get unit-test coverage ≥50%; full UI E2E lives in 12 §5.
- **12 ↔ 11:** 11's verification log is a *separate* artifact from 12's tests. 11 is subjective playtest evidence; 12 is automated. They coexist, neither replaces the other.

## 13. Verification (skeleton)

12 implementation is "skeleton-complete" when:

1. `addons/gut/` is present and `gut_cmdln.gd` runs from headless boot.
2. `godot/tests/unit/` contains test files for every script under `godot/scripts/` (lint check passes).
3. The 8 integration tests in §4 run green via `gut_cmdln.gd -gdir=res://tests/integration`.
4. `godot/scenes/replay_viewer.tscn` boots and accepts a `--replay <match_id>` CLI argument.
5. A recorded match's NDJSON files load in the replay viewer and the timeline scrubber moves through them.
6. `.github/workflows/ci.yml` runs unit + integration suites and fails on any test failure.
7. Coverage ≥ 70% line / ≥ 60% branch achieved on the existing v0.4.1 codebase (or marked as "current target, not yet achieved" if not).
8. A `manual/smoke_real_llm.md` checklist exists with at least 6 scenarios.

## 14. Open Questions

Tracked here, deferred to later 12+ revisions:

- **Prompt-drift fixture system** — Q2 chose A (mock-only); a future Q2-revisit could add nightly real-LLM fixture runs to detect prompt regressions. → 12+1
- **Fuzzer / property tests** — random command generation testing CommandBus invariants. → 12+1
- **Determinism for full re-sim replay** — letting replay actually re-simulate physics + behavior trees by recording RNG seeds + LLM responses. Significant work; skipped per Q3 = B. → 12+2
- **Multiplayer replay sync** — when networking lands. → tied to networking sub-doc
- **Replay forking** ("what if at minute 5...") — needs re-sim. → 12+2
- **Steam Deck / mobile / web platform validation** — when shipping. → release prep doc
- **Performance baseline values** — actual numbers for "tick rate target", "LLM call budget", "memory ceiling". → first weekly CI run establishes empirical baselines

## 15. Future Roadmap

12+1 deliberate enrichments:
- Real-LLM fixture nightly job
- Property-based testing (fuzzer over command schema)
- Replay analysis tools (heatmaps, decision-tree visualization)
- Performance dashboards
- Test sharding for parallel CI

12+2:
- Full deterministic re-sim replay
- Networked replay sync
- Replay forking
- Cross-version replay compatibility (replay schema migration tools)
