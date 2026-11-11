class_name BotBrain
extends RefCounted
## Utility AI. Runs inside the sim tick with the sim's RNG and keeps its memory on the entity (goal, next think,
## strafe side), so bots are part of the deterministic state: same seed -> same match.
## Every few ticks it scores candidate spots (higher ground, good water for water animals, snacks when hurt,
## toward the centre as the tide rises) and decides whether to attack or use its special.

static var _levels: Dictionary = {}


static func level_config(name: String) -> Dictionary:
	if _levels.is_empty():
		_levels = Content.load_json("res://data/bots.json").levels
	return _levels.get(name, _levels.easy)


static func think(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary) -> Dictionary:
	if sim.mode == "ball":
		return BallBrain.think(sim, e, cfg)
	var cmd := {"m": -1, "a": -1, "s": -1}
	var rules := sim.rules
	var near: MatchSim.Ent = null
	var nd2 := 0
	for o in sim.ents:
		if o.alive and o.id != e.id:
			var d2 := MatchSim._d2(o.x - e.x, o.y - e.y)
			if near == null or d2 < nd2:
				near = o
				nd2 = d2
	var nd := Fx.isqrt(nd2) if near != null else 0

	var span := maxi(1, int(rules.tide.max_level) - int(rules.tide.start_level))
	var urgency := sim.level - int(rules.tide.start_level)
	var hurt := e.hp * 10 < e.max_hp * 4
	# aggression grows with the tide: a quarter at the start, full at the last phase
	var aggression := int(cfg.aggression_pct) * (span + 3 * urgency) / (4 * span)
	var engaging := near != null and nd < 8000 and not hurt and e.strafe != 0

	if sim.tick >= e.next_think:
		e.next_think = sim.tick + int(cfg.think_ticks) + sim.rng.range_i(4)
		_pick_goal(sim, e, cfg)
		# strafe = 0 means "not engaging this round"
		e.strafe = 0 if sim.rng.range_i(100) >= aggression else (1 if sim.rng.range_i(2) == 0 else -1)
		if near != null and sim.tick >= int(rules.calm_start_ticks):
			var to := Fx.atan2_a(near.y - e.y, near.x - e.x)
			var close := nd < sim.attack_range(e) * 95 / 100
			# hurt bots only fight back at close range
			if hurt and nd > 3000:
				close = false
			if close and sim.rng.range_i(100) < maxi(aggression, 15 if nd < 3500 else 0):
				var err := int(cfg.aim_error)
				cmd.a = posmod(to + sim.rng.between(-err, err), Fx.ANGLES)
			if e.special >= int(rules.attack.special_hits) and nd < 7000:
				cmd.s = to
				cmd["sd"] = nd

	var gx := e.goal_x - e.x
	var gy := e.goal_y - e.y
	var gd := Fx.dist(gx, gy)
	var vx := 0
	var vy := 0
	if gd > 300:
		vx = gx * Fx.ONE / gd
		vy = gy * Fx.ONE / gd
	if engaging and nd > 0:
		# circle around the nearest enemy instead of walking straight at it
		var side := Fx.atan2_a(near.y - e.y, near.x - e.x) + Fx.QUARTER * e.strafe
		vx += Fx.cos_a(side) * 6 / 10
		vy += Fx.sin_a(side) * 6 / 10
	if vx != 0 or vy != 0:
		cmd.m = Fx.atan2_a(vy, vx)
	return cmd


static func _pick_goal(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary) -> void:
	var tide: Dictionary = sim.rules.tide
	var start := int(tide.start_level)
	var span := maxi(1, int(tide.max_level) - start)
	var urgency := sim.level - start # 0 at the start, span at the end
	var cx := sim.width * MatchSim.TILE / 2
	var cy := sim.height * MatchSim.TILE / 2
	var water := sim.type_of(e) == "water"
	var hurt := e.hp * 2 < e.max_hp
	var look := int(cfg.look_tiles) * MatchSim.TILE
	var best_score: int = -(1 << 40)
	for k in int(cfg.samples):
		var px := e.x
		var py := e.y
		var r := 0
		if k > 0:
			var ang := sim.rng.range_i(Fx.ANGLES)
			r = MatchSim.TILE + sim.rng.range_i(look)
			px = clampi(e.x + Fx.cos_a(ang) * r / Fx.ONE, 500, sim.width * MatchSim.TILE - 500)
			py = clampi(e.y + Fx.sin_a(ang) * r / Fx.ONE, 500, sim.height * MatchSim.TILE - 500)
		var depth := sim.depth_at(px, py)
		var score := -depth * 120 - r / 100
		if depth >= 2:
			score -= 400
		if water and depth == 1:
			score += 80
		if hurt:
			for s in sim.snacks:
				if MatchSim._d2(s[0] - px, s[1] - py) < 2000 * 2000:
					score += 150
		score -= Fx.dist(px - cx, py - cy) / 100 * urgency / span
		# early on, keep some distance from others (less as the island shrinks); hurt bots always do
		var calm_weight := (span - urgency) if not hurt else span
		for o in sim.ents:
			if o.alive and o.id != e.id:
				var od := Fx.dist(o.x - px, o.y - py)
				if od < 6000:
					score -= (6000 - od) / 40 * calm_weight / span
		if score > best_score:
			best_score = score
			e.goal_x = px
			e.goal_y = py
