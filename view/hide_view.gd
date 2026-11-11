extends Node2D
## A Verstoppertje session on screen (phase 3). Reads the sim, never changes it: input becomes a command per tick,
## the sim steps at 30 Hz, the view interpolates. Seekers see a disguised hider exactly as the real prop.
## Debug entry: --scene=hide --seed=N [--character=skipper] [--bots=easy|normal|hard]

const PX := 0.08 # screen pixels per milli-tile: 80 px per tile
const DT := 1.0 / 30.0
const MAX_STEPS := 3
const RESULT_SCENE := "res://ui/result_screen.tscn"
const PROP_PX := 104.0 # on-screen size of a 200 px prop SVG
const PERSON_SCALE := 0.7 # 200 x 240 SVG -> 140 x 168 px on screen (as big as an animal in Whitecap)
const INK := Color("2B3A4A")
const WOOD := Color("B98A55")
const STONE := Color("A9A9A2")
const ROOF := Color("C4553F")

var m: HideMatch
var island: IslandView
var board: Node2D # docks, quay, roofs, tells, shadows (z 0)
var actors: Node2D # props, disguised hiders and animals, sorted by y (z 1)
var overlay: Node2D # gulls, rings, the player's marker (z 2)
var cam: Camera2D
var hud: Control
var _people := {} # seat -> Sprite2D (the character, assets/people/<id>.svg)
var _masks := {} # seat -> Sprite2D (the prop a hider looks like)
var _prev := {}
var _acc := 0.0
var _t := 0.0
var _ending := -1.0
var _msg := ""
var _msg_t := 0.0
var _textures := {}
var _labels := {}
var _dark: ColorRect
var controls := "keys" # keys | mouse | touch
var touch: TouchControls
var rb: Rollback # online: the rollback driving the session
var net: OnlineClient # online: the room connection
var _online_started := false
var _next_hash := Rollback.HASH_EVERY - 1


class _Ground:
	## IslandView reads a sim; this gives it the harbour as heights (sea deep, shallow water, everything else dry).
	var width := 0
	var height := 0
	var heights := PackedByteArray()
	var level := 2
	var phase_left := 1000
	var finished := 0
	var rules := {"tide": {"warn_ticks": 0, "max_level": 2}}


func _ready() -> void:
	Platform.entered("hide")
	var profile: Dictionary = Platform.load_profile()
	var seed_value := Boot.seed_value() if Boot.seed_value() != 0 else randi() % 2000000000 + 1
	var who := str(Boot.args.get("character", profile.get("selected_character", "skipper")))
	if not HideMatch.CHARACTERS.has(who):
		who = "skipper"
	m = HideMatch.create(seed_value, who, 6, str(Boot.args.get("bots", "normal")))
	var plan: Dictionary = Boot.next_match
	Boot.next_match = {}
	if plan.has("online"):
		_start_online(plan.online)
	var s := m.sim
	var g := _Ground.new()
	g.width = s.width
	g.height = s.height
	for v in s.tiles:
		g.heights.append([0, 1, 3, 1, 4, 4][v]) # docks stand over water: planks are drawn on top
	var sea := Node2D.new()
	sea.z_index = -2
	sea.draw.connect(func(): sea.draw_rect(Rect2(-4000, -4000, s.width * 1000 * PX + 8000, s.height * 1000 * PX + 8000), Color("134A6E")))
	add_child(sea)
	island = IslandView.new().setup(g, 1000.0 * PX)
	island.z_index = -1
	add_child(island)
	board = Node2D.new()
	board.draw.connect(_draw_board)
	add_child(board)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	actors.z_index = 1
	add_child(actors)
	for p in s.props:
		var sp := _prop_sprite(int(p[0]))
		sp.position = Vector2(p[1], p[2]) * PX
		actors.add_child(sp)
	for e in s.ents:
		var c := Sprite2D.new()
		c.texture = load("res://assets/people/%s.svg" % str(s.characters[e.id].get("id", "skipper")))
		c.offset = Vector2(0, -80) # the SVG's feet (100, 200) on the position
		c.scale = Vector2.ONE * PERSON_SCALE
		actors.add_child(c)
		_people[e.id] = c
		var mask := _prop_sprite(0)
		mask.visible = false
		actors.add_child(mask)
		_masks[e.id] = mask
		_prev[e.id] = Vector2(e.x, e.y)
	overlay = Node2D.new()
	overlay.z_index = 2
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(s.width * 1000 * PX)
	cam.limit_bottom = int(s.height * 1000 * PX)
	add_child(cam)
	cam.make_current()
	cam.position = _pos(s.ents[m.human])
	_build_hud()
	_update_actors()
	_announce_round()


func _prop_sprite(kind: int) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = _texture(kind)
	sp.offset = Vector2(0, -50) # the SVG's foot point (100, 150) on the position
	sp.scale = Vector2.ONE * (PROP_PX / 200.0)
	return sp


func _texture(kind: int) -> Texture2D:
	if not _textures.has(kind):
		_textures[kind] = load("res://assets/props/%s.svg" % HideSim.kind_names()[kind])
	return _textures[kind]


# --- loop ---

func _process(delta: float) -> void:
	_t += delta
	_msg_t -= delta
	if _ending < 0.0:
		_acc += delta
		var steps := 0
		while _acc >= DT and steps < MAX_STEPS:
			if rb != null:
				if not _online_step():
					break # waiting for the start, or for someone's input
			else:
				for e in m.sim.ents:
					_prev[e.id] = Vector2(e.x, e.y)
				m.step(_command())
			_handle_events()
			_acc -= DT
			steps += 1
		if steps == MAX_STEPS:
			_acc = 0.0
		if m.finished():
			_ending = 1.5
	else:
		_ending -= delta
		if _ending <= 0.0:
			if net != null:
				net.close()
			Boot.last_result = m.human_result()
			get_tree().change_scene_to_file(RESULT_SCENE)
			return
	_update_actors()
	var me: HideSim.Ent = m.sim.ents[m.human]
	cam.position = cam.position.lerp(_pos(me), minf(1.0, delta * 6.0))
	_update_hud()
	board.queue_redraw()
	overlay.queue_redraw()


func _alpha() -> float:
	return clampf(_acc / DT, 0.0, 1.0)


func _pos(e: HideSim.Ent) -> Vector2:
	var cur := Vector2(e.x, e.y)
	return Vector2(_prev.get(e.id, cur)).lerp(cur, _alpha()) * PX


func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)


## Keys: WASD walk, Space acts on the nearest thing (hider: the nearest prop; seeker: the nearest prop or animal).
## Mouse: click a prop. Touch: the shared touch controls, in a later step.
func _command() -> Dictionary:
	var s := m.sim
	var me: HideSim.Ent = s.ents[m.human]
	var cmd := {"m": -1, "a": -1, "s": -1}
	var mx := int(_key(KEY_D) or _key(KEY_RIGHT)) - int(_key(KEY_A) or _key(KEY_LEFT))
	var my := int(_key(KEY_S) or _key(KEY_DOWN)) - int(_key(KEY_W) or _key(KEY_UP))
	if touch != null and touch.move != Vector2.ZERO:
		cmd.m = Fx.atan2_a(int(touch.move.y * 1000), int(touch.move.x * 1000))
	elif mx != 0 or my != 0:
		cmd.m = Fx.atan2_a(my * 1000, mx * 1000)
	var target := Vector2i(-1, -1)
	if touch != null and touch.attacking:
		target = _nearest_thing(me) # the action button: disguise / tap the nearest thing
	elif controls != "touch" and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var w := get_global_mouse_position() / PX
		target = Vector2i(int(w.x), int(w.y))
	elif _key(KEY_SPACE):
		target = _nearest_thing(me)
	if target != Vector2i(-1, -1):
		cmd.a = Fx.atan2_a(target.y - me.y, target.x - me.x)
		cmd["sd"] = Fx.dist(target.x - me.x, target.y - me.y)
	return cmd


func _nearest_thing(me: HideSim.Ent) -> Vector2i:
	var s := m.sim
	var best := Vector2i(-1, -1)
	var bd := -1
	for p in s.props:
		var d := HideSim._d2(p[1] - me.x, p[2] - me.y)
		if bd < 0 or d < bd:
			bd = d
			best = Vector2i(p[1], p[2])
	if me.role == HideSim.SEEKER:
		for o in s.ents:
			if o.role == HideSim.HIDER:
				var d := HideSim._d2(o.x - me.x, o.y - me.y)
				if d < bd:
					bd = d
					best = Vector2i(o.x, o.y)
	return best


func _handle_events() -> void:
	for ev in m.sim.events:
		match str(ev.type):
			"round":
				_announce_round()
			"seek":
				_say(tr("HIDE_SEEK_START"), 1.6)
				Sfx.play("whistle")
			"disguise":
				if int(ev.id) == m.human:
					Sfx.play("plop")
			"noise":
				Sfx.play_at("tap", Vector2(ev.x, ev.y) * PX, cam.position)
			"found":
				Sfx.play("cheer" if int(ev.by) == m.human or int(ev.id) != m.human else "ko")
				if int(ev.id) == m.human:
					_say(tr("HIDE_YOU_FOUND"), 1.8)
				elif int(ev.by) == m.human:
					_say(tr("HIDE_GOT_ONE"), 1.4)
			"miss":
				if int(ev.id) == m.human:
					Sfx.play("hit")
					_say(tr("HIDE_MISS"), 1.0)
			"reveal":
				_say(tr("HIDE_REVEAL"), 2.0)
				Sfx.play("whistle")
			"finished":
				Sfx.play("win" if m.sim.result()[m.human].place == 1 else "tap")


func _announce_round() -> void:
	var me: HideSim.Ent = m.sim.ents[m.human]
	_say(tr("HIDE_ROLE_HIDER") if me.role == HideSim.HIDER else tr("HIDE_ROLE_SEEKER"), 2.2)


func _say(text: String, seconds: float) -> void:
	_msg = text
	_msg_t = seconds


# --- drawing ---

func _update_actors() -> void:
	var s := m.sim
	var me: HideSim.Ent = s.ents[m.human]
	var reveal := s.phase == HideSim.PHASE_REVEAL
	for e in s.ents:
		var c: Sprite2D = _people[e.id]
		var mask: Sprite2D = _masks[e.id]
		var pos := _pos(e)
		var disguised: bool = e.role == HideSim.HIDER and e.disguise >= 0
		c.visible = e.role != HideSim.GULL and (not disguised or reveal)
		var walking: bool = e.still == 0
		c.position = pos + Vector2(0, 18 - (absf(sin(_t * 14.0)) * 5.0 if walking else 0.0))
		c.scale.x = PERSON_SCALE * (-1.0 if Fx.cos_a(e.aim) < 0 else 1.0)
		c.rotation = sin(_t * 14.0) * 0.06 if walking else 0.0
		mask.visible = disguised and not reveal
		if mask.visible:
			mask.texture = _texture(e.disguise)
			mask.position = pos
			# moving makes the prop wobble (the tell everyone can see); still = exactly like the real one
			mask.rotation = sin(_t * 18.0) * 0.12 if e.still < int(s.rules.still_ticks) else 0.0
			mask.modulate.a = 0.6 if e.id == me.id else 1.0


func _draw_board() -> void:
	var s := m.sim
	var tp := 1000.0 * PX
	for y in s.height:
		for x in s.width:
			var k := s.tiles[y * s.width + x]
			var r := Rect2(x * tp, y * tp, tp, tp)
			match k:
				3: # dock: planks
					board.draw_rect(r, WOOD)
					for i in 4:
						board.draw_line(r.position + Vector2(0, i * tp / 4.0), r.position + Vector2(tp, i * tp / 4.0), WOOD.darkened(0.25), 2.0)
				4: # quay: stone slabs
					board.draw_rect(r, STONE)
					board.draw_rect(r.grow(-2.0), STONE.lightened(0.08))
				5: # sheds and the office: roofs
					board.draw_rect(r, ROOF)
					board.draw_line(r.position + Vector2(0, tp / 2.0), r.position + Vector2(tp, tp / 2.0), ROOF.darkened(0.2), 3.0)
	# tells: footprints, ripples, noise rings
	for t in s.tells:
		var p := Vector2(t.x, t.y) * PX
		var life := clampf(float(t.until - s.tick) / 60.0, 0.0, 1.0)
		match t.kind:
			0:
				board.draw_circle(p + Vector2(-7, 0), 5.0, Color(0.35, 0.25, 0.15, 0.5 * life))
				board.draw_circle(p + Vector2(7, 6), 5.0, Color(0.35, 0.25, 0.15, 0.5 * life))
			1:
				board.draw_arc(p, 20.0 + (1.0 - life) * 26.0, 0, TAU, 24, Color(1, 1, 1, 0.7 * life), 3.0)
			2:
				board.draw_arc(p, 16.0 + (1.0 - life) * 40.0, 0, TAU, 24, Color(1.0, 0.85, 0.3, 0.8 * life), 4.0)
	# shadows under the animals
	for e in s.ents:
		if _people[e.id].visible:
			board.draw_set_transform(_pos(e) + Vector2(0, 20), 0.0, Vector2(1.0, 0.38))
			board.draw_circle(Vector2.ZERO, 26.0, Color(0, 0, 0, 0.18))
			board.draw_set_transform(Vector2.ZERO)


func _draw_overlay() -> void:
	var s := m.sim
	var me: HideSim.Ent = s.ents[m.human]
	for e in s.ents:
		if e.role == HideSim.GULL: # found hiders fly over the harbour as little gulls
			var p := _pos(e) + Vector2(0, -30)
			overlay.draw_circle(p, 16.0, INK)
			overlay.draw_circle(p, 12.0, Color.WHITE)
			overlay.draw_line(p + Vector2(-26, -6), p + Vector2(-8, 0), INK, 5.0)
			overlay.draw_line(p + Vector2(26, -6), p + Vector2(8, 0), INK, 5.0)
	if s.phase == HideSim.PHASE_REVEAL: # the reveal: everyone's name over their head
		var font := UiTheme.title_font()
		for e in s.ents:
			if e.role != HideSim.GULL:
				var top := _pos(e) + Vector2(-80, -112)
				var label: String = tr("HUD_YOU") if e.id == m.human else (m.names[e.id] if m.names[e.id] != "" else tr("ONLINE_PLAYER"))
				overlay.draw_string_outline(font, top, label, HORIZONTAL_ALIGNMENT_CENTER, 160, 22, 7, INK)
				overlay.draw_string(font, top, label, HORIZONTAL_ALIGNMENT_CENTER, 160, 22, Color.WHITE)
	if me.role != HideSim.GULL:
		var p := _pos(me)
		overlay.draw_arc(p + Vector2(0, 18), 40.0, 0, TAU, 32, Color("3FE0FF"), 4.0)
	if me.dizzy > 0:
		overlay.draw_arc(_pos(me) + Vector2(0, -70), 14.0, _t * 8.0, _t * 8.0 + 4.5, 12, Color("FFD23F"), 4.0)


# --- HUD ---

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.theme = UiTheme.get_theme()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	SafeArea.apply(hud)
	_dark = ColorRect.new()
	_dark.color = Color(0.05, 0.06, 0.1, 1.0) # no peeking
	_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_dark)
	_dark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	top.position = Vector2(40, 30)
	hud.add_child(top)
	for key in ["role", "time", "found", "round", "points"]:
		var panel := PanelContainer.new()
		top.add_child(panel)
		var l := Label.new()
		l.add_theme_font_override("font", UiTheme.title_font())
		l.add_theme_font_size_override("font_size", 34)
		panel.add_child(l)
		_labels[key] = l
	var msg := Label.new()
	msg.label_settings = UiTheme.heading(68)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(msg)
	msg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	msg.position.y = 160
	msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_labels["msg"] = msg
	controls = Controls.choose(Platform.load_profile(), Boot.args, DisplayServer.is_touchscreen_available())
	if controls == "touch":
		touch = TouchControls.new()
		hud.add_child(touch)
		touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hud.move_child(touch, 1) # above the dark screen, below the labels
	var hint := Label.new()
	hint.text = tr("HIDE_CONTROLS_TOUCH") if controls == "touch" else tr("HIDE_CONTROLS_KEYS")
	if controls == "touch":
		get_tree().create_timer(4.0).timeout.connect(hint.hide)
	hint.label_settings = UiTheme.heading(26, Color.WHITE, 6)
	hud.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 40
	hint.offset_top = -70


func _update_hud() -> void:
	var s := m.sim
	var me: HideSim.Ent = s.ents[m.human]
	var roles := {HideSim.HIDER: "HIDE_ROLE_SHORT_HIDER", HideSim.SEEKER: "HIDE_ROLE_SHORT_SEEKER", HideSim.GULL: "HIDE_ROLE_SHORT_GULL"}
	_labels.role.text = tr(roles[me.role])
	var secs := maxi(0, s.phase_left) / 30
	_labels.time.text = "%d:%02d" % [secs / 60, secs % 60]
	_labels.found.text = tr("HIDE_FOUND").format({"found": s.hiders_total() - s.hiders_left(), "total": s.hiders_total()})
	_labels.round.text = tr("HIDE_ROUND").format({"round": s.round_no + 1, "rounds": int(s.rules.rounds)})
	_labels.points.text = tr("HIDE_POINTS").format({"points": me.points})
	_labels.msg.text = _msg
	_labels.msg.modulate.a = clampf(_msg_t * 2.0, 0.0, 1.0)
	# seekers wait in the dark while the others hide
	_dark.visible = s.phase == HideSim.PHASE_HIDE and me.role == HideSim.SEEKER
	if _dark.visible:
		_labels.msg.text = tr("HIDE_WAIT_DARK").format({"seconds": secs})
		_labels.msg.modulate.a = 1.0


# --- online (phase 4): relay + rollback, as in Whitecap ---

## The lobby's "match" message: same seed and seats on every screen; bots fill the empty seats.
func _start_online(info: Dictionary) -> void:
	m = HideMatch.create_online(int(info.seed), info.get("animals", []), 6, "normal")
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
			_announce_round()
		"desync":
			_say(tr("ONLINE_DESYNC"), 3.0)
			if _ending < 0.0:
				_ending = 3.0
			if St33f.crash != null:
				St33f.crash.capture("desync", "online desync at tick %d" % int(msg.get("t", -1)), [])


## One online tick: own input out, the rollback plays (replaying corrected ticks), settled hashes out.
func _online_step() -> bool:
	if not _online_started or not rb.can_advance():
		return false
	for e in m.sim.ents:
		_prev[e.id] = Vector2(e.x, e.y)
	rb.local_input(HideMatch.cmd_to(_command()))
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

