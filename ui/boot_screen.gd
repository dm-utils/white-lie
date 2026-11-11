extends Control
## Own start screen (no Godot splash). Always moving, so it never reads as frozen.

const MENU := "res://ui/main_menu.tscn"

var _t := 0.0
var _leaving := false
var _tap: Label
var _waves: Control


func _ready() -> void:
	theme = UiTheme.get_theme()
	# let taps fall through to _unhandled_input (a STOP filter on the root would swallow them)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := TextureRect.new()
	bg.texture = UiTheme.sky_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# waves on their own layer: a parent's _draw would sit underneath the background child
	_waves = Control.new()
	_waves.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_waves.draw.connect(_draw_waves)
	add_child(_waves)
	_waves.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title := Label.new()
	title.text = tr("TITLE")
	title.label_settings = UiTheme.heading(220, Color.WHITE, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position.y = 260
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var sub := Label.new()
	sub.text = tr("BOOT_WORKING_TITLE")
	sub.label_settings = UiTheme.heading(40, Color.WHITE, 8)
	add_child(sub)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.position.y = 540
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH

	_tap = Label.new()
	_tap.text = tr("BOOT_TAP")
	_tap.label_settings = UiTheme.heading(52, Color.WHITE, 10)
	add_child(_tap)
	_tap.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tap.position.y -= 150
	_tap.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var target: String = Boot.debug_scene()
	if target != "":
		_go.call_deferred(target)


func _process(delta: float) -> void:
	_t += delta
	_tap.modulate.a = 0.55 + 0.45 * sin(_t * 4.0)
	_waves.queue_redraw()


func _draw_waves() -> void:
	# two rolling waves at the bottom, same motion as the web loader
	var s := _waves.size
	for layer in 2:
		var base := s.y - 90.0 + layer * 45.0
		var pts := PackedVector2Array()
		var x := 0.0
		while x <= s.x + 20.0:
			pts.append(Vector2(x, base + sin(x * 0.012 + _t * (1.6 + layer) + layer) * 14.0))
			x += 20.0
		pts.append(Vector2(s.x, s.y))
		pts.append(Vector2(0, s.y))
		_waves.draw_colored_polygon(pts, UiTheme.DEEP if layer == 1 else UiTheme.SHALLOW)


func _unhandled_input(event: InputEvent) -> void:
	if UiTheme.is_emulated(event):
		return
	var pressed: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if pressed:
		_go(MENU)


func _go(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(path)
