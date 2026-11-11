class_name SimRng
extends RefCounted
## xorshift32: tiny, fast and identical in GDScript and C++. The whole sim (and the bots) draw from one instance,
## so the same seed and the same commands always replay the same match.

var state: int


func _init(seed_value: int = 1) -> void:
	state = seed_value & 0xFFFFFFFF
	if state == 0:
		state = 0x9E3779B9


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state = x
	return x


## 0 .. n-1 (n > 0)
func range_i(n: int) -> int:
	return next_u32() % n


## lo .. hi inclusive
func between(lo: int, hi: int) -> int:
	return lo + range_i(hi - lo + 1)
