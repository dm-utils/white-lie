# White Lie

Hide and seek in the harbour: hiders become a prop (a barrel, a crate, a buoy), seekers have two and a half minutes
to find them. Stand still and you look like the real thing; move and you give yourself away.

Godot 4.7.2 (GDScript), deterministic integer simulation, online play through a relay with rollback.

- Run the tests: `godot --headless --path . res://tests/run_tests.tscn -- --no-crash-reports --no-network`
- Bot balance: `godot --headless --path . res://tests/hide_balance.tscn -- --sessions=60`
- Debug entry: `godot --path . -- --scene=hide --seed=123` (web: `index.html?scene=hide&seed=123`)
- Generated content (never edit the output by hand): `tools/gen_haven.py` (map), `tools/art/props.py` (props),
  `tools/art/tiles.py` (ground atlas), `tools/audio/sfx.py` (sounds)

© ST33F. All rights reserved: the source is visible, it is not open source.
