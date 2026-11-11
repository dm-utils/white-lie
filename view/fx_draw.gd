class_name FxDraw
extends RefCounted
## Match effects drawn in code: ink cloud, dive marker, splashes (droplets + rings), ripples and the ink
## blindness for whoever stands in an enemy cloud. Pure view: uses its own random numbers, never the sim's.
## Styleguide: effects never fully hide an animal; the ink cloud is the only effect that takes away sight,
## and only for the one inside it.

const INK := Color("2B3A4A")
const GRAVITY := 900.0 # px/s^2 for droplets (height above the ground, drawn as an upward offset)

var drops: Array = [] # {pos, vel, z, vz, r, col}
var rings: Array = [] # {pos, t, life, r0, r1, w, col}
var _rng := RandomNumberGenerator.new()


func _init(seed_value := 7) -> void:
	_rng.seed = seed_value


## A splash: droplets thrown up and out, plus flattened rings on the water (top-down with a slight tilt).
func splash(pos: Vector2, size := 1.0, col := Color(0.97, 0.98, 0.97)) -> void:
	for i in int(10 * size) + 4:
		var a := _rng.randf() * TAU
		var speed := _rng.randf_range(60.0, 170.0) * size
		drops.append({"pos": pos, "vel": Vector2(cos(a), sin(a) * 0.5) * speed, "z": 4.0,
			"vz": _rng.randf_range(160.0, 330.0) * sqrt(size), "r": _rng.randf_range(3.0, 6.0) * sqrt(size), "col": col})
	for i in 2:
		rings.append({"pos": pos, "t": -0.08 * i, "life": 0.6, "r0": 10.0 * size, "r1": 70.0 * size, "w": 5.0, "col": col})


## A small ripple, e.g. behind a swimming animal.
func ripple(pos: Vector2) -> void:
	rings.append({"pos": pos, "t": 0.0, "life": 0.7, "r0": 14.0, "r1": 40.0, "w": 3.0, "col": Color(1, 1, 1, 0.55)})


func update(delta: float) -> void:
	for d in drops:
		d.pos += d.vel * delta
		d.vz -= GRAVITY * delta
		d.z += d.vz * delta
	drops = drops.filter(func(d): return d.z > 0.0)
	for r in rings:
		r.t += delta
	rings = rings.filter(func(r): return r.t < r.life)


func is_idle() -> bool:
	return drops.is_empty() and rings.is_empty()


## Rings lie on the water, so they go on the board layer (below the animals).
func draw_rings(ci: CanvasItem) -> void:
	for r in rings:
		if r.t < 0.0:
			continue
		var k: float = r.t / r.life
		var col: Color = r.col
		col.a *= 1.0 - k
		ci.draw_set_transform(r.pos, 0.0, Vector2(1.0, 0.45))
		ci.draw_arc(Vector2.ZERO, lerpf(r.r0, r.r1, 1.0 - (1.0 - k) * (1.0 - k)), 0, TAU, 36, col, r.w * (1.0 - k * 0.6))
		ci.draw_set_transform(Vector2.ZERO)


## Droplets fly above the animals (overlay layer); outlined so they read on sand and on water.
func draw_drops(ci: CanvasItem) -> void:
	for d in drops:
		var p: Vector2 = d.pos - Vector2(0, d.z)
		ci.draw_circle(p, d.r + 1.5, Color(INK, 0.5))
		ci.draw_circle(p, d.r, d.col)


## The octopus' ink: a puffy cloud that swirls and thins out at the end of its life.
static func ink_cloud(ci: CanvasItem, pos: Vector2, radius: float, t: float, fade: float, ink: Color) -> void:
	var a := 0.6 * fade
	var puffs := 7
	var outline := Color(ink.darkened(0.35), a)
	var fill := Color(ink, a)
	# outline pass then fill pass, so overlapping puffs merge into one shape
	for pass_i in 2:
		for i in puffs + 1:
			var ang := i * TAU / puffs + t * 0.6
			var off := Vector2.ZERO if i == puffs else Vector2(cos(ang), sin(ang) * 0.8) * radius * 0.55
			var r := radius * (0.62 if i == puffs else 0.42 + 0.06 * sin(t * 2.0 + i))
			ci.draw_circle(pos + off, r + (5.0 if pass_i == 0 else 0.0), outline if pass_i == 0 else fill)
	for i in 3: # curls on top
		var ang := i * TAU / 3.0 - t * 1.2
		var c := pos + Vector2(cos(ang), sin(ang) * 0.8) * radius * 0.35
		ci.draw_arc(c, radius * 0.16, ang, ang + PI * 1.3, 12, Color(1, 1, 1, 0.22 * fade), 4.0)


## Where a dive will land: a dashed ring in the owner's colour that closes in, with a filling disc,
## so everybody can see it coming (styleguide: every attack is announced).
static func dive_marker(ci: CanvasItem, pos: Vector2, radius: float, progress: float, col: Color, t: float) -> void:
	ci.draw_set_transform(pos, 0.0, Vector2(1.0, 0.7))
	ci.draw_circle(Vector2.ZERO, radius, Color(col, 0.10 + 0.25 * progress))
	ci.draw_circle(Vector2.ZERO, radius * progress, Color(col, 0.22))
	var dashes := 12
	for i in dashes:
		var a := i * TAU / dashes + t * 1.5
		ci.draw_arc(Vector2.ZERO, radius, a, a + TAU / dashes * 0.55, 6, Color(INK, 0.7), 8.0)
		ci.draw_arc(Vector2.ZERO, radius, a, a + TAU / dashes * 0.55, 6, col, 4.0)
	ci.draw_set_transform(Vector2.ZERO)
	# the shadow of what's coming grows in the middle
	ci.draw_circle(pos, 6.0 + 18.0 * progress, Color(0, 0, 0, 0.25 * progress))


## Ink blindness: everything dark except a small hole around the player.
static func ink_blind(ci: CanvasItem, pos: Vector2, hole: float, strength: float, ink: Color) -> void:
	var width := 4000.0
	ci.draw_arc(pos, hole + width / 2.0, 0, TAU, 64, Color(ink, 0.78 * strength), width)
	ci.draw_arc(pos, hole + 30.0, 0, TAU, 64, Color(ink, 0.45 * strength), 60.0)
