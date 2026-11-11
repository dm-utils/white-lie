extends Node2D
## Debug scene for art review (scene=fx): a piece of the real island with the tide warning on, and every match
## effect next to it: ink cloud on sand and on water, dive markers closing in, splashes, swim ripples.
## Effects repeat so a screenshot at any moment shows them. Labels are debug text, not tr().

const TILE_PX := 80.0
const WINDOW := Vector2i(15, 0) # top-left tile of the shown 24 x 13.5 tiles: half beach, half sea
const ME := Color("3FE0FF")
const FOE := Color("FF5A4E")

var fx := FxDraw.new(3)
var _ink := Color("2A1F3D")
var _ground: Node2D
var _air: Node2D
var _t := 0.0
var _next_splash := 0.0


func _ready() -> void:
	var m := Match.create(123, "crab", 6, "easy")
	m.sim.phase_left = 30 # inside the warning window: the tiles that flood next glitter
	var island := IslandView.new().setup(m.sim, TILE_PX)
	island.position = -Vector2(WINDOW) * TILE_PX
	island.z_index = -1
	add_child(island)
	_ink = Color(str(Content.load_json("res://data/palette.json").world.ink))
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground)
	add_child(_ground)
	_air = Node2D.new()
	_air.z_index = 1
	_air.draw.connect(func(): fx.draw_drops(_air))
	add_child(_air)
	for item in [["ink on sand", Vector2(200, 560)], ["ink on water", Vector2(1380, 120)],
			["dive (you)", Vector2(560, 860)], ["dive (other)", Vector2(1560, 760)],
			["splash", Vector2(1160, 420)], ["splash on sand", Vector2(700, 420)], ["ripples", Vector2(1620, 420)],
			["tide warning: glittering tiles flood next", Vector2(40, 1000)]]:
		var l := Label.new()
		l.text = item[0]
		l.position = item[1]
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color("2B3A4A"))
		l.add_theme_constant_override("outline_size", 8)
		l.add_theme_font_size_override("font_size", 26)
		l.z_index = 2
		add_child(l)


func _process(delta: float) -> void:
	_t += delta
	_next_splash -= delta
	if _next_splash <= 0.0:
		_next_splash = 0.6
		fx.splash(Vector2(1240, 540), 1.6)
		fx.splash(Vector2(780, 540), 1.2, Color("C9A26B"))
		fx.ripple(Vector2(1700, 560 + fmod(_t * 60.0, 120.0)))
	fx.update(delta)
	_ground.queue_redraw()
	_air.queue_redraw()


func _draw_ground() -> void:
	FxDraw.ink_cloud(_ground, Vector2(300, 700), 150.0, _t, 1.0, _ink)
	FxDraw.ink_cloud(_ground, Vector2(1500, 280), 150.0, _t, 1.0, _ink)
	var p := fmod(_t, 1.5) / 1.5
	FxDraw.dive_marker(_ground, Vector2(660, 960), 110.0, p, ME, _t)
	FxDraw.dive_marker(_ground, Vector2(1660, 900), 110.0, maxf(p, 0.6), FOE, _t)
	fx.draw_rings(_ground)
