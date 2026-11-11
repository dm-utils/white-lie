class_name HideBalanceRunner
extends Node
## Verstoppertje balance runner (phase 2): many all-bot sessions headless, then hiders found per round.
##   godot --headless --path . res://tests/hide_balance.tscn -- --sessions=60 --level=normal --seed=1
## Goals: 2-3 of 4 hiders found per round on average, under 15 % of rounds with nobody found, under 15 % with all
## found within 60 s. Exit code 1 when outside (unless --report=1).


func _ready() -> void:
	var args := Boot.parse(OS.get_cmdline_user_args())
	var r := run(int(args.get("sessions", "40")), str(args.get("level", "normal")), int(args.get("seed", "1")))
	for line in r.lines:
		print(line)
	get_tree().quit(0 if r.ok or args.get("report", "") == "1" else 1)


static func run(sessions: int, level: String, base_seed: int) -> Dictionary:
	var rounds := 0
	var found := 0
	var nobody := 0
	var quick := 0
	var hider_pts := 0
	var t0 := Time.get_ticks_msec()
	var ticks := 0
	for i in sessions:
		var m := HideMatch.create(base_seed + i * 7919, "", 6, level)
		var last := -1
		while not m.finished():
			m.step()
			var s := m.sim
			if s.phase == HideSim.PHASE_REVEAL and last != s.round_no:
				last = s.round_no
				rounds += 1
				var f := s.hiders_total() - s.hiders_left()
				found += f
				nobody += 1 if f == 0 else 0
				quick += 1 if s.hiders_left() == 0 and s.tick - s.seek_from <= 1800 else 0
		ticks += m.sim.tick
		var res := m.sim.result()
		for row in res:
			hider_pts += int(row.points)
	var avg := float(found) / maxi(1, rounds)
	var nobody_pct := 100.0 * nobody / maxi(1, rounds)
	var quick_pct := 100.0 * quick / maxi(1, rounds)
	var ok := avg >= 2.0 and avg <= 3.0 and nobody_pct < 15.0 and quick_pct < 15.0
	var lines := [
		"hide balance: %d sessions (%d rounds), level %s, %.1f s wall, %.2f ms per 1000 ticks" % [sessions, rounds, level, (Time.get_ticks_msec() - t0) / 1000.0, (Time.get_ticks_msec() - t0) * 1000.0 / maxf(1.0, ticks)],
		"hide balance: found per round %.2f of 4, nobody found %.0f %%, all found within 60 s %.0f %%, points per seat per session %.1f" % [avg, nobody_pct, quick_pct, float(hider_pts) / maxi(1, sessions * 6)],
		"hide balance: %s" % ("within goals" if ok else "OUTSIDE goals"),
	]
	return {"ok": ok, "lines": lines, "avg_found": avg, "nobody_pct": nobody_pct, "quick_pct": quick_pct}
