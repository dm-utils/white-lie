class_name BallBrain
extends RefCounted
## Strandbal bots (phase 14). Same rules as BotBrain: runs inside the sim tick with the sim's RNG, memory on the
## entity (goal_x/goal_y = where it is heading, next_think), so bots are deterministic.
## Roles per team, every think: the teammate nearest the ball attacks it (gets behind it and pushes/shoots it at the
## enemy goal), the one nearest the own goal defends (stands between ball and goal, clears it), the rest supports
## (waits ahead of the ball, fights opponents near it).

const ALIGN := 520 # max angle (of 4096) between "me -> ball" and "ball -> goal" to shoot


static func think(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary) -> Dictionary:
	var cmd := {"m": -1, "a": -1, "s": -1}
	if sim.kickoff > 0:
		return cmd
	var rules := sim.rules
	var rb := int(rules.ball.radius)
	var goal := sim.goal_point(1 - e.team) # where we score
	var own := sim.goal_point(e.team)
	var to_ball := Fx.atan2_a(sim.by - e.y, sim.bx - e.x)
	var ball_d := Fx.dist(sim.bx - e.x, sim.by - e.y)
	var shoot_dir := Fx.atan2_a(goal.y - sim.by, goal.x - sim.bx)
	var aligned := absi(Fx.angle_diff(to_ball, shoot_dir)) < ALIGN
	var role := _role(sim, e)

	if sim.tick >= e.next_think:
		e.next_think = sim.tick + int(cfg.think_ticks) + sim.rng.range_i(4)
		var err := int(cfg.aim_error)
		match role:
			"attack":
				var gp := _behind(sim, e, goal, rb)
				e.goal_x = gp.x
				e.goal_y = gp.y
				if aligned and ball_d < sim.attack_range(e) * 85 / 100:
					cmd.a = posmod(to_ball + sim.rng.between(-err, err) / 2, Fx.ANGLES)
				if e.special >= int(rules.attack.special_hits):
					_special(sim, e, cmd, goal, aligned, ball_d, to_ball)
			"defend":
				# between ball and own goal, a third of the way out; clear the ball when it comes close
				e.goal_x = own.x + (sim.bx - own.x) / 3
				e.goal_y = own.y + (sim.by - own.y) / 3
				var away := absi(Fx.angle_diff(to_ball, Fx.atan2_a(sim.by - own.y, sim.bx - own.x))) < 1024
				if away and ball_d < sim.attack_range(e) * 80 / 100:
					cmd.a = posmod(to_ball + sim.rng.between(-err, err), Fx.ANGLES)
			_:
				# ahead of the ball, off to one side, ready for a pass
				var side := 3000 * (1 if e.id % 4 < 2 else -1)
				e.goal_x = sim.bx + (goal.x - sim.bx) / 3
				e.goal_y = sim.by + side
		_keep_dry(sim, e)
		if cmd.a < 0:
			_fight(sim, e, cmd, cfg)

	var gx := e.goal_x - e.x
	var gy := e.goal_y - e.y
	if Fx.dist(gx, gy) > 250:
		cmd.m = Fx.atan2_a(gy, gx)
	elif role == "attack":
		cmd.m = to_ball # behind the ball: walk into it, dribbling it towards the goal
	return cmd


## "attack", "defend" or "support" for this bot; ties go to the lower id, so every screen agrees.
static func _role(sim: MatchSim, e: MatchSim.Ent) -> String:
	var own := sim.goal_point(e.team)
	var nearest_ball := -1
	var nb := 0
	for o in sim.ents:
		if o.alive and o.team == e.team:
			var d := MatchSim._d2(sim.bx - o.x, sim.by - o.y)
			if nearest_ball < 0 or d < nb:
				nearest_ball = o.id
				nb = d
	if nearest_ball == e.id:
		return "attack"
	var nearest_goal := -1
	var ng := 0
	for o in sim.ents:
		if o.alive and o.team == e.team and o.id != nearest_ball:
			var d := MatchSim._d2(own.x - o.x, own.y - o.y)
			if nearest_goal < 0 or d < ng:
				nearest_goal = o.id
				ng = d
	return "defend" if nearest_goal == e.id else "support"


## The spot just behind the ball, seen from the goal we attack; if we stand in front of the ball, go round it.
static func _behind(sim: MatchSim, e: MatchSim.Ent, goal: Vector2i, rb: int) -> Vector2i:
	var dx := goal.x - sim.bx
	var dy := goal.y - sim.by
	var d := maxi(1, Fx.dist(dx, dy))
	var back := e.radius + rb + 250
	var p := Vector2i(sim.bx - dx * back / d, sim.by - dy * back / d)
	var ex := e.x - sim.bx
	var ey := e.y - sim.by
	if ex * dx + ey * dy > 0: # we are on the goal side of the ball: step sideways first
		var side := 1 if (ex * dy - ey * dx) > 0 else -1
		p += Vector2i(dy * side * (back + 600) / d, -dx * side * (back + 600) / d)
	return p


static func _special(sim: MatchSim, e: MatchSim.Ent, cmd: Dictionary, goal: Vector2i, aligned: bool, ball_d: int, to_ball: int) -> void:
	match str(sim.animals[e.id].special.kind):
		"dash":
			if aligned and ball_d < 3500:
				cmd.s = to_ball
		"dive":
			# land just behind the ball: the blast sends it towards the goal
			var dx := goal.x - sim.bx
			var dy := goal.y - sim.by
			var d := maxi(1, Fx.dist(dx, dy))
			var lx := sim.bx - dx * 700 / d
			var ly := sim.by - dy * 700 / d
			var reach := Fx.dist(lx - e.x, ly - e.y)
			if reach < int(sim.animals[e.id].special.range) and d < 16000:
				cmd.s = Fx.atan2_a(ly - e.y, lx - e.x)
				cmd["sd"] = reach
		"ink":
			var foe := _nearest_foe(sim, e)
			if foe != null and Fx.dist(foe.x - sim.bx, foe.y - sim.by) < 4000:
				cmd.s = Fx.atan2_a(foe.y - e.y, foe.x - e.x)


## Without a ball shot to take: sometimes hit the nearest opponent (more often when it is near the ball).
static func _fight(sim: MatchSim, e: MatchSim.Ent, cmd: Dictionary, cfg: Dictionary) -> void:
	var foe := _nearest_foe(sim, e)
	if foe == null:
		return
	var d := Fx.dist(foe.x - e.x, foe.y - e.y)
	if d > sim.attack_range(e) * 90 / 100:
		return
	if Fx.dist(foe.x - sim.bx, foe.y - sim.by) > 3500:
		return # only fight for the ball, not for its own sake
	if sim.rng.range_i(100) < int(cfg.aggression_pct) / 2:
		var err := int(cfg.aim_error)
		cmd.a = posmod(Fx.atan2_a(foe.y - e.y, foe.x - e.x) + sim.rng.between(-err, err), Fx.ANGLES)


static func _nearest_foe(sim: MatchSim, e: MatchSim.Ent) -> MatchSim.Ent:
	var best: MatchSim.Ent = null
	var bd := 0
	for o in sim.ents:
		if o.alive and o.team != e.team:
			var d := MatchSim._d2(o.x - e.x, o.y - e.y)
			if best == null or d < bd:
				best = o
				bd = d
	return best


## Never head into deep water: pull the target towards the long centre line until it is shallow or dry.
static func _keep_dry(sim: MatchSim, e: MatchSim.Ent) -> void:
	var cy := sim.field_center().y
	for i in 12:
		if sim.depth_at(e.goal_x, e.goal_y) < 2:
			return
		e.goal_y += signi(cy - e.goal_y) * 500
