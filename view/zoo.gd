extends Node2D
## Debug scene for art review: every animal and look, in every animation, side by side (scene=zoo).
## Each state retriggers every 1.2 s so a screenshot at any moment shows it. Labels are debug text, not tr().

const STATES := ["idle", "walk", "swim", "attack", "hit", "ko", "win"]
const ROWS := [["crab", ""], ["octopus", ""], ["gull", ""], ["crab", "crab_sunset"], ["octopus", "octopus_midnight"]]

var _cells: Array = []
var _t := 0.0


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("F2D49B")
	bg.size = Vector2(1920, 1080)
	bg.z_index = -100 # parts behind the body (limbs, tentacles) use negative z
	add_child(bg)
	for r in ROWS.size():
		var row: Array = ROWS[r]
		_label(str(row[0]) + (" / " + str(row[1]) if row[1] != "" else ""), Vector2(20, 120 + r * 200))
		for s in STATES.size():
			if r == 0:
				_label(STATES[s], Vector2(260 + s * 235, 20))
			var c := Cutout.new()
			c.size_px = 150.0
			add_child(c)
			c.build(str(row[0]), str(row[1]))
			c.position = Vector2(330 + s * 235, 200 + r * 200)
			c.moving = STATES[s] == "walk"
			c.swimming = STATES[s] == "swim" and row[0] != "gull"
			_cells.append([c, STATES[s]])


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_color_override("font_color", Color("2B3A4A"))
	l.add_theme_font_size_override("font_size", 28)
	add_child(l)


func _process(delta: float) -> void:
	var before := fmod(_t, 1.2)
	_t += delta
	if fmod(_t, 1.2) < before:
		for cell in _cells:
			var c: Cutout = cell[0]
			match str(cell[1]):
				"attack", "hit", "win":
					c.trigger(str(cell[1]))
				"ko":
					c.free_ko_restart()
