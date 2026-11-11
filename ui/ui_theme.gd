class_name UiTheme
extends RefCounted
## Styleguide colours and fonts in one place (STYLEGUIDE.md §3, §7).

const INK := Color("2B3A4A")
const PAPER := Color("FFF6E3")
const ORANGE := Color("FF8A3D")
const BLUE := Color("3FA7D6")
const SKY := Color("7FD8F0")
const SAND := Color("F2D49B")
const SHALLOW := Color("5FD3C9")
const DEEP := Color("1F6F9F")
const FOAM := Color("F7FBF8")
const GOLD := Color("FFC530")

static var _theme: Theme
static var _title_font: Font
static var _body_font: Font


static func title_font() -> Font:
	if _title_font == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Fredoka-Variable.ttf")
		fv.variation_opentype = {_tag("wght"): 600}
		_title_font = fv
	return _title_font


static func body_font() -> Font:
	if _body_font == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://assets/fonts/Nunito-Variable.ttf")
		fv.variation_opentype = {_tag("wght"): 700}
		_body_font = fv
	return _body_font


## Variable-font axes need the numeric OpenType tag; a plain string key is silently ignored.
static func _tag(axis: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(axis)


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 32

	t.set_font("font", "Button", title_font())
	t.set_font_size("font_size", "Button", 40)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "Button", INK)
	t.set_color("font_disabled_color", "Button", Color(INK, 0.45))
	t.set_stylebox("normal", "Button", _box(PAPER, 10))
	t.set_stylebox("hover", "Button", _box(PAPER.lightened(0.3), 10))
	t.set_stylebox("pressed", "Button", _box(PAPER.darkened(0.06), 4))
	t.set_stylebox("disabled", "Button", _box(PAPER.darkened(0.08), 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	# PlayButton: the one big orange button (STYLEGUIDE §3 UI)
	t.set_type_variation("PlayButton", "Button")
	t.set_font_size("font_size", "PlayButton", 72)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "PlayButton", Color.WHITE)
	t.set_color("font_outline_color", "PlayButton", INK)
	t.set_constant("outline_size", "PlayButton", 6)
	t.set_stylebox("normal", "PlayButton", _box(ORANGE, 12))
	t.set_stylebox("hover", "PlayButton", _box(ORANGE.lightened(0.1), 12))
	t.set_stylebox("pressed", "PlayButton", _box(ORANGE.darkened(0.08), 4))

	t.set_type_variation("BlueButton", "Button")
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(state, "BlueButton", Color.WHITE)
	t.set_stylebox("normal", "BlueButton", _box(BLUE, 10))
	t.set_stylebox("hover", "BlueButton", _box(BLUE.lightened(0.1), 10))
	t.set_stylebox("pressed", "BlueButton", _box(BLUE.darkened(0.08), 4))

	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", _box(PAPER, 6))

	# text fields: white with an ink border (styleguide §7), readable placeholder
	for type in ["LineEdit", "TextEdit"]:
		var field := _box(Color.WHITE, 6)
		field.set_corner_radius_all(16)
		field.content_margin_left = 20
		field.content_margin_right = 20
		field.content_margin_top = 10
		field.content_margin_bottom = 10
		var focus := field.duplicate()
		focus.border_color = BLUE
		t.set_stylebox("normal", type, field)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("read_only", type, field)
		t.set_color("font_color", type, INK)
		t.set_color("font_placeholder_color", type, Color(INK, 0.45))
		t.set_color("caret_color", type, INK)
		t.set_color("selection_color", type, Color(BLUE, 0.35))

	# check boxes: no button frame, just the box and the text
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	t.set_font("font", "CheckBox", body_font())
	t.set_font_size("font_size", "CheckBox", 32)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "CheckBox", INK)
	t.set_constant("h_separation", "CheckBox", 16)
	_theme = t
	return t


static func _box(fill: Color, depth: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = INK
	s.set_border_width_all(6)
	s.border_width_bottom = depth
	s.set_corner_radius_all(32)
	s.content_margin_left = 36
	s.content_margin_right = 36
	s.content_margin_top = 14
	s.content_margin_bottom = 14 + depth - 6
	return s


static func heading(size: int, color: Color = Color.WHITE, outline: int = 12) -> LabelSettings:
	var ls := LabelSettings.new()
	ls.font = title_font()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = outline
	ls.outline_color = INK
	ls.shadow_size = 0
	ls.shadow_color = INK
	ls.shadow_offset = Vector2(0, size * 0.06)
	return ls


static func sky_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, SKY)
	g.set_color(1, SAND)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 256
	return tex


## Touch helpers (GAME_STARTER_PROMPT "Touch and phones"):
## ignore mouse events that Godot emulates from touch, or every tap fires twice.
static func is_emulated(event: InputEvent) -> bool:
	return event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION
