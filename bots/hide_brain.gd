class_name HideBrain
extends RefCounted
## White Lie bots (phase 2). Same rules as Getij's BotBrain: they run inside the sim tick with the sim's RNG and
## keep their memory on the entity, so they are deterministic. They play fair: a seeker bot only uses what a person
## could see (fresh tells, plain animals) plus a small chance to try a random prop.

static var _levels: Dictionary = {}


static func level_config(name: String) -> Dictionary:
	if _levels.is_empty():
		_levels = Content.load_json("res://data/hide_bots.json").levels
	return _levels.get(name, _levels.normal)


static func think(sim: HideSim, e: HideSim.Ent, cfg: Dictionary) -> Dictionary:
	match e.role:
		HideSim.HIDER:
			return _hider(sim, e, cfg)
		HideSim.SEEKER:
			return _seeker(sim, e, cfg)
	return _gull(sim, e)


## Hide phase: walk to a prop with look-alikes nearby and become that kind; then stand still. In the seek phase only
## move (to another group) when a seeker comes close, sometimes.
static func _hider(sim: HideSim, e: HideSim.Ent, cfg: Dictionary) -> Dictionary:
	var cmd := {"m": -1, "a": -1, "s": -1}
	if sim.phase == HideSim.PHASE_REVEAL:
		return cmd
	if e.target < 0:
		e.target = _pick_spot(sim, e, cfg)
		var p: Array = sim.props[e.target]
		# stand right next to it, on the side away from the office (the seekers come from there)
		e.goal_x = p[1] - 650
		e.goal_y = p[2] + sim.rng.between(-300, 300)
	var gx := e.goal_x - e.x
	var gy := e.goal_y - e.y
	var gd := Fx.dist(gx, gy)
	# out of hiding time (or the spot can't be reached): become the nearest prop right here
	var late := sim.phase == HideSim.PHASE_SEEK or sim.phase_left < 90
	if e.disguise < 0 and late and e.cooldown == 0:
		var n := _nearest_prop(sim, e)
		cmd.a = Fx.atan2_a(sim.props[n][2] - e.y, sim.props[n][1] - e.x)
		return cmd
	if e.disguise < 0 or sim.phase == HideSim.PHASE_HIDE:
		if gd > 200:
			cmd.m = Fx.atan2_a(gy, gx)
		elif e.disguise < 0 and e.cooldown == 0:
			var p: Array = sim.props[e.target]
			cmd.a = Fx.atan2_a(p[2] - e.y, p[1] - e.x)
		return cmd
	# seek phase, disguised: hold still; flee to another group now and then when a seeker is close
	if sim.tick >= e.next_think:
		e.next_think = sim.tick + int(cfg.think_ticks) + sim.rng.range_i(6)
		var near := _nearest_seeker(sim, e)
		if near >= 0 and near < 2500 and sim.rng.range_i(100) < int(cfg.flee_pct):
			e.target = _pick_spot(sim, e, cfg)
			var p: Array = sim.props[e.target]
			e.goal_x = p[1] - 650
			e.goal_y = p[2]
	if gd > 200:
		cmd.m = Fx.atan2_a(gy, gx)
	elif e.disguise != int(sim.props[e.target][0]) and e.cooldown == 0:
		var p: Array = sim.props[e.target]
		cmd.a = Fx.atan2_a(p[2] - e.y, p[1] - e.x)
	return cmd


## A prop with at least one look-alike within 3 tiles, not too close to other hiders; random among the best.
static func _pick_spot(sim: HideSim, e: HideSim.Ent, cfg: Dictionary) -> int:
	var best := 0
	var best_score := -(1 << 30)
	for k in int(cfg.samples):
		var i := sim.rng.range_i(sim.props.size())
		var p: Array = sim.props[i]
		var score := 0
		for q in sim.props:
			if q[0] == p[0] and HideSim._d2(q[1] - p[1], q[2] - p[2]) < 3000 * 3000:
				score += 100
		for o in sim.ents:
			if o.id != e.id and o.role == HideSim.HIDER and HideSim._d2(o.goal_x - p[1], o.goal_y - p[2]) < 2500 * 2500:
				score -= 150
		score -= Fx.dist(p[1] - e.x, p[2] - e.y) / 60 # close by: walls make far spots unreachable in 20 s
		if score > best_score:
			best_score = score
			best = i
	return best


static func _nearest_prop(sim: HideSim, e: HideSim.Ent) -> int:
	var best := 0
	var bd := -1
	for i in sim.props.size():
		var d := HideSim._d2(sim.props[i][1] - e.x, sim.props[i][2] - e.y)
		if bd < 0 or d < bd:
			best = i
			bd = d
	return best


static func _nearest_seeker(sim: HideSim, e: HideSim.Ent) -> int:
	var best := -1
	for o in sim.ents:
		if o.role == HideSim.SEEKER:
			var d := Fx.dist(o.x - e.x, o.y - e.y)
			if best < 0 or d < best:
				best = d
	return best


## Seek: plain animals and fresh tells are clues; otherwise walk past props and now and then tap one at random.
static func _seeker(sim: HideSim, e: HideSim.Ent, cfg: Dictionary) -> Dictionary:
	var cmd := {"m": -1, "a": -1, "s": -1}
	if sim.phase != HideSim.PHASE_SEEK:
		return cmd
	var tap := int(sim.rules.tap_range)
	if sim.tick >= e.next_think:
		e.next_think = sim.tick + int(cfg.think_ticks) + sim.rng.range_i(5)
		var clue := _clue(sim, e, cfg)
		if clue != Vector2i(-1, -1):
			e.goal_x = clue.x
			e.goal_y = clue.y
			e.target = 1
		elif e.target != 0 or Fx.dist(e.goal_x - e.x, e.goal_y - e.y) < 600:
			var p: Array = sim.props[sim.rng.range_i(sim.props.size())]
			e.goal_x = p[1]
			e.goal_y = p[2]
			e.target = 0
		# close to the goal: tap it (a clue: always; a random prop: sometimes)
		var gd := Fx.dist(e.goal_x - e.x, e.goal_y - e.y)
		if gd < tap and e.dizzy == 0 and e.cooldown == 0 and (e.target == 1 or sim.rng.range_i(100) < int(cfg.guess_pct)):
			cmd.a = Fx.atan2_a(e.goal_y - e.y, e.goal_x - e.x)
			cmd["sd"] = gd
	var gx := e.goal_x - e.x
	var gy := e.goal_y - e.y
	if Fx.dist(gx, gy) > 500:
		cmd.m = Fx.atan2_a(gy, gx)
	return cmd


## The best clue within sight: a hider that is not (yet) disguised or still wobbling; a disguised one noticed as
## "that wasn't there before" (a person who knows the map can do that too; chance per think, notice_pm per mille);
## else the freshest tell.
static func _clue(sim: HideSim, e: HideSim.Ent, cfg: Dictionary) -> Vector2i:
	var sight := int(cfg.sight)
	for o in sim.ents:
		if o.role == HideSim.HIDER and Fx.dist(o.x - e.x, o.y - e.y) < sight:
			if o.disguise < 0 or o.still < int(sim.rules.still_ticks):
				return Vector2i(o.x, o.y)
			if sim.rng.range_i(1000) < int(cfg.notice_pm):
				return Vector2i(o.x, o.y)
	var best := Vector2i(-1, -1)
	var fresh := -1
	for t in sim.tells:
		var hear := int(sim.rules.tells.noise_radius) if t.kind == 2 else sight
		if t.until > fresh and Fx.dist(t.x - e.x, t.y - e.y) < hear:
			fresh = t.until
			best = Vector2i(t.x, t.y)
	return best


## A found hider becomes a gull: it just circles over the middle of the harbour.
static func _gull(sim: HideSim, e: HideSim.Ent) -> Dictionary:
	var cx := sim.width * HideSim.TILE / 2
	var cy := sim.height * HideSim.TILE / 2
	var ang := (sim.tick * 8 + e.id * 700) % Fx.ANGLES
	var tx := cx + Fx.cos_a(ang) * 6000 / Fx.ONE
	var ty := cy + Fx.sin_a(ang) * 4000 / Fx.ONE
	return {"m": Fx.atan2_a(ty - e.y, tx - e.x), "a": -1, "s": -1}
