class_name St33fProfileSync
extends RefCounted
## Cloud save sync. Play offline freely: the game marks the profile dirty after a change and we push
## a few seconds after the last change (debounce). A stale write gets 409 with the server copy; the game's
## deterministic merge (max of counters, union of unlocks, last-writer-wins only for settings) combines both
## and we retry, up to `max_merges` times.

signal synced(profile: Dictionary, version: int)
signal merged(profile: Dictionary)

var client: St33fClient
## func(local: Dictionary, server: Dictionary) -> Dictionary
var merge: Callable
var debounce_s := 3.0
var max_merges := 3
## Server version we last saw. Persisted by the owner (St33f autoload) between runs.
var version := 0
var dirty := false

var _pending: Dictionary = {}
var _timer := 0.0
var _busy := false


func _init(p_client: St33fClient, p_merge: Callable) -> void:
	client = p_client
	merge = p_merge


func mark_dirty(profile: Dictionary) -> void:
	_pending = profile.duplicate(true)
	dirty = true
	_timer = debounce_s


func is_busy() -> bool:
	return _busy


## Call every frame (the autoload does). Pushes once the debounce ran out.
func tick(delta: float) -> void:
	if not dirty or _busy:
		return
	_timer -= delta
	if _timer <= 0.0:
		push_now()


func push_now() -> Dictionary:
	if _busy:
		return {"ok": false, "status": 0, "data": {}, "error": St33fError.new(0, "busy")}
	_busy = true
	dirty = false
	var profile := _pending
	var res: Dictionary = {}
	for attempt in max_merges + 1:
		res = await client.put_profile(profile, version)
		if res.ok:
			version = int(res.data.get("version", version + 1))
			synced.emit(profile, version)
			break
		var e: St33fError = res.error
		if e.status == 409 and attempt < max_merges:
			var server: Variant = res.data.get("profile")
			version = int(res.data.get("version", 0))
			profile = merge.call(profile, server if typeof(server) == TYPE_DICTIONARY else {})
			merged.emit(profile)
			continue
		if e.is_transient() and not dirty:
			# keep it for the next tick; newer local changes (dirty again) win over this copy
			_pending = profile
			dirty = true
			_timer = maxf(debounce_s, float(e.retry_after()))
		break
	_busy = false
	return res


## Fetch the server copy (after sign-in). Returns the client result; updates `version`.
func pull() -> Dictionary:
	var res: Dictionary = await client.get_profile()
	if res.ok:
		version = int(res.data.get("version", 0))
	return res
