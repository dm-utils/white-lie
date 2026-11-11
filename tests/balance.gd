extends Node
## Bot balance runner: many all-bot matches headless, then win rate per animal and match length.
##   godot --headless --path . res://tests/balance.tscn -- --matches=200 --level=easy --seed=1
## Goals (phase 3): no animal above 45 % or below 22 % wins; matches 2-3 minutes.


func _ready() -> void:
	var args := Boot.parse(OS.get_cmdline_user_args())
	var matches := int(args.get("matches", "100"))
	var level := str(args.get("level", "easy"))
	var base_seed := int(args.get("seed", "1"))
	var wins := {}
	var entries := {}
	var kos := {}
	var total_ticks := 0
	var longest := 0
	var shortest := 1 << 30
	var t0 := Time.get_ticks_msec()
	for i in matches:
		var m := Match.create(base_seed + i * 7919, "", 6, level)
		while not m.finished():
			m.step()
		total_ticks += m.sim.tick
		longest = maxi(longest, m.sim.tick)
		shortest = mini(shortest, m.sim.tick)
		for r in m.sim.result():
			entries[r.animal] = int(entries.get(r.animal, 0)) + 1
			kos[r.animal] = int(kos.get(r.animal, 0)) + int(r.kos)
			if r.place == 1:
				wins[r.animal] = int(wins.get(r.animal, 0)) + 1
	var ms := Time.get_ticks_msec() - t0
	print("balance: %d matches, level %s, %.1f s wall, %.2f ms per 1000 ticks" % [matches, level, ms / 1000.0, ms * 1000.0 / maxf(1.0, total_ticks)])
	print("balance: match length avg %.0f s, min %.0f s, max %.0f s" % [total_ticks / 30.0 / matches, shortest / 30.0, longest / 30.0])
	var ok := true
	for animal in entries:
		# win rate per entry: with 6 players a fair animal wins 1/6 of its entries
		var per_entry := 100.0 * int(wins.get(animal, 0)) / int(entries[animal])
		var share := 100.0 * int(wins.get(animal, 0)) / matches
		print("balance: %-8s entries %4d  wins %4d  win%%/entry %5.1f  share of wins %5.1f  KOs/entry %.2f" % [
			animal, entries[animal], wins.get(animal, 0), per_entry, share, float(kos.get(animal, 0)) / int(entries[animal])])
		if share > 45.0 or share < 22.0:
			ok = false
	print("balance: %s" % ("within goals" if ok else "OUTSIDE goals (share of wins must be 22-45 %)"))
	get_tree().quit(0)
