class_name TouchControls
extends Control
## Phone controls (FO §5): the left half is a floating joystick (appears where the thumb lands), bottom right is the
## attack button (hold = auto-aim and fire), the special button sits above it (a normal Button, see match_view).
## Every finger keeps its own role by its touch index, so moving and attacking work at the same time.
## Positions are in this control's own coordinates (it fills the HUD, which sits inside the safe area).

const DEAD := 18.0 # px: a resting thumb doesn't walk
const RADIUS := 120.0 # px: full speed at this distance
const ATTACK_RADIUS := 115.0 # px; >= 48 dp at any phone density

var move := Vector2.ZERO # length 0..1
var attacking := false
var blocked: Array[Control] = [] # touches starting on these (e.g. the special button) are left to them

var _move_index := -1
var _attack_index := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE # buttons on top keep working; we read touches in _input


func attack_center() -> Vector2:
	return Vector2(size.x - 60.0 - ATTACK_RADIUS, size.y - 50.0 - ATTACK_RADIUS)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		handle(make_input_local(event))


## The whole touch logic (also driven by tests with made-up events).
func handle(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if pos.distance_to(attack_center()) <= ATTACK_RADIUS * 1.15 and _attack_index == -1:
				_attack_index = event.index
				attacking = true
			elif _is_blocked(pos):
				pass
			elif pos.x < size.x * 0.5 and _move_index == -1:
				_move_index = event.index
				_origin = pos
				_knob = pos
				move = Vector2.ZERO
		else:
			if event.index == _move_index:
				_move_index = -1
				move = Vector2.ZERO
			if event.index == _attack_index:
				_attack_index = -1
				attacking = false
		queue_redraw()
	elif event is InputEventScreenDrag and event.index == _move_index:
		var d: Vector2 = (event.position - _origin).limit_length(RADIUS)
		_knob = _origin + d
		move = d / RADIUS if d.length() > DEAD else Vector2.ZERO
		queue_redraw()


func _is_blocked(pos: Vector2) -> bool:
	for c in blocked:
		if is_instance_valid(c) and c.visible and Rect2(c.global_position - global_position, c.size).has_point(pos):
			return true
	return false


func _draw() -> void:
	var ink := Color("2B3A4A")
	if _move_index != -1:
		draw_circle(_origin, RADIUS, Color(1, 1, 1, 0.16))
		draw_arc(_origin, RADIUS, 0, TAU, 48, Color(ink, 0.5), 5.0)
		draw_circle(_knob, 46.0, Color(ink, 0.55))
		draw_circle(_knob, 40.0, Color(1, 1, 1, 0.85))
	var c := attack_center()
	draw_circle(c, ATTACK_RADIUS, Color("FF8A3D", 0.95 if attacking else 0.75))
	draw_arc(c, ATTACK_RADIUS, 0, TAU, 64, ink, 6.0)
	# a pointing hand reads as "this one!": disguise as it, or tap it (no text needed)
	draw_circle(c + Vector2(-8, 18), 30.0, ink)
	draw_circle(c + Vector2(-8, 18), 23.0, Color.WHITE)
	draw_rect(Rect2(c + Vector2(-12, -48), Vector2(22, 60)), ink)
	draw_rect(Rect2(c + Vector2(-6, -42), Vector2(10, 52)), Color.WHITE)
