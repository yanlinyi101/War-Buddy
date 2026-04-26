# Future Features — Backlog

Catch-all for features that came up in design conversations but were intentionally deferred. Each item should describe the trigger that brought it up, what it would do, and any constraints noted at the time of deferral.

---

## Hero "WASD Arena" + LoL classic dual-input mode

**Source:** Phase C brainstorming (2026-04-26).

**Status:** Deferred. Will land as a *second* supplementary control mode after the v0.2 Squad+AI scaffolding is stable.

### What it is
A second Hero control scheme borrowed from League of Legends. Two sub-features:

1. **WASD Arena steering.** Holding `W` / `A` / `S` / `D` directly drives the Hero like a twin-stick character — bypassing `NavigationAgent3D` pathfinding. Releasing the keys hands control back to whatever order is queued.
2. **Right-click-move + left-click-attack mapping.** LoL classic:
   - Right-click on ground → pathfind move (replaces current left-click-move).
   - Right-click on enemy → approach + auto-attack.
   - Left-click on enemy → "attack click" (force-target, equivalent to right-click on enemy).
   - Left-click on ground → no-op.

The two coexist with the existing left-click-everything scheme as a toggleable mode (e.g. `Settings → Input scheme → Classic / LoL`).

### Why deferred
- Forces a camera-pan key remap (current `camera_pan_*` actions are bound to `WASD`); Phase C doesn't need that churn.
- Hero input rewrite is independent of Squad+AI work, so bundling them adds risk to v0.2.
- Need a settings UI to switch schemes; that's a HUD-side feature and is also not blocking Phase C.

### Constraints when it lands
- WASD steering must skip `NavigationAgent3D` and write directly to `velocity`. Pathfinding resumes on next right-click order.
- Camera pan keys must move off `WASD`. Likely options: arrow keys, screen-edge + middle-drag only, or a "camera follows hero" mode (LoL Arena style).
- `hero_controller.gd::_unhandled_input` will need to branch on the active input scheme. Spec the branch as a small `RefCounted` strategy object so adding more schemes (e.g. controller pad) later is mechanical.

### Acceptance criteria (when implemented)
- A settings toggle picks Classic or LoL scheme; the choice persists across runs.
- LoL: WASD pans hero, right-click pathfind, left-click attack-target. Camera pan still works on whatever keys it ends up on.
- Classic: today's behavior is preserved (left-click move/target, right-click cancel).
- Switching schemes mid-session does not break ongoing orders or selection state.
- Smoke test in `05-godot-smoke-test-checklist.md` gets a parallel section for the LoL scheme.
