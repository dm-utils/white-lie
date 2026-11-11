class_name MatchSim
extends RefCounted
## The rules of one match: pure, deterministic, integer-only. No nodes, no clock, no global random.
## Input: one command per entrant per tick ({m: move angle, a: attack angle, s: special angle, sd: special
## distance}; -1 or missing = none). Output: state, events (for view/audio/HUD), a state hash and the result.
## Units: milli-tiles, ticks (30/s), hp x100, angles 0..4095. All tunables come from res://data.
## This file is the specification for the C++ port (phase 7): keep it plain and portable.

const TILE := 1000
const ENT_FIELDS := ["id", "animal_idx", "x", "y", "hp", "max_hp", "radius", "speed", "alive", "charges", "reload",
	"cooldown", "special", "slow", "slow_pct", "dash", "dash_dx", "dash_dy", "calm", "last_hit_by", "last_hit_tick",
	"kos", "place", "died_tick", "aim", "damage_pct", "is_bot", "goal_x", "goal_y", "next_think", "strafe"]
const PROJ_FIELDS := ["owner", "x", "y", "dx", "dy", "life", "damage", "radius"]
const CLOUD_FIELDS := ["owner", "x", "y", "radius", "life", "slow"]
const DIVE_FIELDS := ["owner", "x", "y", "delay", "radius", "damage"]
## Strandbal (phase 14): extra state, hashed and saved only in that mode so normal matches keep their golden traces.
const BALL_ENT_FIELDS := ["team", "respawn", "goals"]
const BALL_FIELDS := ["bx", "by", "bvx", "bvy", "btouch", "bprev", "score_0", "score_1", "kickoff", "golden", "end_tick"]
const BALL_MARK := 1000 # in Ent.dash_hit: this dash already shot the ball

static var _rules: Dictionary
static var _animals: Array = []
static var _islands: Dictionary = {}
static var _modes: Dictionary = {}


class Ent:
	var id := 0
	var animal_idx := 0
	var x := 0
	var y := 0
	var hp := 0
	var max_hp := 0
	var radius := 0
	var speed := 0
	var alive := 1
	var charges := 0
	var reload := 0
	var cooldown := 0
	var special := 0
	var slow := 0
	var slow_pct := 100
	var dash := 0
	var dash_dx := 0
	var dash_dy := 0
	var calm := 0
	var last_hit_by := -1
	var last_hit_tick := -100000
	var kos := 0
	var place := 0
	var died_tick := -1
	var aim := 0
	var damage_pct := 100
	var is_bot := 0
	var goal_x := 0
	var goal_y := 0
	var next_think := 0
	var strafe := 1
	var team := -1 # Strandbal: 0 blue (defends the left goal), 1 orange; -1 every animal for itself
	var respawn := 0 # Strandbal: ticks until a washed-away animal is back
	var goals := 0
	var dash_hit: Array = [] # ids hit during the current dash (cleared when a dash starts)


class Proj:
	var owner := 0
	var x := 0
	var y := 0
	var dx := 0
	var dy := 0
	var life := 0
	var damage := 0
	var radius := 0


class Cloud:
	var owner := 0
	var x := 0
	var y := 0
	var radius := 0
	var life := 0
	var slow := 100


class Dive:
	var owner := 0
	var x := 0
	var y := 0
	var delay := 0
	var radius := 0
	var damage := 0


var seed_value := 0
var tick := 0
var rng: SimRng
var width := 0
var height := 0
var heights := PackedByteArray()
var level := 0
var phase_left := 0
var sudden := 0
var snack_timer := 0
var finished := 0
var ents: Array = []
var projs: Array = []
var snacks: Array = [] # [x, y] pairs
var clouds: Array = []
var dives: Array = []
var events: Array = [] # cleared every tick: {type, ...}

var rules: Dictionary
var animals: Array # animal config per entrant (same order as ents)

# Strandbal (mode "ball"): the ball, the score and the clock; field and mouth in milli-tiles
var mode := ""
var field: Array[int] = [] # [x0, y0, x1, y1]
var mouth: Array[int] = [] # [y0, y1]
var bx := 0
var by := 0
var bvx := 0
var bvy := 0
var btouch := -1 # last animal to touch the ball (scorer)
var bprev := -1
var score_0 := 0
var score_1 := 0
var kickoff := 0 # ticks of the kickoff pause left (nobody moves)
var golden := 0 # 1 = golden goal: next goal wins
var end_tick := 0


static func load_config() -> void:
	if not _rules.is_empty():
		return
	_rules = Content.load_json("res://data/rules.json")
	_animals = Content.animals()


static func animal_config(id: String) -> Dictionary:
	load_config()
	for a in _animals:
		if a.id == id:
			return a
	return {}


## The rules for a mode: rules.json with data/modes/<mode>.json "rules" merged over it ("" = the normal match).
static func rules_for(p_mode: String) -> Dictionary:
	load_config()
	if p_mode == "":
		return _rules
	if not _modes.has(p_mode):
		var over: Dictionary = Content.load_json("res://data/modes/%s.json" % p_mode).rules
		_modes[p_mode] = _merged(_rules, over)
	return _modes[p_mode]


static func _merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.get(k) is Dictionary and over[k] is Dictionary:
			out[k] = _merged(out[k], over[k])
		else:
			out[k] = over[k]
	return out


static func island_data(name: String) -> Dictionary:
	if not _islands.has(name):
		_islands[name] = Content.load_json("res://data/islands/%s.json" % name)
	return _islands[name]


## entrants: animal ids, one per player; index = entity id.
func _init(p_seed: int, entrants: Array, p_mode := "") -> void:
	load_config()
	mode = p_mode
	rules = rules_for(p_mode)
	seed_value = p_seed
	rng = SimRng.new(p_seed)
	var isl := island_data(str(rules.island))
	width = int(isl.width)
	height = int(isl.height)
	heights = PackedByteArray()
	for h in isl.heights:
		heights.append(int(h))
	level = int(rules.tide.start_level)
	phase_left = int(rules.tide.phase_ticks)
	snack_timer = int(rules.snacks.respawn_ticks)

	# spawn order shuffled by the seed (Fisher-Yates); Strandbal: fixed team spawns instead
	var spawns: Array = isl.spawns.duplicate()
	for i in range(spawns.size() - 1, 0, -1):
		if mode == "ball":
			break
		var j := rng.range_i(i + 1)
		var t = spawns[i]
		spawns[i] = spawns[j]
		spawns[j] = t

	animals = []
	for i in entrants.size():
		var cfg := animal_config(str(entrants[i]))
		animals.append(cfg)
		var e := Ent.new()
		e.id = i
		e.animal_idx = _animals.find(cfg)
		var sp: Array = spawns[i % spawns.size()]
		if mode == "ball":
			e.team = i % 2
			sp = isl.team_spawns[e.team][(i / 2) % 3]
		e.x = int(sp[0]) * TILE + TILE / 2
		e.y = int(sp[1]) * TILE + TILE / 2
		e.hp = int(cfg.hp)
		e.max_hp = e.hp
		e.radius = int(cfg.radius)
		e.speed = int(cfg.speed)
		e.charges = int(rules.attack.charges)
		e.goal_x = e.x
		e.goal_y = e.y
		ents.append(e)

	var spots: Array = isl.snack_spots.duplicate()
	for n in int(rules.snacks.start):
		if spots.is_empty():
			break
		var k := rng.range_i(spots.size())
		var s: Array = spots[k]
		spots.remove_at(k)
		snacks.append([int(s[0]) * TILE + TILE / 2, int(s[1]) * TILE + TILE / 2])

	if mode == "ball":
		var f: Array = isl.field
		field = [int(f[0]) * TILE, int(f[1]) * TILE, int(f[2]) * TILE, int(f[3]) * TILE]
		mouth = [int(isl.goal[0]) * TILE, int(isl.goal[1]) * TILE]
		_kickoff()


# --- queries (also used by bots and the view) ---

func height_at(x: int, y: int) -> int:
	var tx := clampi(x / TILE, 0, width - 1)
	var ty := clampi(y / TILE, 0, height - 1)
	return heights[ty * width + tx]


## <= 0 dry, 1 shallow, >= 2 deep
func depth_at(x: int, y: int) -> int:
	return level - height_at(x, y)


func ground(x: int, y: int) -> String:
	var d := depth_at(x, y)
	return "dry" if d <= 0 else ("shallow" if d == 1 else "deep")


func type_of(e: Ent) -> String:
	return str(animals[e.id].type)


func alive_count() -> int:
	var n := 0
	for e in ents:
		n += e.alive
	return n


func attack_range(e: Ent) -> int:
	var at: Dictionary = animals[e.id].attack
	return int(at.speed) * int(at.life)


# --- the tick ---

func step(cmds: Array) -> void:
	events.clear()
	if finished:
		return
	tick += 1
	_tide()
	_snack_respawn()
	var frozen := false
	if kickoff > 0: # Strandbal: after a goal everyone waits on their own half
		kickoff -= 1
		frozen = true
	for e in ents:
		if e.alive:
			_update_ent(e, {} if frozen else (cmds[e.id] if e.id < cmds.size() and cmds[e.id] is Dictionary else {}))
		elif mode == "ball":
			_respawn_tick(e)
	_update_projs()
	_update_clouds()
	_update_dives()
	if mode == "ball":
		_update_ball()
	_resolve_deaths()
	_check_end()


func _tide() -> void:
	phase_left -= 1
	if phase_left == int(rules.tide.warn_ticks) and level < int(rules.tide.max_level):
		events.append({"type": "tide_warning"})
	if phase_left > 0:
		return
	phase_left = int(rules.tide.phase_ticks)
	if level < int(rules.tide.max_level):
		level += 1
		events.append({"type": "tide_rise", "level": level})
		var keep: Array = []
		for s in snacks:
			if depth_at(s[0], s[1]) <= 0:
				keep.append(s)
		snacks = keep
	else:
		sudden += 1
		events.append({"type": "sudden_death", "level": sudden})


func _snack_respawn() -> void:
	snack_timer -= 1
	if snack_timer > 0:
		return
	snack_timer = int(rules.snacks.respawn_ticks)
	if snacks.size() >= int(rules.snacks.max):
		return
	var spots: Array = island_data(str(rules.island)).snack_spots
	var dry: Array = []
	for s in spots:
		var x := int(s[0]) * TILE + TILE / 2
		var y := int(s[1]) * TILE + TILE / 2
		if depth_at(x, y) <= -1: # only on properly dry land: pulls players inland
			dry.append([x, y])
	if not dry.is_empty():
		snacks.append(dry[rng.range_i(dry.size())])


func _update_ent(e: Ent, cmd: Dictionary) -> void:
	var at: Dictionary = rules.attack
	if e.cooldown > 0:
		e.cooldown -= 1
	if e.slow > 0:
		e.slow -= 1
	e.calm += 1
	if e.charges < int(at.charges):
		e.reload += 1
		if e.reload >= int(at.reload_ticks):
			e.charges += 1
			e.reload = 0

	var t := type_of(e)
	# movement
	if e.dash > 0:
		e.dash -= 1
		e.x += e.dash_dx
		e.y += e.dash_dy
		var sp: Dictionary = animals[e.id].special
		if mode == "ball" and not e.dash_hit.has(BALL_MARK) and _touch_ball(e.x, e.y, e.radius):
			e.dash_hit.append(BALL_MARK)
			_kick(e.id, e.dash_dx, e.dash_dy, int(rules.ball.shot.dash))
		for o in ents:
			if o.alive and _foe(e, o) and not e.dash_hit.has(o.id) and _touch(e.x, e.y, o, e.radius):
				e.dash_hit.append(o.id)
				_damage(o, int(sp.damage) * e.damage_pct / 100, e.id)
				var speed := int(sp.speed)
				o.x += e.dash_dx * int(sp.push) / speed
				o.y += e.dash_dy * int(sp.push) / speed
				_clamp(o)
	else:
		var m := int(cmd.get("m", -1))
		if m >= 0:
			var pct: int = int(rules.ground_speed_pct[t][ground(e.x, e.y)])
			var sp := e.speed * pct / 100
			if e.slow > 0:
				sp = sp * e.slow_pct / 100
			e.x += Fx.cos_a(m) * sp / Fx.ONE
			e.y += Fx.sin_a(m) * sp / Fx.ONE
	_clamp(e)
	if mode == "ball":
		_dribble(e, int(cmd.get("m", -1)) if e.dash == 0 else -1)

	# water and recovery
	var depth := depth_at(e.x, e.y)
	if depth >= 2:
		var dmg := int(rules.deep_damage_per_tick[t]) * (100 + sudden * int(rules.tide.sudden_death_extra_pct)) / 100
		_damage(e, dmg, -1)
	elif e.calm >= int(rules.regen.calm_ticks) and e.hp < e.max_hp:
		e.hp = mini(e.max_hp, e.hp + int(rules.regen.per_tick))

	# snacks
	var reach := int(rules.snacks.radius) + e.radius
	for i in range(snacks.size() - 1, -1, -1):
		var s: Array = snacks[i]
		if e.hp < e.max_hp and _d2(e.x - s[0], e.y - s[1]) <= reach * reach:
			e.hp = mini(e.max_hp, e.hp + int(rules.snacks.heal))
			snacks.remove_at(i)
			events.append({"type": "snack", "id": e.id, "x": s[0], "y": s[1]})

	# attack
	var a := int(cmd.get("a", -1))
	if a >= 0 and e.charges > 0 and e.cooldown == 0:
		e.charges -= 1
		e.cooldown = int(at.cooldown_ticks)
		e.calm = 0
		e.aim = posmod(a, Fx.ANGLES)
		var cfg: Dictionary = animals[e.id].attack
		var count := int(cfg.count)
		for i in count:
			var ang := e.aim + (i - (count - 1) / 2) * int(cfg.spread)
			var p := Proj.new()
			p.owner = e.id
			p.x = e.x + Fx.cos_a(ang) * e.radius / Fx.ONE
			p.y = e.y + Fx.sin_a(ang) * e.radius / Fx.ONE
			p.dx = Fx.cos_a(ang) * int(cfg.speed) / Fx.ONE
			p.dy = Fx.sin_a(ang) * int(cfg.speed) / Fx.ONE
			p.life = int(cfg.life)
			p.damage = int(cfg.damage) * e.damage_pct / 100
			p.radius = int(cfg.radius)
			projs.append(p)
		events.append({"type": "attack", "id": e.id, "angle": e.aim})

	# special
	var s_ang := int(cmd.get("s", -1))
	if s_ang >= 0 and e.special >= int(at.special_hits):
		e.special = 0
		e.calm = 0
		e.aim = posmod(s_ang, Fx.ANGLES)
		var sp: Dictionary = animals[e.id].special
		match str(sp.kind):
			"dash":
				e.dash = int(sp.ticks)
				e.dash_dx = Fx.cos_a(e.aim) * int(sp.speed) / Fx.ONE
				e.dash_dy = Fx.sin_a(e.aim) * int(sp.speed) / Fx.ONE
				e.dash_hit = []
			"ink":
				var c := Cloud.new()
				c.owner = e.id
				c.x = e.x + Fx.cos_a(e.aim) * int(sp.offset) / Fx.ONE
				c.y = e.y + Fx.sin_a(e.aim) * int(sp.offset) / Fx.ONE
				c.radius = int(sp.radius)
				c.life = int(sp.ticks)
				c.slow = int(sp.slow)
				clouds.append(c)
			"dive":
				var d := int(cmd.get("sd", -1))
				d = int(sp.range) if d < 0 else mini(d, int(sp.range))
				var v := Dive.new()
				v.owner = e.id
				v.x = clampi(e.x + Fx.cos_a(e.aim) * d / Fx.ONE, 0, width * TILE - 1)
				v.y = clampi(e.y + Fx.sin_a(e.aim) * d / Fx.ONE, 0, height * TILE - 1)
				v.delay = int(sp.delay)
				v.radius = int(sp.radius)
				v.damage = int(sp.damage) * e.damage_pct / 100
				dives.append(v)
		events.append({"type": "special", "id": e.id, "kind": str(sp.kind), "angle": e.aim})


func _update_projs() -> void:
	var keep: Array = []
	var hits := int(rules.attack.special_hits)
	for p in projs:
		p.x += p.dx
		p.y += p.dy
		p.life -= 1
		var hit := false
		for e in ents:
			if e.alive and e.id != p.owner and _foe(ents[p.owner], e) and _touch(p.x, p.y, e, p.radius):
				_damage(e, p.damage, p.owner)
				var o: Ent = ents[p.owner]
				o.special = mini(hits, o.special + 1)
				events.append({"type": "hit", "id": e.id, "by": p.owner, "x": p.x, "y": p.y})
				hit = true
				break
		if not hit and mode == "ball" and _touch_ball(p.x, p.y, p.radius):
			_kick(p.owner, p.dx, p.dy, int(rules.ball.shot[str(animals[p.owner].attack.kind)]))
			hit = true
		if not hit and p.life > 0:
			keep.append(p)
	projs = keep


func _update_clouds() -> void:
	var keep: Array = []
	for c in clouds:
		c.life -= 1
		for e in ents:
			if e.alive and e.id != c.owner and _foe(ents[c.owner], e) and _touch(c.x, c.y, e, c.radius):
				e.slow = 2
				e.slow_pct = c.slow
		if c.life > 0:
			keep.append(c)
	clouds = keep


func _update_dives() -> void:
	var keep: Array = []
	for v in dives:
		v.delay -= 1
		if v.delay > 0:
			keep.append(v)
			continue
		for e in ents:
			if e.alive and e.id != v.owner and _foe(ents[v.owner], e) and _touch(v.x, v.y, e, v.radius):
				_damage(e, v.damage, v.owner)
		if mode == "ball" and _touch_ball(v.x, v.y, v.radius):
			var dx: int = bx - v.x
			var dy: int = by - v.y
			if dx == 0 and dy == 0:
				dx = 1 if ents[v.owner].team == 0 else -1
			_kick(v.owner, dx, dy, int(rules.ball.shot.dive))
		events.append({"type": "dive", "id": v.owner, "x": v.x, "y": v.y})
	dives = keep


func _damage(e: Ent, amount: int, by: int) -> void:
	if not e.alive or amount <= 0:
		return
	if mode == "ball" and by >= 0: # Strandbal: hits slow you down more than they wash you away
		amount = amount * int(rules.ball.damage_pct) / 100
	e.hp -= amount
	if by >= 0:
		e.last_hit_by = by
		e.last_hit_tick = tick
		e.calm = 0


func _resolve_deaths() -> void:
	if mode == "ball":
		for e in ents:
			if e.alive and e.hp <= 0:
				e.alive = 0
				e.hp = 0
				e.respawn = int(rules.ball.respawn_ticks)
				e.died_tick = tick
				e.dash = 0
				if e.last_hit_by >= 0 and tick - e.last_hit_tick <= int(rules.knockout_credit_ticks):
					ents[e.last_hit_by].kos += 1
				events.append({"type": "ko", "id": e.id, "x": e.x, "y": e.y, "by": e.last_hit_by})
		return
	var remaining := alive_count()
	for e in ents:
		if e.alive and e.hp <= 0:
			e.alive = 0
			e.hp = 0
			e.place = remaining
			remaining -= 1
			e.died_tick = tick
			if e.last_hit_by >= 0 and tick - e.last_hit_tick <= int(rules.knockout_credit_ticks):
				ents[e.last_hit_by].kos += 1
			events.append({"type": "ko", "id": e.id, "x": e.x, "y": e.y, "by": e.last_hit_by})


func _check_end() -> void:
	if mode == "ball":
		_check_end_ball()
		return
	var alive: Array = []
	for e in ents:
		if e.alive:
			alive.append(e)
	# hard cap: 6 minutes; remaining players ranked by health, then id
	if alive.size() > 1 and tick >= 30 * 60 * 6:
		alive.sort_custom(func(a, b): return a.hp > b.hp or (a.hp == b.hp and a.id < b.id))
		for i in alive.size():
			alive[i].place = i + 1
		finished = 1
	elif alive.size() <= 1:
		if alive.size() == 1:
			alive[0].place = 1
		finished = 1
	if finished:
		events.append({"type": "finished"})


# --- helpers ---

func _touch(x: int, y: int, e: Ent, r: int) -> bool:
	var rr := r + e.radius
	return _d2(x - e.x, y - e.y) <= rr * rr


static func _d2(dx: int, dy: int) -> int:
	return dx * dx + dy * dy


func _clamp(e: Ent) -> void:
	e.x = clampi(e.x, e.radius, width * TILE - e.radius)
	e.y = clampi(e.y, e.radius, height * TILE - e.radius)


# --- determinism: hash, snapshot, result ---

## FNV-1a over every piece of state that can affect the future.
func state_hash() -> int:
	var h := 2166136261
	for v in [tick, level, phase_left, sudden, snack_timer, finished, rng.state, ents.size(), projs.size(), snacks.size(), clouds.size(), dives.size()]:
		h = _mix(h, v)
	for e in ents:
		for f in ENT_FIELDS:
			h = _mix(h, int(e.get(f)))
		for id in e.dash_hit:
			h = _mix(h, id)
	for p in projs:
		for f in PROJ_FIELDS:
			h = _mix(h, int(p.get(f)))
	for s in snacks:
		h = _mix(_mix(h, s[0]), s[1])
	for c in clouds:
		for f in CLOUD_FIELDS:
			h = _mix(h, int(c.get(f)))
	for v in dives:
		for f in DIVE_FIELDS:
			h = _mix(h, int(v.get(f)))
	if mode == "ball":
		for f in BALL_FIELDS:
			h = _mix(h, int(get(f)))
		for e in ents:
			for f in BALL_ENT_FIELDS:
				h = _mix(h, int(e.get(f)))
	return h


static func _mix(h: int, v: int) -> int:
	var u := v & 0xFFFFFFFF
	for i in 4:
		h ^= (u >> (i * 8)) & 0xFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


func snapshot() -> Dictionary:
	var out := {"seed": seed_value, "tick": tick, "rng": rng.state, "level": level, "phase_left": phase_left, "sudden": sudden,
		"snack_timer": snack_timer, "finished": finished, "snacks": snacks.duplicate(true), "ents": [], "projs": [], "clouds": [], "dives": []}
	for e in ents:
		var d := {}
		for f in ENT_FIELDS:
			d[f] = e.get(f)
		d["dash_hit"] = e.dash_hit.duplicate()
		if mode == "ball":
			for f in BALL_ENT_FIELDS:
				d[f] = e.get(f)
		out.ents.append(d)
	for pair in [["projs", projs, PROJ_FIELDS], ["clouds", clouds, CLOUD_FIELDS], ["dives", dives, DIVE_FIELDS]]:
		for o in pair[1]:
			var d := {}
			for f in pair[2]:
				d[f] = o.get(f)
			out[pair[0]].append(d)
	if mode == "ball":
		for f in BALL_FIELDS:
			out[f] = get(f)
	return out


func restore(s: Dictionary) -> void:
	tick = int(s.tick)
	rng.state = int(s.rng)
	level = int(s.level)
	phase_left = int(s.phase_left)
	sudden = int(s.sudden)
	snack_timer = int(s.snack_timer)
	finished = int(s.finished)
	snacks = []
	for p in s.snacks:
		snacks.append([int(p[0]), int(p[1])])
	for i in ents.size():
		var d: Dictionary = s.ents[i]
		for f in ENT_FIELDS:
			ents[i].set(f, int(d[f]))
		ents[i].dash_hit = []
		for id in d.dash_hit:
			ents[i].dash_hit.append(int(id))
		if mode == "ball":
			for f in BALL_ENT_FIELDS:
				ents[i].set(f, int(d[f]))
	if mode == "ball":
		for f in BALL_FIELDS:
			set(f, int(s[f]))
	projs = _restore_list(s.projs, Proj, PROJ_FIELDS)
	clouds = _restore_list(s.clouds, Cloud, CLOUD_FIELDS)
	dives = _restore_list(s.dives, Dive, DIVE_FIELDS)


static func _restore_list(src: Array, cls, fields: Array) -> Array:
	var out: Array = []
	for d in src:
		var o = cls.new()
		for f in fields:
			o.set(f, int(d[f]))
		out.append(o)
	return out


## Places, knockouts and survival per entrant (valid once finished, or for those already out).
func result() -> Array:
	var out: Array = []
	for e in ents:
		var row := {"id": e.id, "animal": str(animals[e.id].id), "place": e.place, "kos": e.kos,
			"survived_ticks": (e.died_tick if e.died_tick >= 0 else tick)}
		if mode == "ball":
			row["team"] = e.team
			row["goals"] = e.goals
		out.append(row)
	return out


# --- Strandbal (phase 14) ---

## Teams protect their own; without teams (normal match) everyone is a foe.
func _foe(a: Ent, b: Ent) -> bool:
	return a.id != b.id and (a.team < 0 or a.team != b.team)


func _touch_ball(x: int, y: int, r: int) -> bool:
	var rr := r + int(rules.ball.radius)
	return _d2(x - bx, y - by) <= rr * rr


## The point in the middle of the goal that `team` defends (team 0 the left one).
func goal_point(team: int) -> Vector2i:
	return Vector2i(field[0] if team == 0 else field[2], (mouth[0] + mouth[1]) / 2)


func field_center() -> Vector2i:
	return Vector2i((field[0] + field[2]) / 2, (field[1] + field[3]) / 2)


## A shot: the ball keeps a quarter of its speed and gets `speed` along (dx, dy).
func _kick(id: int, dx: int, dy: int, speed: int) -> void:
	var d := maxi(1, Fx.dist(dx, dy))
	bvx = bvx / 4 + dx * speed / d
	bvy = bvy / 4 + dy * speed / d
	_cap_ball()
	_touched(id)
	events.append({"type": "kick", "id": id, "x": bx, "y": by, "power": speed})


func _touched(id: int) -> void:
	if id != btouch:
		bprev = btouch
		btouch = id


func _cap_ball() -> void:
	var top := int(rules.ball.max_speed)
	var v := Fx.dist(bvx, bvy)
	if v > top:
		bvx = bvx * top / v
		bvy = bvy * top / v


## Walking into the ball pushes it ahead (dribbling); a ball rolling into an animal bounces off it.
func _dribble(e: Ent, move: int) -> void:
	var b: Dictionary = rules.ball
	var rr := e.radius + int(b.radius)
	var dx := bx - e.x
	var dy := by - e.y
	if _d2(dx, dy) > rr * rr:
		return
	var d := Fx.dist(dx, dy)
	if d == 0:
		dx = 1 if e.team == 0 else -1
		dy = 0
		d = 1
	var nx := dx * Fx.ONE / d
	var ny := dy * Fx.ONE / d
	bx = e.x + nx * rr / Fx.ONE
	by = e.y + ny * rr / Fx.ONE
	var vn := (bvx * nx + bvy * ny) / Fx.ONE
	var want := e.speed * int(b.dribble_pct) / 100 if move >= 0 else 0
	var target := maxi(want, -vn * int(b.bounce_pct) / 100)
	if vn < target:
		bvx += (target - vn) * nx / Fx.ONE
		bvy += (target - vn) * ny / Fx.ONE
		_cap_ball()
	_touched(e.id)


func _update_ball() -> void:
	if kickoff > 0:
		return
	var b: Dictionary = rules.ball
	var r := int(b.radius)
	var bounce := int(b.bounce_pct)
	bx += bvx
	by += bvy
	var in_mouth: bool = by >= mouth[0] and by < mouth[1]
	if in_mouth and bx < field[0]:
		_goal(1)
		return
	if in_mouth and bx >= field[2]:
		_goal(0)
		return
	if not in_mouth:
		if bx - r < field[0]:
			bx = field[0] + r
			bvx = -bvx * bounce / 100
			events.append({"type": "bounce", "x": bx, "y": by})
		elif bx + r > field[2]:
			bx = field[2] - r
			bvx = -bvx * bounce / 100
			events.append({"type": "bounce", "x": bx, "y": by})
	if by - r < field[1]:
		by = field[1] + r
		bvy = -bvy * bounce / 100
		events.append({"type": "bounce", "x": bx, "y": by})
	elif by + r > field[3]:
		by = field[3] - r
		bvy = -bvy * bounce / 100
		events.append({"type": "bounce", "x": bx, "y": by})
	var g := ground(bx, by)
	var f := int(b.friction[g])
	bvx = bvx * f / 1000
	bvy = bvy * f / 1000
	if g == "deep": # deep water carries the ball slowly back to the middle of the field
		var cy: int = (field[1] + field[3]) / 2
		bvy += int(b.deep_drift) * signi(cy - by)
	if absi(bvx) < 3 and absi(bvy) < 3:
		bvx = 0
		bvy = 0


func _goal(team: int) -> void:
	if team == 0:
		score_0 += 1
	else:
		score_1 += 1
	var by_id := btouch if btouch >= 0 and ents[btouch].team == team else -1 # an own goal credits nobody
	if by_id >= 0:
		ents[by_id].goals += 1
	events.append({"type": "goal", "team": team, "by": by_id, "x": bx, "y": by, "score": [score_0, score_1]})
	_kickoff()


## Everyone back to their own half, the ball in the middle, a short pause.
func _kickoff() -> void:
	var c := field_center()
	bx = c.x
	by = c.y
	bvx = 0
	bvy = 0
	btouch = -1
	bprev = -1
	projs = []
	clouds = []
	dives = []
	var isl := island_data(str(rules.island))
	for e in ents:
		if e.alive:
			var sp: Array = isl.team_spawns[e.team][(e.id / 2) % 3]
			e.x = int(sp[0]) * TILE + TILE / 2
			e.y = int(sp[1]) * TILE + TILE / 2
			e.dash = 0
	kickoff = int(rules.ball.kickoff_ticks)
	events.append({"type": "kickoff"})


func _respawn_tick(e: Ent) -> void:
	if e.respawn <= 0:
		return
	e.respawn -= 1
	if e.respawn > 0:
		return
	var sp: Array = island_data(str(rules.island)).team_spawns[e.team][(e.id / 2) % 3]
	e.alive = 1
	e.hp = e.max_hp
	e.x = int(sp[0]) * TILE + TILE / 2
	e.y = int(sp[1]) * TILE + TILE / 2
	e.charges = int(rules.attack.charges)
	e.slow = 0
	e.dash = 0
	e.calm = 0
	events.append({"type": "respawn", "id": e.id, "x": e.x, "y": e.y})


func _check_end_ball() -> void:
	var b: Dictionary = rules.ball
	var win := int(b.goals_to_win)
	var done := score_0 >= win or score_1 >= win
	if not done and golden == 0 and tick >= int(b.match_ticks):
		if score_0 == score_1:
			golden = 1
			end_tick = tick + int(b.golden_ticks)
			level = int(rules.tide.max_level)
			phase_left = int(rules.tide.phase_ticks)
			events.append({"type": "golden"})
		else:
			done = true
	elif not done and golden == 1 and (score_0 != score_1 or tick >= end_tick):
		done = true
	if not done:
		return
	for e in ents: # 1 won, 2 draw, 3 lost
		var mine := score_0 if e.team == 0 else score_1
		var theirs := score_1 if e.team == 0 else score_0
		e.place = 1 if mine > theirs else (2 if mine == theirs else 3)
	finished = 1
	events.append({"type": "finished"})


## Seconds left on the clock (golden goal: seconds of golden time left).
func ball_seconds_left() -> int:
	var until := end_tick if golden == 1 else int(rules.ball.match_ticks)
	return maxi(0, until - tick) / 30
