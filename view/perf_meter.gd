class_name PerfMeter
extends Node
## Frame-time measurement (phase 9c): a rolling window of frame times with average and p95 (the slow frames you feel),
## plus Godot's draw calls and node count. Shown as an overlay with F3 or the debug entry perf=1; the match's debug
## fps log uses the same numbers, so CI's smoke output carries them too.

const WINDOW := 240 # frames (4 s at 60 fps)

var _times := PackedFloat32Array()
var _label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color("2B3A4A"))
	_label.add_theme_constant_override("outline_size", 6)
	_label.position = Vector2(12, 1080 - 120)
	_label.visible = str(Boot.args.get("perf", "")) == "1"
	layer.add_child(_label)


func _process(delta: float) -> void:
	add(delta)
	if _label.visible and Engine.get_process_frames() % 15 == 0:
		_label.text = summary_text()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		_label.visible = not _label.visible


func add(delta: float) -> void:
	_times.append(delta * 1000.0)
	if _times.size() > WINDOW:
		_times = _times.slice(_times.size() - WINDOW)


## {avg_ms, p95_ms, fps} over the window (pure, tested).
func stats() -> Dictionary:
	if _times.is_empty():
		return {"avg_ms": 0.0, "p95_ms": 0.0, "fps": 0.0}
	var sorted := _times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in _times:
		total += t
	var avg := total / _times.size()
	return {"avg_ms": avg, "p95_ms": sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * 0.95)) - 1)], "fps": 1000.0 / maxf(0.001, avg)}


func summary_text() -> String:
	var s := stats()
	return "%d fps · %.1f ms avg · %.1f ms p95 · %d draw calls · %d nodes" % [
		roundi(s.fps), s.avg_ms, s.p95_ms,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))]
