extends Node2D
## The match on screen. Reads the sim, never changes it: input becomes a command per tick, the sim steps at a
## fixed 30 Hz, and the view interpolates between ticks. Events (hits, KOs, tide) drive effects and messages.
## Debug entry: --scene=match --seed=N [--animal=gull] [--bots=easy|normal|hard];
## debug builds also take [--tide=<seconds per phase>] [--god=1] (smoke test). Any build: [--controls=touch]
## [--safe=l,t,r,b] to see the phone layout on a PC. [--mode=ball] plays Strandbal (phase 14).

const PX := 0.08 # screen pixels per milli-tile: 80 px per tile, ~24 x 13 tiles visible at 1920 x 1080
const DT := 1.0 / 30.0
const MAX_STEPS_PER_FRAME := 3
const RESULT_SCENE := "res://ui/result_screen.tscn"
const ANIMAL_PX := 96.0 # on-screen size of an animal (styleguide: recognisable silhouette)

var m: Match
var _plan: Dictionary = {} # from the menu (daily challenge), empty for a normal match
var rb: Rollback # online: the rollback driving the match
var net: OnlineClient # online: the room connection
var _online_started := false
var _next_hash := Rollback.HASH_EVERY - 1
var island: IslandView # ground and water, one shader (z -1)
var board: Node2D # snacks, ink, dive markers, ripples, shadows and rings (z 0)
var actors: Node2D # cutout animals, sorted by y (z 1)
var overlay: Node2D # projectiles, effects, bars, target (z 2)
var cam: Camera2D
var _cutouts := {} # id -> Cutout
var hud: Control
var controls := "keys" # keys | mouse | touch
var touch: TouchControls
var perf: PerfMeter

var _acc := 0.0
var _prev := {} # id -> Vector2 (milli-tiles) at the previous tick
var _intro := 1.6
var _ending := -1.0
var _pending_special := false
var _last_move := 0
var _target := -1
var _fx: Array = [] # {kind, pos (px), t}
var _msg := ""
var _msg_t := 0.0
var _fps_t := 0.0
var _t := 0.0
var fx := FxDraw.new()
var _ink := Color("2A1F3D")
var _in_water := {} # id -> bool, to splash when an animal enters the water
var _wake := {} # id -> seconds until the next ripple behind a swimmer
var _dive_delay := {} # Dive instance id -> its delay when first seen (marker progress)
var _blind := 0.0 # ink blindness on screen, eases in and out
var mode := "" # "" normal, "ball" Strandbal
var _prev_ball := Vector2.ZERO
var _waiting_kickoff := false


func _ready() -> void:
	Platform.entered("match")
	var profile: Dictionary = Platform.load_profile()
	var seed_value := Boot.seed_value() if Boot.seed_value() != 0 else randi() % 2000000000 + 1
	var animal := str(Boot.args.get("animal", profile.get("selected_animal", "octopus")))
	var bots := str(Boot.args.get("bots", "easy"))
	_plan = Boot.next_match
	Boot.next_match = {}
	mode = str(_plan.get("mode", Boot.args.get("mode", "")))
	if mode != "ball":
		mode = ""
	if _plan.has("online"):
		pass # set up below, after the offline defaults
	elif _plan.has("seed"): # the daily challenge: seed, animal and bots are the same for everyone
		seed_value = int(_plan.seed)
		animal = str(_plan.animal)
		bots = str(_plan.bots)
	if not Match.SLICE_ANIMALS.has(animal):
		animal = "octopus"
	m = Match.create(seed_value, animal, 6, bots if mode == "" or Boot.args.has("bots") else "normal", mode)
	if _plan.has("online"):
		_start_online(_plan.online)
	if Boot.args.has("tide") and OS.is_debug_build():
		m.sim.rules = m.sim.rules.duplicate(true)
		m.sim.rules.tide.phase_ticks = maxi(60, int(Boot.args.tide) * 30)
		m.sim.phase_left = int(m.sim.rules.tide.phase_ticks)
	if Boot.args.get("god", "") == "1" and OS.is_debug_build():
		# debug builds only: the smoke test needs the player alive to photograph later tide phases
		m.sim.ents[m.human].hp = 100000000
		m.sim.ents[m.human].max_hp = 100000000
	controls = choose_controls(profile, Boot.args, DisplayServer.is_touchscreen_available())
	_remember_positions()

	var sea := Node2D.new() # the open sea behind everything
	sea.z_index = -2
	sea.draw.connect(func(): sea.draw_rect(Rect2(-4000, -4000, m.sim.width * 1000 * PX + 8000, m.sim.height * 1000 * PX + 8000), ABYSS))
	add_child(sea)
	island = IslandView.new().setup(m.sim, 1000.0 * PX)
	island.z_index = -1
	add_child(island)
	var world: Dictionary = Content.load_json("res://data/palette.json").world
	_ink = Color(str(world.ink))
	_team = [Color(str(world.team_blue)), Color(str(world.team_orange))]
	_waiting_kickoff = mode == "ball"
	board = Node2D.new()
	board.draw.connect(_draw_board)
	add_child(board)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	actors.z_index = 1
	add_child(actors)
	for e in m.sim.ents:
		var c := Cutout.new()
		c.size_px = ANIMAL_PX
		actors.add_child(c)
		var id := str(m.sim.animals[e.id].id)
		c.build(id, Rewards.equipped_look(profile, id) if e.id == m.human else "") # the player wears their look
		_cutouts[e.id] = c
	overlay = Node2D.new()
	overlay.z_index = 2
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	_update_cutouts()
	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(m.sim.width * 1000 * PX)
	cam.limit_bottom = int(m.sim.height * 1000 * PX)
	cam.position = Vector2(cam.limit_right / 2.0, cam.limit_bottom / 2.0)
	cam.zoom = Vector2(0.55, 0.55)
	add_child(cam)
	cam.make_current()
	_build_hud()
	perf = PerfMeter.new() # F3 or perf=1 shows it; the debug fps log uses it too
	add_child(perf)
	_say(tr("DROP_TITLE") if mode == "" else tr("BALL_YOUR_TEAM" if m.sim.ents[m.human].team == 0 else "BALL_YOUR_TEAM_ORANGE"), _intro)


# --- loop ---

func _process(delta: float) -> void:
	_t += delta
	if _intro > 0.0:
		_intro -= delta
		cam.zoom = cam.zoom.lerp(Vector2.ONE if _intro < 0.6 else Vector2(0.55, 0.55), minf(1.0, delta * 4.0))
	elif _ending < 0.0:
		_acc += delta
		var steps := 0
		while _acc >= DT and steps < MAX_STEPS_PER_FRAME:
			if rb != null and not _online_step():
				break # online: waiting for the start, or for someone's input (more than 1 s behind)
			if rb == null:
				_remember_positions()
				m.step(_command())
			_handle_events()
			if mode == "ball":
				_kickoff_whistle()
			_acc -= DT
			steps += 1
		if steps == MAX_STEPS_PER_FRAME:
			_acc = 0.0 # a slow frame must not spiral
		if m.finished() or m.human_out():
			_ending = 1.4
	else:
		_ending -= delta
		if _ending <= 0.0:
			_finish()
			return
	for f in _fx:
		f.t += delta
	_fx = _fx.filter(func(f): return f.t < 0.7)
	fx.update(delta)
	_update_blind(delta)
	_msg_t -= delta
	_update_cutouts()
	_update_camera(delta)
	_update_hud()
	board.queue_redraw()
	overlay.queue_redraw()
	hud.queue_redraw()
	if OS.is_debug_build():
		_fps_t += delta
		if _fps_t >= 5.0:
			_fps_t = 0.0
			var ps: Dictionary = perf.stats()
			print("fps %d tick %d t %.2f wall %d p95 %.1fms draws %d" % [Engine.get_frames_per_second(), m.sim.tick, _t, Time.get_ticks_msec(),
				ps.p95_ms, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])


func _alpha() -> float:
	return clampf(_acc / DT, 0.0, 1.0) if _intro <= 0.0 else 0.0


func _remember_positions() -> void:
	for e in m.sim.ents:
		_prev[e.id] = Vector2(e.x, e.y)
	_prev_ball = Vector2(m.sim.bx, m.sim.by)


func _pos_px(e: MatchSim.Ent) -> Vector2:
	var cur := Vector2(e.x, e.y)
	return Vector2(_prev.get(e.id, cur)).lerp(cur, _alpha()) * PX


func _update_camera(delta: float) -> void:
	if _intro > 0.6:
		return
	var me: MatchSim.Ent = m.sim.ents[m.human]
	var focus := me
	if not me.alive:
		for e in m.sim.ents:
			if e.alive:
				focus = e
				break
	var look := Vector2(Fx.cos_a(me.aim), Fx.sin_a(me.aim)) / 1024.0 * 120.0 if me.alive else Vector2.ZERO
	cam.position = cam.position.lerp(_pos_px(focus) + look, minf(1.0, delta * 6.0))


# --- input -> command ---

func _command() -> Dictionary:
	var e: MatchSim.Ent = m.sim.ents[m.human]
	var cmd := {"m": -1, "a": -1, "s": -1}
	var mx := int(_key(KEY_D) or _key(KEY_RIGHT)) - int(_key(KEY_A) or _key(KEY_LEFT))
	var my := int(_key(KEY_S) or _key(KEY_DOWN)) - int(_key(KEY_W) or _key(KEY_UP))
	if controls == "touch" and touch != null and touch.move != Vector2.ZERO:
		cmd.m = Fx.atan2_a(int(touch.move.y * 1000), int(touch.move.x * 1000))
		_last_move = cmd.m
	elif mx != 0 or my != 0:
		cmd.m = Fx.atan2_a(my * 1000, mx * 1000)
		_last_move = cmd.m
	var target := _auto_target(e)
	_target = target.id if target != null else -1
	var aim := _last_move
	var dist := -1
	var ball_d := Fx.dist(m.sim.bx - e.x, m.sim.by - e.y) if mode == "ball" else 1 << 30
	if controls != "mouse" and ball_d < m.sim.attack_range(e) * 9 / 10:
		target = null
		_target = -1
		aim = Fx.atan2_a(m.sim.by - e.y, m.sim.bx - e.x)
		dist = ball_d
	elif controls == "mouse":
		var world := get_global_mouse_position() / PX
		aim = Fx.atan2_a(int(world.y) - e.y, int(world.x) - e.x)
		dist = Fx.dist(int(world.x) - e.x, int(world.y) - e.y)
	elif target != null:
		aim = Fx.atan2_a(target.y - e.y, target.x - e.x)
		dist = Fx.dist(target.x - e.x, target.y - e.y)
	var attacking := _key(KEY_SPACE)
	if controls == "mouse":
		attacking = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	elif controls == "touch":
		attacking = touch != null and touch.attacking or _key(KEY_SPACE)
	if attacking:
		cmd.a = aim
	if _pending_special:
		_pending_special = false
		cmd.s = aim
		cmd["sd"] = dist
	return cmd


func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


## Nearest enemy within attack range (+15 %): the keyboard "auto-aim".
func _auto_target(e: MatchSim.Ent) -> MatchSim.Ent:
	var reach := m.sim.attack_range(e) * 115 / 100
	var best: MatchSim.Ent = null
	var best_d2 := reach * reach
	for o in m.sim.ents:
		if o.alive and o.id != e.id and (e.team < 0 or o.team != e.team):
			var d2 := MatchSim._d2(o.x - e.x, o.y - e.y)
			if d2 < best_d2:
				best = o
				best_d2 = d2
	return best


func _unhandled_input(event: InputEvent) -> void:
	if UiTheme.is_emulated(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if controls == "keys" and event.physical_keycode == KEY_SHIFT:
			_pending_special = true
		elif event.physical_keycode == KEY_ESCAPE and OS.is_debug_build():
			_ending = 0.01
	elif event is InputEventMouseButton and event.pressed and controls == "mouse" and event.button_index == MOUSE_BUTTON_RIGHT:
		_pending_special = true


func _on_special_pressed() -> void:
	_pending_special = true


# --- events ---

func _handle_events() -> void:
	for ev in m.sim.events:
		match str(ev.type):
			"attack", "special":
				_cutouts[int(ev.id)].trigger("attack")
				_sound(_attack_sound(int(ev.id), str(ev.type), str(ev.get("kind", ""))), _pos_px(m.sim.ents[int(ev.id)]))
			"hit":
				_cutouts[int(ev.id)].trigger("hit")
				_sound("hit", Vector2(ev.x, ev.y) * PX)
				_fx.append({"kind": "spark", "pos": Vector2(ev.x, ev.y) * PX, "t": 0.0})
			"ko":
				_cutouts[int(ev.id)].trigger("ko")
				_fx.append({"kind": "splash", "pos": Vector2(ev.x, ev.y) * PX, "t": 0.0})
				fx.splash(Vector2(ev.x, ev.y) * PX, 1.6)
				_sound("ko", Vector2(ev.x, ev.y) * PX)
				if int(ev.id) == m.human:
					_say(tr("HUD_WASHED_AWAY"), 1.5)
			"snack":
				_fx.append({"kind": "heal", "pos": Vector2(ev.x, ev.y) * PX, "t": 0.0})
				if int(ev.id) == m.human:
					Sfx.play("snack")
			"dive":
				_fx.append({"kind": "boom", "pos": Vector2(ev.x, ev.y) * PX, "t": 0.0})
				var at := Vector2(ev.x, ev.y)
				var wet := m.sim.depth_at(int(at.x), int(at.y)) >= 1
				fx.splash(at * PX, 2.0, Color.WHITE if wet else Color("C9A26B"))
				_sound("boom", at * PX)
			"tide_warning":
				_say(tr("HUD_TIDE_WARNING"), 2.0)
				Sfx.play("tide")
			"tide_rise":
				_say(tr("HUD_TIDE_RISES"), 1.5)
			"sudden_death":
				_say(tr("HUD_SUDDEN_DEATH"), 1.5)
			"kick":
				_sound("kick", Vector2(ev.x, ev.y) * PX, -2.0 + 4.0 * minf(1.0, float(ev.power) / 860.0))
				_fx.append({"kind": "spark", "pos": Vector2(ev.x, ev.y) * PX, "t": 0.0})
			"bounce":
				_sound("splash", Vector2(ev.x, ev.y) * PX, -10.0)
			"goal":
				var at := Vector2(ev.x, ev.y) * PX
				fx.splash(at, 2.4, _team[int(ev.team)]) # confetti in the scoring team's colour
				fx.splash(at, 1.6)
				_fx.append({"kind": "boom", "pos": at, "t": 0.0})
				var ours: bool = int(ev.team) == m.sim.ents[m.human].team
				var scorer := int(ev.by)
				_say(tr("BALL_YOU_SCORED") if scorer == m.human else (tr("BALL_GOAL") if ours else tr("BALL_GOAL_AGAINST")), 1.8)
				Sfx.play("cheer" if ours else "ko")
				_waiting_kickoff = true
				_prev_ball = Vector2(m.sim.bx, m.sim.by)
				for e in m.sim.ents:
					_prev[e.id] = Vector2(e.x, e.y) # the kickoff teleports everyone: no sliding across the field
			"golden":
				_say(tr("BALL_GOLDEN"), 2.5)
				Sfx.play("tide")
			"respawn":
				_cutouts[int(ev.id)].revive()
				_prev[int(ev.id)] = Vector2(ev.x, ev.y)
			"finished":
				if mode == "ball":
					var mine: int = m.sim.ents[m.human].place
					for e in m.sim.ents:
						if e.alive and e.place == 1 and mine != 2:
							_cutouts[e.id].trigger("win")
					_say(tr(["", "BALL_WON", "BALL_DRAW", "BALL_LOST"][clampi(mine, 1, 3)]), 1.5)
					Sfx.play("whistle")
					Sfx.play("win" if mine == 1 else "ko")
					continue
				for e in m.sim.ents:
					if e.alive and e.place == 1:
						_cutouts[e.id].trigger("win")
				if m.sim.ents[m.human].place == 1:
					_say(tr("HUD_LAST_DRY"), 1.5)
					Sfx.play("win")


## Strandbal: the whistle when the kickoff pause ends and play starts.
func _kickoff_whistle() -> void:
	if _waiting_kickoff and m.sim.kickoff == 0 and not m.finished():
		_waiting_kickoff = false
		Sfx.play("whistle")


func _say(text: String, seconds: float) -> void:
	_msg = text
	_msg_t = seconds


func _finish() -> void:
	if net != null:
		net.close()
	Boot.last_result = m.human_result()
	Boot.last_result["bots"] = m.bot_level
	Boot.last_result["replay"] = Replay.encode(m.replay)
	if _plan.has("daily"):
		Boot.last_result["daily"] = _plan.daily
	if _plan.has("run"): # a counted run (week board): token from the leaderboards service
		Boot.last_result["run"] = _plan.run
	get_tree().change_scene_to_file(RESULT_SCENE)


# --- drawing: island, water, snacks, effects, animals ---

const DEEP := Color("1F6F9F")
const ABYSS := Color("134A6E")
const INK := Color("2B3A4A")
const ME := Color("3FE0FF")
const FOE := Color("FF5A4E")


## On the ground, below the animals: snacks, ink clouds, dive markers, ripples, shadows and team rings.
func _draw_board() -> void:
	var sim := m.sim
	if mode == "ball":
		_draw_field()
	for s in sim.snacks:
		var p := Vector2(s[0], s[1]) * PX
		board.draw_circle(p, 13.0, INK)
		board.draw_circle(p, 10.0, Color("5BD66B"))
	var cloud_ticks := _special_value("ink", "ticks", 120)
	for c in sim.clouds:
		var fade := clampf(float(c.life) / 20.0, 0.0, 1.0) * clampf(float(cloud_ticks - c.life + 1) / 4.0, 0.0, 1.0)
		FxDraw.ink_cloud(board, Vector2(c.x, c.y) * PX, c.radius * PX, _t, fade, _ink)
	var live := {}
	for v in sim.dives:
		var key: int = v.get_instance_id()
		live[key] = true
		if not _dive_delay.has(key):
			_dive_delay[key] = maxi(1, v.delay)
		var progress: float = 1.0 - (float(v.delay) - _alpha()) / float(_dive_delay[key])
		FxDraw.dive_marker(board, Vector2(v.x, v.y) * PX, v.radius * PX, clampf(progress, 0.0, 1.0), ME if v.owner == m.human else FOE, _t)
	for key in _dive_delay.keys():
		if not live.has(key):
			_dive_delay.erase(key)
	fx.draw_rings(board)
	# shadows and team rings under the animals (styleguide: cyan = you, coral = others)
	for e in m.sim.ents:
		if e.alive:
			board.draw_set_transform(_pos_px(e) + Vector2(0, 20), 0.0, Vector2(1.0, 0.38))
			board.draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.18))
			if mode == "ball": # team colours; you get a white edge as well
				if e.id == m.human:
					board.draw_arc(Vector2.ZERO, 32.0, 0, TAU, 40, Color.WHITE, 15.0)
				board.draw_arc(Vector2.ZERO, 32.0, 0, TAU, 40, _team[e.team], 10.0)
			else:
				board.draw_arc(Vector2.ZERO, 32.0, 0, TAU, 40, ME if e.id == m.human else FOE, 9.0)
			board.draw_set_transform(Vector2.ZERO)
	if mode == "ball":
		board.draw_set_transform(_ball_px() + Vector2(0, 14), 0.0, Vector2(1.0, 0.4))
		board.draw_circle(Vector2.ZERO, float(sim.rules.ball.radius) * PX, Color(0, 0, 0, 0.22))
		board.draw_set_transform(Vector2.ZERO)


## Above the animals: projectiles, effects, health bars, "YOU", charges and the auto-aim target.
func _draw_overlay() -> void:
	var sim := m.sim
	for p in sim.projs:
		var pos := Vector2(p.x, p.y) * PX
		overlay.draw_circle(pos, p.radius * PX * 0.55 + 4.0, INK)
		overlay.draw_circle(pos, p.radius * PX * 0.55 + 1.0, ME if p.owner == m.human else FOE)
	for f in _fx:
		var k: float = f.t / 0.7
		match str(f.kind):
			"splash":
				for i in 3:
					overlay.draw_arc(f.pos, 12.0 + k * 60.0 + i * 12.0, 0, TAU, 32, Color(1, 1, 1, 1.0 - k), 4.0)
			"boom":
				overlay.draw_circle(f.pos, 156.0 * (0.6 + k * 0.5), Color(1.0, 0.77, 0.19, 0.5 * (1.0 - k)))
			"heal":
				overlay.draw_circle(f.pos + Vector2(0, -k * 30.0), 8.0, Color(0.36, 0.84, 0.42, 1.0 - k))
			_:
				overlay.draw_arc(f.pos, 4.0 + k * 16.0, 0, TAU, 16, Color(1, 1, 1, 1.0 - k), 2.0)
	if mode == "ball":
		_draw_ball()
	fx.draw_drops(overlay)
	if _blind > 0.01:
		FxDraw.ink_blind(overlay, _pos_px(sim.ents[m.human]), 150.0, _blind, _ink)
	for e in sim.ents:
		if e.alive:
			_draw_bars(e)
	if _target >= 0 and controls != "mouse" and sim.ents[_target].alive:
		overlay.draw_arc(_pos_px(sim.ents[_target]), 46.0, _t * 2.0, _t * 2.0 + TAU * 0.85, 32, Color("FFC530"), 4.0)


func _draw_bars(e: MatchSim.Ent) -> void:
	var p := _pos_px(e)
	var mine := e.id == m.human
	var lift := 22.0 if str(m.sim.animals[e.id].type) == "flyer" else 0.0
	var w := 56.0
	var top := p + Vector2(-w / 2, -86 - lift)
	overlay.draw_rect(Rect2(top - Vector2(2, 2), Vector2(w + 4, 11)), INK)
	var f := clampf(float(e.hp) / float(e.max_hp), 0.0, 1.0)
	var col: Color = FOE if mode == "" else _team[e.team]
	if mine:
		col = Color("5BD66B") if f > 0.5 else (Color("FFD23F") if f > 0.25 else FOE)
	overlay.draw_rect(Rect2(top, Vector2(w * f, 7)), col)
	if mine:
		var font := UiTheme.title_font()
		overlay.draw_string_outline(font, top + Vector2(-20, -10), tr("HUD_YOU"), HORIZONTAL_ALIGNMENT_CENTER, w + 40, 24, 7, INK)
		overlay.draw_string(font, top + Vector2(-20, -10), tr("HUD_YOU"), HORIZONTAL_ALIGNMENT_CENTER, w + 40, 24, Color.WHITE)
		for i in int(m.sim.rules.attack.charges):
			var c := p + Vector2(-16 + i * 16, 42)
			overlay.draw_circle(c, 7.0, INK)
			overlay.draw_circle(c, 5.0, Color("FFC530") if i < e.charges else Color(1, 1, 1, 0.4))


## Cutout animals follow the sim: position (interpolated), walking, swimming, facing.
func _update_cutouts() -> void:
	for e in m.sim.ents:
		var c: Cutout = _cutouts[e.id]
		var flyer := str(m.sim.animals[e.id].type) == "flyer"
		var pos := _pos_px(e) + Vector2(0, 18 - (14.0 if flyer else 0.0))
		c.moving = c.position.distance_to(pos) > 0.6
		c.position = pos
		c.swimming = e.alive and not flyer and m.sim.depth_at(e.x, e.y) >= 1
		if c.swimming and not _in_water.get(e.id, true):
			fx.splash(_pos_px(e) + Vector2(0, 16), 0.7)
			_sound("splash", _pos_px(e), -6.0)
		_in_water[e.id] = c.swimming
		if c.swimming and c.moving:
			_wake[e.id] = float(_wake.get(e.id, 0.0)) - get_process_delta_time()
			if _wake[e.id] <= 0.0:
				_wake[e.id] = 0.28
				fx.ripple(_pos_px(e) + Vector2(0, 18))
		c.facing = -1.0 if Fx.cos_a(e.aim) < 0 else 1.0
		if not e.alive and c.is_gone():
			c.visible = false


# --- HUD ---

var _left: Label
var _tide: Label
var _tide_bar: ProgressBar
var _msg_label: Label
var _special: Button


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.theme = UiTheme.get_theme()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.apply(hud) # out of notches and rounded corners

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	top.position = Vector2(40, 30)
	hud.add_child(top)
	_left = _chip_label(top)
	_tide = _chip_label(top)
	_tide_bar = ProgressBar.new()
	_tide_bar.custom_minimum_size = Vector2(220, 24)
	_tide_bar.show_percentage = false
	_tide_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = DEEP
	fill.set_corner_radius_all(12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color.WHITE
	bg.border_color = INK
	bg.set_border_width_all(4)
	bg.set_corner_radius_all(12)
	_tide_bar.add_theme_stylebox_override("fill", fill)
	_tide_bar.add_theme_stylebox_override("background", bg)
	top.add_child(_tide_bar)

	_msg_label = Label.new()
	_msg_label.label_settings = UiTheme.heading(68)
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(_msg_label)
	_msg_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_msg_label.position.y = 140
	_msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_special = Button.new()
	_special.text = tr("HUD_SPECIAL")
	_special.focus_mode = Control.FOCUS_NONE
	_special.custom_minimum_size = Vector2(220, 110)
	_special.pressed.connect(_on_special_pressed)
	hud.add_child(_special)
	_special.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_special.offset_left = -280
	_special.offset_top = -170
	_special.offset_right = -60
	_special.offset_bottom = -60
	if controls == "touch":
		touch = TouchControls.new()
		hud.add_child(touch)
		touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hud.move_child(touch, 0) # below the buttons
		touch.blocked.append(_special)
		# the special button sits above the attack button, within thumb reach
		_special.offset_top = -170 - 2.0 * TouchControls.ATTACK_RADIUS - 60.0
		_special.offset_bottom = -60 - 2.0 * TouchControls.ATTACK_RADIUS - 60.0

	var hint := Label.new()
	hint.text = {"keys": tr("HUD_CONTROLS_KEYS"), "mouse": tr("HUD_CONTROLS_MOUSE"), "touch": tr("HUD_CONTROLS_TOUCH")}.get(controls, "")
	if controls == "touch": # the hint sits where the thumb goes: show it at the start only
		get_tree().create_timer(4.0).timeout.connect(hint.hide)
	hint.label_settings = UiTheme.heading(26, Color.WHITE, 6)
	hud.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 40
	hint.offset_top = -70


func _chip_label(parent: Control) -> Label:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	var l := Label.new()
	l.add_theme_font_override("font", UiTheme.title_font())
	l.add_theme_font_size_override("font_size", 34)
	panel.add_child(l)
	return l


func _update_hud() -> void:
	var sim := m.sim
	_left.text = tr("HUD_LEFT").format({"count": sim.alive_count()})
	var start := int(sim.rules.tide.start_level)
	_tide.text = tr("HUD_TIDE").format({"level": sim.level - start + 1, "max": int(sim.rules.tide.max_level) - start + 1})
	if mode == "ball":
		_left.text = tr("BALL_SCORE").format({"blue": sim.score_0, "orange": sim.score_1})
		var left := sim.ball_seconds_left()
		_tide.text = ("%d:%02d" % [left / 60, left % 60]) if sim.golden == 0 else tr("BALL_GOLDEN_SHORT")
	var phase := float(sim.rules.tide.phase_ticks)
	_tide_bar.value = 100.0 if sim.level >= int(sim.rules.tide.max_level) else (1.0 - sim.phase_left / phase) * 100.0
	_msg_label.text = _msg
	_msg_label.modulate.a = clampf(_msg_t * 2.0, 0.0, 1.0)
	var me: MatchSim.Ent = sim.ents[m.human]
	var ready := me.alive and me.special >= int(sim.rules.attack.special_hits)
	_special.theme_type_variation = "PlayButton" if ready else ""
	_special.add_theme_font_size_override("font_size", 40)
	_special.modulate.a = 1.0 if me.alive else 0.4


## Ink blindness eases in while the player stands in an enemy cloud (the sim slows them there).
func _update_blind(delta: float) -> void:
	var me: MatchSim.Ent = m.sim.ents[m.human]
	var inside := false
	if me.alive:
		for c in m.sim.clouds:
			if c.owner != me.id and Vector2(c.x - me.x, c.y - me.y).length() <= c.radius + me.radius:
				inside = true
	_blind = move_toward(_blind, 1.0 if inside else 0.0, delta * (4.0 if inside else 2.0))


## A number from an animal's special in data/animals.json (first animal with that special kind).
func _special_value(kind: String, key: String, fallback: int) -> int:
	for a in m.sim.animals:
		var sp: Dictionary = a.get("special", {})
		if str(sp.get("kind", "")) == kind:
			return int(sp.get(key, fallback))
	return fallback


## Sounds in the world are heard from the camera: quieter far away, silent off screen.
func _sound(sound: String, pos: Vector2, extra_db := 0.0) -> void:
	var db := Sfx.attenuation_db(pos.distance_to(cam.position), 1920.0 / cam.zoom.x) + extra_db
	if db > -60.0:
		Sfx.play(sound, db)


const ATTACK_SOUNDS := {"snip": "snip", "fan": "plop", "long": "peck"}


func _attack_sound(id: int, type: String, kind: String) -> String:
	if type == "special":
		return {"dash": "dash", "ink": "ink", "dive": "dive"}.get(kind, "hit")
	var animal: Dictionary = m.sim.animals[id]
	return ATTACK_SOUNDS.get(str(animal.get("attack", {}).get("kind", "")), "hit")


## keys | mouse | touch: the debug argument, else the player's choice, else touch on a touchscreen (pure, tested).
static func choose_controls(profile: Dictionary, args: Dictionary, touchscreen: bool) -> String:
	if ["keys", "mouse", "touch"].has(str(args.get("controls", ""))):
		return str(args.controls)
	var chosen := str(profile.get("settings", {}).get("controls", ""))
	if ["keys", "mouse", "touch"].has(chosen):
		return chosen
	return "touch" if touchscreen else "keys"


# --- online (phase 12c): relay + rollback ---

## The lobby's "match" message: same seed and seats on every screen; bots fill the empty seats.
func _start_online(info: Dictionary) -> void:
	var animals: Array = info.get("animals", [])
	m = Match.create_online(int(info.seed), animals, 6, "normal", mode)
	m.human = int(info.slot)
	rb = Rollback.new(m, m.human, int(info.get("delay", 2)))
	net = OnlineClient.new()
	add_child(net)
	net.message.connect(_on_net)
	net.closed.connect(func(_code: int) -> void:
		if _ending < 0.0:
			_say(tr("ONLINE_LOST"), 3.0)
			_ending = 3.0)
	net.open(St33f.client.pvp_room_url(str(info.room), int(info.slot), str(info.key)))
	_say(tr("ONLINE_WAITING_START"), 30.0)


func _on_net(msg: Dictionary) -> void:
	match OnlineClient.apply(rb, msg):
		"start":
			_online_started = true
			_say(tr("DROP_TITLE"), 1.2)
		"desync":
			# two screens disagree: nothing here can be trusted any more (should never happen; reported)
			_say(tr("ONLINE_DESYNC"), 3.0)
			if _ending < 0.0:
				_ending = 3.0
			if St33f.crash != null:
				St33f.crash.capture("desync", "online desync at tick %d" % int(msg.get("t", -1)), [])


## One online tick: own input out, the rollback plays (replaying corrected ticks), settled hashes out.
func _online_step() -> bool:
	if not _online_started or not rb.can_advance():
		return false
	_remember_positions()
	rb.local_input(Match.cmd_to(_command()))
	for out in OnlineClient.batch(rb.outbox):
		net.send(out)
	rb.outbox.clear()
	rb.advance()
	while rb.settled_hash(_next_hash) != -1:
		net.send({"type": "hash", "t": _next_hash, "h": rb.settled_hash(_next_hash)})
		if OS.is_debug_build():
			print("online settled tick %d hash %d seat %d of %d rollbacks %d" % [_next_hash, rb.settled_hash(_next_hash), m.human, m.sim.ents.size(), rb.rollbacks])
		_next_hash += Rollback.HASH_EVERY
	return true


# --- Strandbal (phase 14): field, goals, ball ---

const LINE := Color(1, 1, 1, 0.7)
var _team: Array = [Color("3F8CFF"), Color("FF8A3D")] # blue, orange from data/palette.json (rings, nets, confetti)


func _ball_px() -> Vector2:
	return _prev_ball.lerp(Vector2(m.sim.bx, m.sim.by), _alpha()) * PX


## Lines in the sand, the centre circle and the two goals (posts + net, in the colour of the team defending it).
func _draw_field() -> void:
	var f := m.sim.field
	var r := Rect2(Vector2(f[0], f[1]) * PX, Vector2(f[2] - f[0], f[3] - f[1]) * PX)
	board.draw_rect(r, LINE, false, 8.0)
	var cx := r.position.x + r.size.x / 2.0
	board.draw_line(Vector2(cx, r.position.y), Vector2(cx, r.end.y), LINE, 8.0)
	board.draw_arc(r.get_center(), 3.0 * 1000.0 * PX, 0, TAU, 48, LINE, 8.0)
	board.draw_circle(r.get_center(), 10.0, LINE)
	var y0 := float(m.sim.mouth[0]) * PX
	var y1 := float(m.sim.mouth[1]) * PX
	var depth := 2.2 * 1000.0 * PX
	for team in 2:
		var x := r.position.x if team == 0 else r.end.x
		var back := x - depth if team == 0 else x + depth
		var net := Rect2(Vector2(minf(x, back), y0), Vector2(depth, y1 - y0))
		board.draw_rect(net, Color(_team[team], 0.25))
		for i in range(1, 8):
			var yy := y0 + (y1 - y0) * i / 8.0
			board.draw_line(Vector2(x, yy), Vector2(back, yy), Color(1, 1, 1, 0.35), 2.0)
		board.draw_rect(net, _team[team], false, 6.0)
		for yy in [y0, y1]:
			board.draw_circle(Vector2(x, yy), 13.0, INK)
			board.draw_circle(Vector2(x, yy), 9.0, Color.WHITE)


## A beach ball: white with coloured wedges, rolling with the distance it travels.
func _draw_ball() -> void:
	var p := _ball_px()
	var rad := float(m.sim.rules.ball.radius) * PX
	var spin := (p.x + p.y) / maxf(1.0, rad)
	overlay.draw_circle(p, rad + 4.0, INK)
	overlay.draw_circle(p, rad, Color.WHITE)
	var cols := [_team[0], Color("FFD23F"), _team[1]]
	for i in 3:
		var a0 := spin + i * TAU / 3.0
		var pts := PackedVector2Array([p])
		for k in 7:
			pts.append(p + Vector2.from_angle(a0 + k * (TAU / 6.0) / 6.0) * rad)
		overlay.draw_colored_polygon(pts, cols[i])
	overlay.draw_circle(p, rad * 0.22, Color.WHITE)
	overlay.draw_arc(p + Vector2(-rad * 0.3, -rad * 0.35), rad * 0.3, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.8), 3.0)
