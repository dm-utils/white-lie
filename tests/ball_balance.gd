class_name BallBalanceRunner
extends Node
## Strandbal balance runner (phase 14): many all-bot matches headless, then goals, sides and animals.
##   godot --headless --path . res://tests/ball_balance.tscn -- --matches=200 --level=normal --seed=1
## Goals: 2-8 goals per match on average, under 15 % end 0-0, blue and orange each win 45-55 % of decided
## matches, every animal wins 40-60 % of its decided entries. Exit code 1 when outside (CI runs a light version).


func _ready() -> void:
	var args := Boot.parse(OS.get_cmdline_user_args())
	var r := run(int(args.get("matches", "100")), str(args.get("level", "normal")), int(args.get("seed", "1")))
	for line in r.lines:
		print(line)
	get_tree().quit(0 if r.ok or args.get("report", "") == "1" else 1)


static func run(matches: int, level: String, base_seed: int) -> Dictionary:
	var goals := 0
	var nil := 0
	var golden := 0
	var team_wins := [0, 0]
	var decided := 0
	var wins := {}
	var entries := {}
	var kos := 0
	var total_ticks := 0
	var t0 := Time.get_ticks_msec()
	for i in matches:
		var m := Match.create(base_seed + i * 7919, "", 6, level, "ball")
		while not m.finished():
			m.step()
		total_ticks += m.sim.tick
		golden += m.sim.golden
		var g := m.sim.score_0 + m.sim.score_1
		goals += g
		if g == 0:
			nil += 1
		var winner := -1
		if m.sim.score_0 != m.sim.score_1:
			winner = 0 if m.sim.score_0 > m.sim.score_1 else 1
			team_wins[winner] += 1
			decided += 1
		for row in m.sim.result():
			kos += int(row.kos)
			if winner >= 0:
				entries[row.animal] = int(entries.get(row.animal, 0)) + 1
				if int(row.team) == winner:
					wins[row.animal] = int(wins.get(row.animal, 0)) + 1
	var ms := Time.get_ticks_msec() - t0
	var lines: Array = []
	var ok := true
	var avg := float(goals) / maxi(1, matches)
	var nil_pct := 100.0 * nil / maxi(1, matches)
	lines.append("ball balance: %d matches, level %s, %.1f s wall, %.2f ms per 1000 ticks" % [matches, level, ms / 1000.0, ms * 1000.0 / maxf(1.0, total_ticks)])
	lines.append("ball balance: goals per match %.2f, 0-0 %.0f %%, golden goal %d, match length avg %.0f s, KOs per match %.1f" % [
		avg, nil_pct, golden, total_ticks / 30.0 / maxi(1, matches), float(kos) / maxi(1, matches)])
	ok = ok and avg >= 2.0 and avg <= 8.0 and nil_pct < 15.0
	var blue: float = 100.0 * team_wins[0] / maxi(1, decided)
	lines.append("ball balance: decided %d, blue wins %.0f %%, orange %.0f %%" % [decided, blue, 100.0 - blue if decided > 0 else 0.0])
	ok = ok and blue >= 45.0 and blue <= 55.0
	for animal in entries:
		var pct := 100.0 * int(wins.get(animal, 0)) / int(entries[animal])
		lines.append("ball balance: %-8s decided entries %4d  wins %5.1f %%" % [animal, entries[animal], pct])
		ok = ok and pct >= 40.0 and pct <= 60.0
	lines.append("ball balance: %s" % ("within goals" if ok else "OUTSIDE goals"))
	return {"ok": ok, "lines": lines, "avg_goals": avg, "nil_pct": nil_pct, "blue_pct": blue}
