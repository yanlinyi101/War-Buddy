# War Buddy

Single-commander RTS prototype built in Godot 4.6.x. You drive one hero, issue text orders to a deputy channel, and knock over three enemy buildings to win.

## Quick Start

### Play the pre-built release

Grab the latest build from [Releases](https://github.com/yanlinyi101/War-Buddy/releases/latest) and extract:

- **Linux** — `./war-buddy.x86_64`
- **Windows** — double-click `war-buddy.exe`
- **Web** — serve the folder over HTTP (e.g. `python -m http.server` inside the extracted dir) and open `http://localhost:8000` in a Chromium-based browser

### Controls

| Input | Action |
| --- | --- |
| Left click on ground | Move hero |
| Left click on enemy building | Target + auto-attack |
| Right click | Cancel target / stop |
| WASD / screen edge / middle-drag | Pan camera |
| Mouse wheel | Zoom |
| Command panel (bottom of screen) | Type an order, pick `combat` or `economy` channel, press **Submit** |

### Victory

Destroy all three enemy buildings. The hero-attack cooldown is 0.75s and each hit deals 20 of 60 HP, so a fresh building goes down in ~2.25s of sustained fire.

### Run from source

Requires Godot 4.6.2-stable:

```bash
godot --editor --path godot
```

The entry scene is `godot/scenes/main.tscn`. See [CLAUDE.md](CLAUDE.md) for the full module map.

## Repository layout

- [`godot/`](godot/) — engine code (GDScript only, no C# / no Unity)
- [`docs/specs/`](docs/specs/) — design, implementation, architecture, and smoke-test specs
- [`.github/workflows/`](.github/workflows/) — CI (headless boot + GUT tests + docs-lint) and tagged releases
- [`CHANGELOG.md`](CHANGELOG.md) — version history

## Status

**v0.1.0** — RTS MVP commander slice is functionally complete. Multi-unit selection, economy, and production are intentionally out of scope for v0.1; see [`docs/specs/04-godot-unity-parity-checklist.md`](docs/specs/04-godot-unity-parity-checklist.md) for what was in-scope vs. deferred.
