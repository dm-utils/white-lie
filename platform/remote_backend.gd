extends "res://platform/local_backend.gd"
## Local-first backend with cloud sync through the St33f Engine.
## The game always plays from the local profile (offline works). When signed in, every save is also marked
## dirty for the St33f profile sync, which pushes a few seconds later and merges on conflicts (ProfileMerge).
## After sign-in, the cloud copy is pulled once and merged into the local one.

var _st33f: Node


func _init(st33f: Node) -> void:
	_st33f = st33f
	_st33f.profile_sync.merge = Callable(ProfileMerge, "merge")
	_st33f.signed_in.connect(_on_signed_in)


func is_signed_in() -> bool:
	return _st33f.is_signed_in()


## Server value when known (last fetched, also from disk), else the game's declared default.
func get_config(key: String, default_value: Variant) -> Variant:
	return _st33f.get_setting(key, super.get_config(key, default_value))


func save_profile(p: Dictionary) -> void:
	super.save_profile(p)
	if _st33f.is_signed_in():
		_st33f.profile_sync.mark_dirty(p)


## Pull the cloud copy, merge it into the local one, save, and push the result back.
func _on_signed_in(_user_id: String) -> void:
	var res: Dictionary = await _st33f.profile_sync.pull()
	_st33f.handle_result(res)
	if not res.ok:
		return
	var server: Variant = res.data.get("profile")
	var local := load_profile()
	var merged := ProfileMerge.merge(local, server if typeof(server) == TYPE_DICTIONARY else {})
	save_profile(merged)
