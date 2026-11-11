extends RefCounted
## Local-only backend: everything lives under user://. Same interface the remote backend will have.
## Profile = an opaque, versioned JSON blob (no Godot objects, no node paths).
##   format  = layout of the blob (migrated in code)
##   version = write counter; the server uses it for 409 conflict detection later

const PROFILE_FORMAT := 1

var profile_path := "user://profile.json"
var results_path := "user://results.json"
var crash_path := "user://crashes.log"
var config_path := "res://data/settings_defs.json"

var _config: Dictionary = {}


func is_signed_in() -> bool:
	return false


func default_profile() -> Dictionary:
	return {
		"format": PROFILE_FORMAT,
		"version": 0,
		"updated_at": "",
		"pearls_total": 0,
		"unlocked_animals": ["crab", "octopus", "gull"],
		"selected_animal": "octopus",
		"achievements": {},
		"stats": {"matches": 0, "wins": 0, "knockouts": 0},
		"settings": {},
	}


func load_profile() -> Dictionary:
	var data: Variant = _read_json(profile_path)
	if typeof(data) != TYPE_DICTIONARY:
		return default_profile()
	return migrate(data)


func migrate(p: Dictionary) -> Dictionary:
	var d := default_profile()
	for k in d:
		if not p.has(k):
			p[k] = d[k]
	p["format"] = PROFILE_FORMAT
	return p


func save_profile(p: Dictionary) -> void:
	p["version"] = int(p.get("version", 0)) + 1
	p["updated_at"] = Time.get_datetime_string_from_system(true) + "Z"
	_write_json(profile_path, p)


func unlock_achievement(id: String, tier: int) -> void:
	var p := load_profile()
	var current := int(p["achievements"].get(id, 0))
	if tier > current:
		p["achievements"][id] = tier
		save_profile(p)


func submit_result(board: String, result: Dictionary, _replay: Dictionary) -> void:
	var all: Variant = _read_json(results_path)
	if typeof(all) != TYPE_DICTIONARY:
		all = {}
	var best := int(all.get(board, {}).get("score", -1))
	if int(result.get("score", 0)) > best:
		all[board] = result
		_write_json(results_path, all)


## Local defaults from the game's own declarations (data/settings_defs.json).
func get_config(key: String, default_value: Variant) -> Variant:
	if _config.is_empty():
		var c: Variant = _read_json(config_path)
		if typeof(c) == TYPE_DICTIONARY:
			for d in c.get("defs", []):
				_config[str(d.key)] = d.default
	return _config.get(key, default_value)


func report_crash(message: String, stack: Array) -> void:
	var f := FileAccess.open(crash_path, FileAccess.READ_WRITE if FileAccess.file_exists(crash_path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify({"at": Time.get_datetime_string_from_system(true), "message": message, "stack": stack}))


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("write failed: %s (%d)" % [path, FileAccess.get_open_error()])
		return
	# full_precision: JSON that a sim or server reads must not be rounded
	f.store_string(JSON.stringify(data, "  ", true, true))
