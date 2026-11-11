class_name Fx
extends RefCounted
## Integer maths for the sim. Angles 0..4095 (a full turn), direction (cos a, sin a) with y pointing down.
## Values come from data/sin_table.json (generated once), so GDScript and a C++ port give identical results.
## Integer division truncates toward zero in both languages; use posmod for angles.

const ANGLES := 4096
const QUARTER := 1024
const ONE := 1024

static var _sin := PackedInt32Array()
static var _atan := PackedInt32Array()


static func _ensure() -> void:
	if not _sin.is_empty():
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sin_table.json"))
	for v in d.sin:
		_sin.append(int(v))
	for v in d.atan:
		_atan.append(int(v))


static func sin_a(a: int) -> int:
	_ensure()
	return _sin[posmod(a, ANGLES)]


static func cos_a(a: int) -> int:
	return sin_a(a + QUARTER)


## Angle of the vector (dx, dy); 0 for the zero vector.
static func atan2_a(dy: int, dx: int) -> int:
	_ensure()
	if dx == 0 and dy == 0:
		return 0
	var ax := absi(dx)
	var ay := absi(dy)
	var a: int
	if ax >= ay:
		a = _atan[ay * ONE / ax]
	else:
		a = QUARTER - _atan[ax * ONE / ay]
	if dx < 0:
		a = ANGLES / 2 - a
	if dy < 0:
		a = ANGLES - a
	return posmod(a, ANGLES)


## Floor of the square root (Newton's method on integers).
static func isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var x := n
	var y := (x + 1) / 2
	while y < x:
		x = y
		y = (x + n / x) / 2
	return x


static func dist(dx: int, dy: int) -> int:
	return isqrt(dx * dx + dy * dy)


## Shortest signed difference between two angles (-2048..2047).
static func angle_diff(a: int, b: int) -> int:
	return posmod(a - b + ANGLES / 2, ANGLES) - ANGLES / 2
