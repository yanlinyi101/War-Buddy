# CI/CD overview

## Workflows

| File | Triggers | Purpose |
| --- | --- | --- |
| `ci.yml` | push / PR to `main`, manual | Headless Godot boot, script-parse check, docs sanity |
| `release.yml` | tag `v*`, manual | Export Linux / Windows / Web builds and attach to a GitHub Release |

## Pinned versions

- **Godot:** `4.6.2-stable` (current 4.6 patch). Must match installed editor. Update `GODOT_VERSION` in both workflow files together.
- **Export templates:** pulled from the matching Godot release.

## Preconditions for `release.yml`

`godot/export_presets.cfg` must be committed and contain presets named exactly:

- `Linux/X11`
- `Windows Desktop`
- `Web`

Generate it once by opening the project in the Godot editor → *Project → Export…* → add each preset with the names above → Save → commit the resulting `godot/export_presets.cfg`. The file is intentionally tracked so CI is reproducible.

## Local equivalents

Headless boot (same check CI runs):

```bash
godot4 --headless --path godot --quit-after 120
```

Local export (example):

```bash
godot4 --headless --path godot --export-release "Linux/X11" build/linux/war-buddy.x86_64
```

## Cutting a release

```bash
git tag -a v0.1.0 -m "MVP graybox"
git push origin v0.1.0
```

Monitor the `Release export` workflow. Artifacts land on the tag's GitHub Release page.
