# Getij

Beach animals brawl on a shrinking island while the tide comes in. Godot 4.7.2 (pinned), GDScript.

## Run

```
godot --path .                                   # normal start
godot --path . -- --scene=match --seed=123       # debug entry: straight into a scene with a seed
```

Web: `index.html?scene=match&seed=123`.

## Test

```
godot --headless --path . --import
godot --headless --path . res://tests/run_tests.tscn
python -I tools/web_smoke.py build/web           # after exporting the "Web" preset
```

## Layout

| Folder | Contents |
|---|---|
| `sim/` | Pure, deterministic game rules (no nodes, no wall clock, seeded RNG) |
| `bots/` | Bot AI, runs inside the sim tick |
| `view/` | Scenes, animation, effects, camera |
| `ui/` | Screens, HUD, theme |
| `platform/` | `Platform` autoload: the only door to the backend |
| `boot/` | Debug entry point |
| `data/` | Content as JSON |
| `i18n/` | `strings.csv`: every player-facing text, via `tr("KEY")` |
| `assets/` | Art, audio, fonts; every file has a row in `assets/credits.csv` |
| `tests/` | Headless test runner |
| `tools/` | Build and check scripts |

## Rules

- No player-facing string inline: `tr("KEY")`, and the key goes into `i18n/strings.csv` in the same change.
- No asset without a row in `assets/credits.csv` (source, author, licence, date).
- `develop` gets the work; `main` changes only through a pull request the owner merges. Never force-push.
