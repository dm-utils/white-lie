class_name SafeArea
extends RefCounted
## Insets that keep the HUD out of notches and rounded corners (styleguide). Godot reports the safe area in screen
## pixels; we turn it into viewport units. On desktop it is the whole window (zero insets).
## Debug entry: safe=left,top,right,bottom (viewport px), to see a phone layout on a PC.


## {left, top, right, bottom} in viewport units.
static func insets(viewport_size: Vector2) -> Dictionary:
	if Boot.args.has("safe"):
		return parse(str(Boot.args.safe))
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0 or win.y <= 0:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var safe := DisplayServer.get_display_safe_area()
	return from_rects(Rect2(safe), win, viewport_size)


## The safe rect (screen px) inside a window of win px, as insets in viewport units (pure, tested).
static func from_rects(safe: Rect2, win: Vector2, viewport_size: Vector2) -> Dictionary:
	if safe.size.x <= 0 or safe.size.y <= 0:
		return {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var k := viewport_size / win
	return {
		"left": maxf(0.0, safe.position.x) * k.x,
		"top": maxf(0.0, safe.position.y) * k.y,
		"right": maxf(0.0, win.x - safe.end.x) * k.x,
		"bottom": maxf(0.0, win.y - safe.end.y) * k.y,
	}


static func parse(text: String) -> Dictionary:
	var p := text.split(",")
	var v := func(i: int) -> float: return float(p[i]) if p.size() > i else 0.0
	return {"left": v.call(0), "top": v.call(1), "right": v.call(2), "bottom": v.call(3)}


## Applies the insets to a full-rect control (the HUD root).
static func apply(c: Control) -> void:
	var i := insets(c.get_viewport_rect().size)
	c.offset_left = i.left
	c.offset_top = i.top
	c.offset_right = -i.right
	c.offset_bottom = -i.bottom
