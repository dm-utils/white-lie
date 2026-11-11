class_name HideSim
extends RefCounted
## The rules of White Lie (phase 2): pure, deterministic, integer-only, as the shared deterministic-sim pattern.
## Input: one command per seat per tick ({m: move angle, a: action angle, s: gadget angle, sd: distance}; -1 = none).
## Action = disguise as the nearest prop in that direction (hider) or tap the nearest thing there (seeker).
## A session is 3 rounds; every round: hide (seekers frozen in the office) -> seek -> reveal. Roles follow from the
## seat and the round, so every screen agrees without a server. Units: milli-tiles, ticks (30/s), angles 0..4095.

const TILE := 1000
const HIDER := 0
const SEEKER := 1
const GULL := 2 # a found hider: flies over the harbour, can't tap
const PHASE_HIDE := 0
const PHASE_SEEK := 1
const PHASE_REVEAL := 2
const WALLS := [0, 5] # sea, building
const ENT_FIELDS := ["id", "animal_idx", "x", "y", "role", "disguise", "still", "moved", "dizzy", "cooldown",
	"found_tick", "found_by", "points", "aim", "is_bot", "goal_x", "goal_y", "next_think", "target"]
const TELL_FIELDS := ["kind", "x", "y", "until"] # kind 0 footprint, 1 ripple, 2 noise

static var _rules: Dictionary
static var _maps: Dictionary = {}
static var _kinds: Array = [] # prop kind names, sorted (index = disguise value)
static var _kind_cfg: Dictionary = {}


class Ent:
	var id := 0
	var animal_idx := 0 # index in data/characters.json
	var x := 0
	var y := 0
	var role := HIDER
	var disguise := -1 # prop kind index, -1 = plain animal
	var still := 0 # ticks without moving
	var moved := 0 # distance moved since the last footprint/ripple
	var dizzy := 0
	var cooldown := 0
	var found_tick := -1
	var found_by := -1
	var points := 0
	var aim := 0
	var is_bot := 0
	var goal_x := 0
	var goal_y := 0
	var next_think := 0
	var target := -1 # bots: the prop (or seat + 1000) they are heading for


class Tell:
	var kind := 0
	var x := 0
	var y := 0
	var until := 0


var seed_value := 0
var tick := 0
var rng: SimRng
var rules: Dictionary
var width := 0
var height := 0
var tiles := PackedByteArray()
var props: Array = [] # [kind index, x, y] (they never move)
var ents: Array = []
var tells: Array = []
var round_no := 0
var seek_from := 0 # tick the seek phase began
var phase := PHASE_HIDE
var phase_left := 0
var finished := 0
var events: Array = []
var characters: Array = [] # character config per seat
var _map: Dictionary


static func load_config() -> void:
	if not _rules.is_empty():
		return
	_rules = Content.load_json("res://data/hide_rules.json")
	_kind_cfg = Content.load_json("res://data/props.json").kinds
	_kinds = _kind_cfg.keys()
	_kinds.sort()


static func kind_names() -> Array:
	load_config()
	return _kinds


static func kind_radius(k: int) -> int:
	return int(_kind_cfg[_kinds[k]].radius)


static func map_data(name: String) -> Dictionary:
	if not _maps.has(name):
		_maps[name] = Content.load_json("res://data/maps/%s.json" % name)
	return _maps[name]


func _init(p_seed: int, entrants: Array) -> void:
	load_config()
	rules = _rules
	seed_value = p_seed
	rng = SimRng.new(p_seed)
	_map = map_data(str(rules.map))
	width = int(_map.width)
	height = int(_map.height)
	tiles = PackedByteArray()
	for v in _map.tiles:
		tiles.append(int(v))
	for p in _map.props:
		props.append([_kinds.find(str(p.kind)), int(p.x), int(p.y)])
	var all := Content.characters()
	for i in entrants.size():
		var cfg := Content.character(str(entrants[i]))
		characters.append(cfg)
		var e := Ent.new()
		e.id = i
		e.animal_idx = all.find(cfg)
		ents.append(e)
	_start_round()


# --- queries (bots and the view use these too) ---

func tile_at(x: int, y: int) -> int:
	return tiles[clampi(y / TILE, 0, height - 1) * width + clampi(x / TILE, 0, width - 1)]


func walkable(x: int, y: int) -> bool:
	return not WALLS.has(tile_at(x, y))


func role_for(seat: int, r: int) -> int:
	return SEEKER if (seat + r) % 3 == 2 else HIDER # the player (seat 0) hides first, seeks in the last round


func hiders_left() -> int:
	var n := 0
	for e in ents:
		n += 1 if e.role == HIDER else 0
	return n


func hiders_total() -> int:
	var n := 0
	for e in ents:
		n += 1 if role_for(e.id, round_no) == HIDER else 0
	return n


## The prop a hider standing still looks like, or -1.
func looks_like(e: Ent) -> int:
	return e.disguise if e.role == HIDER and e.still >= int(rules.still_ticks) else -1


# --- the tick ---

func step(cmds: Array) -> void:
	events.clear()
	if finished:
		return
	tick += 1
	phase_left -= 1
	for e in ents:
		_update_ent(e, cmds[e.id] if e.id < cmds.size() and cmds[e.id] is Dictionary else {})
	var keep: Array = []
	for t in tells:
		if t.until > tick:
			keep.append(t)
	tells = keep
	_check_phase()


func _update_ent(e: Ent, cmd: Dictionary) -> void:
	if e.cooldown > 0:
		e.cooldown -= 1
	if e.dizzy > 0:
		e.dizzy -= 1
	var frozen := phase == PHASE_REVEAL or (phase == PHASE_HIDE and e.role == SEEKER)
	var m := -1 if frozen else int(cmd.get("m", -1))
	if m >= 0:
		var sp := int(rules.speed[["hider", "seeker", "gull"][e.role]])
		if e.role != GULL and tile_at(e.x, e.y) == 1:
			sp = sp * int(rules.water_speed_pct) / 100
		if e.dizzy > 0:
			sp = sp * int(rules.dizzy_speed_pct) / 100
		var nx := e.x + Fx.cos_a(m) * sp / Fx.ONE
		var ny := e.y + Fx.sin_a(m) * sp / Fx.ONE
		var ox := e.x
		var oy := e.y
		if e.role == GULL or walkable(nx, e.y):
			e.x = nx
		if e.role == GULL or walkable(e.x, ny):
			e.y = ny
		e.x = clampi(e.x, 500, width * TILE - 500)
		e.y = clampi(e.y, 500, height * TILE - 500)
		var d := absi(e.x - ox) + absi(e.y - oy)
		if d > 0:
			e.still = 0
			e.moved += d
			e.aim = m
			if e.role == HIDER and e.disguise >= 0:
				_tell(e)
		else:
			e.still += 1
	else:
		e.still += 1
	var a := -1 if frozen else int(cmd.get("a", -1))
	if a >= 0 and e.cooldown == 0:
		e.cooldown = int(rules.tap_cooldown_ticks)
		e.aim = posmod(a, Fx.ANGLES)
		if e.role == HIDER:
			_disguise(e, e.aim)
		elif e.role == SEEKER and phase == PHASE_SEEK and e.dizzy == 0:
			_tap(e, e.aim, int(cmd.get("sd", -1)))


## A disguised hider who moves leaves tells: footprints on sand, ripples in water, noise on the dock.
func _tell(e: Ent) -> void:
	var tl: Dictionary = rules.tells
	if e.moved < int(rules.speed.hider) * int(tl.step_every_ticks):
		return
	e.moved = 0
	var ground := tile_at(e.x, e.y)
	var t := Tell.new()
	t.x = e.x
	t.y = e.y
	match ground:
		2:
			t.kind = 0
			t.until = tick + int(tl.footprint_ticks)
		1:
			t.kind = 1
			t.until = tick + int(tl.ripple_ticks)
		3:
			t.kind = 2
			t.until = tick + int(tl.noise_ticks)
			events.append({"type": "noise", "x": e.x, "y": e.y})
		_:
			return
	tells.append(t)
	if tells.size() > int(tl.max):
		tells.remove_at(0)


func _disguise(e: Ent, ang: int) -> void:
	var px := e.x + Fx.cos_a(ang) * TILE / Fx.ONE
	var py := e.y + Fx.sin_a(ang) * TILE / Fx.ONE
	var reach := int(rules.disguise_range)
	var best := -1
	var bd := 0
	for i in props.size():
		var p: Array = props[i]
		if _d2(p[1] - e.x, p[2] - e.y) > reach * reach:
			continue
		var d := _d2(p[1] - px, p[2] - py)
		if best < 0 or d < bd:
			best = i
			bd = d
	if best < 0:
		return
	var was := e.disguise
	e.disguise = int(props[best][0])
	e.still = 0
	events.append({"type": "disguise", "id": e.id, "kind": e.disguise})
	if was >= 0 and phase == PHASE_SEEK: # changing shape while seekers look: a plop anyone near can hear
		events.append({"type": "noise", "x": e.x, "y": e.y})
		var t := Tell.new()
		t.kind = 2
		t.x = e.x
		t.y = e.y
		t.until = tick + int(rules.tells.noise_ticks)
		tells.append(t)


## Tap the thing nearest to the aimed point: a hider (found) or a real prop (miss, dizzy).
func _tap(e: Ent, ang: int, dist: int) -> void:
	var reach := int(rules.tap_range)
	var d := reach if dist < 0 else mini(dist, reach)
	var px := e.x + Fx.cos_a(ang) * d / Fx.ONE
	var py := e.y + Fx.sin_a(ang) * d / Fx.ONE
	var pick := int(rules.tap_pick)
	var hit: Ent = null
	var hd := pick * pick + 1
	for o in ents:
		if o.role == HIDER:
			var dd := _d2(o.x - px, o.y - py)
			if dd <= pick * pick and dd < hd:
				hit = o
				hd = dd
	var prop_d := pick * pick + 1
	for p in props:
		prop_d = mini(prop_d, _d2(p[1] - px, p[2] - py))
	if hit != null and hd <= prop_d:
		hit.role = GULL
		hit.found_tick = tick
		hit.found_by = e.id
		hit.disguise = -1
		e.points += int(rules.points.seeker_find)
		events.append({"type": "found", "id": hit.id, "by": e.id, "x": hit.x, "y": hit.y})
	elif prop_d <= pick * pick:
		e.dizzy = int(rules.dizzy_ticks)
		e.points = maxi(0, e.points + int(rules.points.seeker_miss))
		events.append({"type": "miss", "id": e.id, "x": px, "y": py})


func _check_phase() -> void:
	if phase == PHASE_SEEK and hiders_left() == 0:
		phase_left = 0
	if phase_left > 0:
		return
	match phase:
		PHASE_HIDE:
			phase = PHASE_SEEK
			phase_left = int(rules.seek_ticks)
			seek_from = tick
			events.append({"type": "seek"})
		PHASE_SEEK:
			_score_round()
			phase = PHASE_REVEAL
			phase_left = int(rules.reveal_ticks)
			events.append({"type": "reveal", "round": round_no})
		PHASE_REVEAL:
			if round_no + 1 >= int(rules.rounds):
				_finish()
			else:
				round_no += 1
				_start_round()


func _score_round() -> void:
	var pts: Dictionary = rules.points
	var seek_start := seek_from
	var left := hiders_left()
	var last_found := -1
	for e in ents:
		if role_for(e.id, round_no) != HIDER:
			continue
		var until: int = e.found_tick if e.found_tick >= 0 else tick
		e.points += maxi(0, until - seek_start) / int(pts.hider_per_ticks)
		if e.found_tick < 0:
			e.points += int(pts.never_found)
			if left == 1:
				e.points += int(pts.last_survivor)
		elif last_found < 0 or e.found_tick > ents[last_found].found_tick:
			last_found = e.id
	if left == 0:
		if last_found >= 0:
			ents[last_found].points += int(pts.last_survivor) # held out the longest
		for e in ents:
			if e.role == SEEKER:
				e.points += int(pts.all_found)


func _start_round() -> void:
	phase = PHASE_HIDE
	phase_left = int(rules.hide_ticks)
	tells = []
	var hs: Array = _map.hider_spawns
	var ss: Array = _map.seeker_spawns
	var hi := 0
	var si := 0
	for e in ents:
		e.role = role_for(e.id, round_no)
		e.disguise = -1
		e.still = 0
		e.moved = 0
		e.dizzy = 0
		e.found_tick = -1
		e.found_by = -1
		e.target = -1
		var sp: Array
		if e.role == SEEKER:
			sp = ss[si % ss.size()]
			si += 1
		else:
			sp = hs[hi % hs.size()]
			hi += 1
		e.x = int(sp[0]) * TILE + TILE / 2 + rng.between(-300, 300)
		e.y = int(sp[1]) * TILE + TILE / 2 + rng.between(-300, 300)
		e.goal_x = e.x
		e.goal_y = e.y
	events.append({"type": "round", "round": round_no})


func _finish() -> void:
	finished = 1
	events.append({"type": "finished"})


## Places by points (ties: lower seat first): [{id, animal, points, place}].
func result() -> Array:
	var order: Array = ents.duplicate()
	order.sort_custom(func(a, b): return a.points > b.points or (a.points == b.points and a.id < b.id))
	var out: Array = []
	for e in ents:
		out.append({"id": e.id, "character": str(characters[e.id].get("id", "")), "points": e.points, "place": order.find(e) + 1})
	return out


static func _d2(dx: int, dy: int) -> int:
	return dx * dx + dy * dy


# --- determinism ---

func state_hash() -> int:
	var h := 2166136261
	for v in [tick, rng.state, round_no, phase, phase_left, seek_from, finished, ents.size(), tells.size()]:
		h = _mix(h, v)
	for e in ents:
		for f in ENT_FIELDS:
			h = _mix(h, int(e.get(f)))
	for t in tells:
		for f in TELL_FIELDS:
			h = _mix(h, int(t.get(f)))
	return h


## FNV-1a step over 4 bytes of v.
static func _mix(h: int, v: int) -> int:
	var u := v & 0xFFFFFFFF
	for i in 4:
		h ^= (u >> (i * 8)) & 0xFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


func snapshot() -> Dictionary:
	var out := {"tick": tick, "rng": rng.state, "round": round_no, "phase": phase, "phase_left": phase_left, "seek_from": seek_from, "finished": finished,
		"ents": [], "tells": []}
	for e in ents:
		var d := {}
		for f in ENT_FIELDS:
			d[f] = e.get(f)
		out.ents.append(d)
	for t in tells:
		var d := {}
		for f in TELL_FIELDS:
			d[f] = t.get(f)
		out.tells.append(d)
	return out


func restore(s: Dictionary) -> void:
	tick = int(s.tick)
	rng.state = int(s.rng)
	round_no = int(s.round)
	phase = int(s.phase)
	phase_left = int(s.phase_left)
	seek_from = int(s.seek_from)
	finished = int(s.finished)
	for i in ents.size():
		for f in ENT_FIELDS:
			ents[i].set(f, int(s.ents[i][f]))
	tells = []
	for d in s.tells:
		var t := Tell.new()
		for f in TELL_FIELDS:
			t.set(f, int(d[f]))
		tells.append(t)
