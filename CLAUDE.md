# CLAUDE.md

Guidance for Claude Code (and any agentic assistant) working in this repository.

## TL;DR

- **Engine:** Godot 4.6.x. GDScript only. No Unity, no C#.
- **Entry point:** `godot/scenes/main.tscn` (see `godot/project.godot`).
- **Source of truth for design:** `docs/specs/01-rts-mvp-design.md`.
- **When in doubt about scope, default to the commander MVP slice**, not the broader Unity-era RTS sandbox.

## Repository layout

```
War Buddy/
├── godot/                 # The game. This is the primary codebase.
│   ├── project.godot      # Engine config, input map, main scene
│   ├── scenes/            # .tscn scene files
│   ├── scripts/           # .gd scripts (one module per file, see below)
│   └── README.md          # Engine-side overview
├── docs/specs/            # Design + architecture + migration docs
│   ├── 01-rts-mvp-design.md
│   ├── 02-rts-mvp-implementation-plan.md
│   ├── 03-godot-rts-architecture-reference.md
│   ├── 04-godot-unity-parity-checklist.md
│   └── 05-godot-smoke-test-checklist.md
├── .github/workflows/     # CI (headless boot) + release export
├── README.md
└── CLAUDE.md              # this file
```

## Module map (what each script owns)

| File | Responsibility |
| --- | --- |
| `godot/scripts/bootstrap.gd` | Root scene wiring, reference validation, signal plumbing |
| `godot/scripts/hero_controller.gd` | Mouse-first move / target / attack (`CharacterBody3D`) |
| `godot/scripts/hero_state.gd` | HUD-facing hero model (HP, target, action) |
| `godot/scripts/command_log_model.gd` | Authoritative deputy command store, timed status progression |
| `godot/scripts/match_state.gd` | Enemy building registry + one-shot victory trigger |
| `godot/scripts/enemy_building.gd` | Destructible `StaticBody3D` with HP + signals |
| `godot/scripts/hud_root.gd` | `CanvasLayer` HUD — command panel, voice placeholder, victory overlay |
| `godot/scripts/rts_camera.gd` | RTS pan / zoom camera (`Camera3D`) |

**Rule:** one module per file. If you need a new subsystem, add a new `.gd` file — don't fold unrelated logic into an existing module.

## Core invariants (do not violate)

1. **Single authoritative match-state path.** Enemy destruction must go through `EnemyBuilding.destroyed` → `MatchState.mark_destroyed`. No side paths.
2. **Victory triggers exactly once.** Guard in `match_state.gd` with `victory_trigger_count`.
3. **HUD clicks must not leak into world orders.** Before any raycast, check `get_viewport().gui_get_hovered_control() == null`.
4. **Command records are immutable after submit.** Status progression mutates only the `status` field and emits `command_status_changed`.
5. **Voice input is a placeholder only.** No fake recording flow, no "active" state.
6. **Bootstrap fails loud on missing references.** Use `assert` so broken scenes surface immediately.

## Build / run / test

```bash
# Open in editor
godot4 --editor --path godot

# Headless boot (same check CI runs)
godot4 --headless --path godot --quit-after 120

# Export (needs godot/export_presets.cfg + export templates installed)
godot4 --headless --path godot --export-release "Linux/X11" build/linux/war-buddy.x86_64
```

There is no test runner wired yet. Adding GUT or a hand-rolled `SceneTree` harness is tracked as Task 2 in [`02-rts-mvp-implementation-plan.md`](docs/specs/02-rts-mvp-implementation-plan.md).

## CI/CD

- `ci.yml` — every push/PR: install Godot 4.6-stable, headless boot, fail on `SCRIPT ERROR` / `Parse Error` / missing scripts, plus a docs sanity check that forbids reintroducing Unity artifacts.
- `release.yml` — on tag `v*`: export Linux / Windows / Web builds and attach them to a GitHub Release. Requires `godot/export_presets.cfg` to be committed.

Update `GODOT_VERSION` in both workflow files together whenever `godot/project.godot` bumps engine versions. See [`.github/workflows/README.md`](.github/workflows/README.md) for details.

## Conventions

- **GDScript style:** snake_case for files, vars, and funcs; PascalCase for `class_name`; typed signatures (`func foo(x: int) -> void`) when the type is obvious.
- **Signals over polling.** If a module needs to react to a state change, connect to a signal — don't peek at another node's fields from `_process`.
- **Resource paths:** always `res://…`, never relative.
- **No autoloads yet.** When the architecture reference (`03-...`) picks up `CommandBus` / `EventBus`, introduce them as Autoloads — but not before.
- **Scenes stay graybox.** Don't import art assets to "make it look nicer" unless the task explicitly asks for it.
- **Commit messages:** conventional-commit prefix (`feat(godot):`, `fix:`, `docs:`, `ci:`, `test:`).

## Out-of-scope guardrails

The following were in the retired Unity sandbox and are **not** MVP blockers. Don't add them unless a task explicitly scopes them in:

- multi-unit selection / drag-box selection
- squads, rally points, recall hotkeys
- workers, gather/return loop, depots, resource nodes
- production queues, building placement ghosts
- full order vocabulary (stop / hold / attack-move)
- real networking or second-player sync
- voice recognition, TTS, real AI deputy execution

If a request seems to pull scope into this list, surface the scope question before implementing.

## When editing docs

- The files in `docs/specs/` are the design contract. Treat them as code: if you change behavior that a spec names, update the spec in the same change.
- Don't reintroduce Unity terminology (`MonoBehaviour`, `.unity` scenes, Unity Test Runner, `SharedOfficeWars`). CI's `docs-lint` job will fail the build.

## Useful external docs

- Godot 4 docs: https://docs.godotengine.org/en/stable/
- GDScript style guide: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html
