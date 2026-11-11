class_name Cutout
extends Node2D
## A cutout animal: one sprite per part (assets/animals/<id>/<part>.svg) on joints from data/rigs/<id>.json,
## animated in code (idle breathing, blink, walk, swim, attack, hit, knockout, win). Squash and stretch per the
## styleguide: attack <= 0.25 s, hit 0.15 s. The node's origin is the animal's feet.
## Parts are drawn in a 200 x 200 animal space; textures are imported at 2x (svg/scale=2) for sharp menus.

const ATTACK_S := 0.25
const HIT_S := 0.15
const KO_S := 0.8
const TEX_SCALE := 2.0

var animal_id := ""
var moving := false
var swimming := false
var facing := 1.0
var size_px := 90.0:
	set(v):
		size_px = v
		_root_scale()

var joints := {} # part name -> Node2D
var _rest := {} # part name -> Vector2 rest position
var _body: Node2D
var _water: Node2D
var _t := 0.0
var _attack := 0.0
var _hit := 0.0
var _ko := -1.0
var _win := false
var _blink := 2.0


func build(id: String, look := "") -> Cutout:
	animal_id = id
	var rig: Dictionary = Content.load_json("res://data/rigs/%s.json" % id)
	var folder := "res://assets/looks/%s" % look if look != "" else "res://assets/animals/%s" % id
	var origin := Vector2(rig.origin[0], rig.origin[1])
	var pivots := {}
	for p in rig.parts:
		pivots[p.name] = Vector2(p.pivot[0], p.pivot[1])
	_body = Node2D.new()
	add_child(_body)
	# create joints parent-first
	var pending: Array = rig.parts.duplicate()
	var guard := 0
	while not pending.is_empty() and guard < 100:
		guard += 1
		var p: Dictionary = pending.pop_front()
		var parent_name := str(p.parent)
		if parent_name != "" and not joints.has(parent_name):
			pending.append(p)
			continue
		var joint := Node2D.new()
		joint.name = p.name
		joint.z_index = int(p.z)
		var pivot: Vector2 = pivots[p.name]
		joint.position = pivot - (origin if parent_name == "" else pivots[parent_name])
		var sprite := Sprite2D.new()
		sprite.texture = load("%s/%s.svg" % [folder, p.name])
		sprite.centered = false
		sprite.scale = Vector2.ONE / TEX_SCALE
		# each texture is cropped to its part's box (x, y, w, h) in animal space; see tools/art/animals.py
		var box: Array = p.get("box", [0, 0, rig.size, rig.size])
		sprite.offset = (Vector2(box[0], box[1]) - pivot) * TEX_SCALE
		joint.add_child(sprite)
		(_body if parent_name == "" else joints[parent_name]).add_child(joint)
		joints[p.name] = joint
		_rest[p.name] = joint.position
	_water = Node2D.new()
	_water.z_index = 20
	_water.draw.connect(_draw_water)
	add_child(_water)
	_root_scale()
	return self


func trigger(what: String) -> void:
	match what:
		"attack":
			_attack = ATTACK_S
		"hit":
			_hit = HIT_S
		"ko":
			_ko = 0.0
		"win":
			_win = true


## Back in the game after washing away (Strandbal): visible and standing again.
func revive() -> void:
	_ko = -1.0
	visible = true


## Review only (zoo scene): play the knockout again from the start.
func free_ko_restart() -> void:
	_ko = 0.0


func is_gone() -> bool:
	return _ko >= KO_S


func _root_scale() -> void:
	scale = Vector2(facing, 1.0) * (size_px / 200.0)


func _process(delta: float) -> void:
	_t += delta
	_attack = maxf(0.0, _attack - delta)
	_hit = maxf(0.0, _hit - delta)
	_blink -= delta
	if _blink < -0.12:
		_blink = 2.0 + fmod(_t * 7.3, 2.5)
	if _ko >= 0.0:
		_ko += delta
	_pose()
	_water.visible = swimming and _ko < 0.0
	_water.queue_redraw()


func _pose() -> void:
	for n in joints:
		var j: Node2D = joints[n]
		j.position = _rest[n]
		j.rotation = 0.0
		j.scale = Vector2.ONE
	_body.position = Vector2.ZERO
	_body.rotation = 0.0
	_body.scale = Vector2.ONE
	modulate = Color.WHITE
	scale = Vector2(facing, 1.0) * (size_px / 200.0)

	var breathe := sin(_t * 3.0)
	_body.scale = Vector2(1.0 - breathe * 0.015, 1.0 + breathe * 0.025)
	var stride := _t * (9.0 if swimming else 14.0)
	if moving:
		_body.position.y = -absf(sin(stride)) * (3.0 if swimming else 6.0)
		_body.rotation = sin(stride) * 0.04
	var swing := sin(stride) * (0.45 if moving else 0.06)
	for side in [["limb_bl", 1.0], ["limb_fr", 1.0], ["limb_br", -1.0], ["limb_fl", -1.0]]:
		if joints.has(side[0]):
			joints[side[0]].rotation = swing * side[1]
	if joints.has("tail"):
		joints.tail.rotation = sin(_t * 5.0) * 0.12
	if joints.has("head"):
		joints.head.rotation = sin(_t * 2.0) * 0.05
	if animal_id == "gull" and joints.has("limb_fl"):
		joints.limb_fl.rotation = -absf(sin(_t * (16.0 if moving else 3.0))) * (0.5 if moving else 0.1)

	# blink
	if _blink < 0.0:
		for e in ["eye_l", "eye_r"]:
			if joints.has(e):
				joints[e].scale.y = 0.15

	# attack: a quick squash and the "weapon" part snaps forward
	if _attack > 0.0:
		var k := sin((1.0 - _attack / ATTACK_S) * PI)
		_body.scale *= Vector2(1.0 + 0.14 * k, 1.0 - 0.12 * k)
		for c in [["claw_l", -0.6], ["claw_r", 0.6]]:
			if joints.has(c[0]):
				joints[c[0]].rotation += c[1] * k
		if joints.has("head"):
			joints.head.position.x += 16.0 * k
		if animal_id == "octopus":
			for t in ["limb_fl", "limb_fr"]:
				joints[t].rotation += 0.5 * k * (1.0 if t == "limb_fr" else -1.0)

	# hit: flash and flinch
	if _hit > 0.0:
		var k := _hit / HIT_S
		modulate = Color(1.0 + k, 1.0 + k * 0.6, 1.0 + k * 0.6)
		_body.scale *= Vector2(1.0 + 0.1 * k, 1.0 - 0.1 * k)

	if _win:
		_body.position.y = -absf(sin(_t * 7.0)) * 26.0

	# knockout: washed away (spin, shrink, fade) — not violent, a bit silly
	if _ko >= 0.0:
		var k := clampf(_ko / KO_S, 0.0, 1.0)
		_body.rotation = k * TAU * 1.5
		_body.scale *= Vector2.ONE * (1.0 - 0.6 * k)
		modulate.a = 1.0 - k


func _draw_water() -> void:
	# the waterline at the animal's middle: only the top half shows while swimming
	var c := Color("5FD3C9")
	_water.draw_set_transform(Vector2(0, -26), 0.0, Vector2(1.0, 0.38))
	_water.draw_circle(Vector2.ZERO, 96.0, Color(c, 0.9))
	_water.draw_arc(Vector2.ZERO, 96.0, 0.0, TAU, 48, Color(0.97, 0.98, 0.97, 0.95), 10.0)
	_water.draw_set_transform(Vector2.ZERO)
