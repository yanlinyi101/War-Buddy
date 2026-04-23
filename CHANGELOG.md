# Changelog

All notable changes to War Buddy are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project follows semantic versioning loosely — pre-1.0 minor bumps may break save-format or API assumptions.

## [v0.1.0] — 2026-04-23

First public cut of the RTS MVP commander slice, fully ported to Godot 4.6.x.

### Added
- **Commander-on-field gameplay loop** — single hero controlled by mouse, raycast-targeted move / attack, enemy building HP feedback, one-shot victory trigger when all three enemy buildings are destroyed.
- **Deputy command console** — two-channel (combat / economy) text command input with a lifecycle state machine (`submitted` → `received` → `pending_execution`) driven by `command_log_model.gd`.
- **Voice placeholder** — visible "Voice (Soon)" button that logs its click without pretending to record.
- **RTS camera** — WASD / screen-edge pan, middle-mouse drag, mouse-wheel zoom (`rts_camera.gd`).
- **Navigation** — `NavigationAgent3D` pathfinding with runtime-baked `NavigationRegion3D`; per-building `NavigationObstacle3D` so the hero actually routes around live buildings.
- **HUD input routing** — explicit `mouse_filter` pass on decorative Controls so clicks fall through to world orders; interactive controls block.
- **Destruction feedback** — 0.35s scale + alpha tween on `EnemyBuilding._destroy()`, with `destroyed` signal emitted before the tween so the victory check fires on the killing-blow frame.
- **`[RTSMVP]` debug log prefix** — every bootstrap, hero input, command, and victory event uses a common prefix for grep-friendly debugging.
- **Headless tests** — [GUT 9.6.0](https://github.com/bitwes/Gut) addon at `godot/addons/gut/`, 10 cases covering command log submission/status lifecycle and match-state one-shot victory invariants.
- **CI/CD**
  - `.github/workflows/ci.yml` — on every push/PR: headless boot + `SCRIPT ERROR` gate + GUT tests + docs-lint that forbids reintroducing Unity artifacts.
  - `.github/workflows/release.yml` — on `v*` tag: matrix export for Linux / Windows / Web, attached to a GitHub Release.
- **Project docs** — `CLAUDE.md` at repo root, five-file `docs/specs/` set covering design, implementation plan, architecture reference, Unity parity outcome, and smoke-test checklist.

### Known issues / intentionally deferred
- **Multi-unit selection, drag-box, squads** — deferred to v0.2+.
- **Economy, workers, production queues, building placement ghosts** — out of scope for the commander MVP slice.
- **Voice input** — UI placeholder only; no real speech recognition.
- **Art assets** — everything is graybox. Visual pass is a v0.2+ concern.

### Migration note
The earlier Unity C# scaffold has been retired from this repo. Only engine-agnostic design text survives in the specs. See [`docs/specs/04-godot-unity-parity-checklist.md`](docs/specs/04-godot-unity-parity-checklist.md) for the close-out audit.
