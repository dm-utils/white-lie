class_name ProfileMerge
extends RefCounted
## Deterministic merge of two profiles (local and server) after a 409:
##   counters        -> max          (pearls, stats, mastery, write counter)
##   unlocks         -> union        (animals, owned looks, badges, avatars), sorted
##   seasons         -> max per season (pearls)
##   achievements    -> max tier per id
##   choices         -> last writer wins by updated_at (selected animal, equipped looks, settings, name)
## Same inputs always give the same result, so two devices converge.


static func merge(local: Dictionary, server: Dictionary) -> Dictionary:
	if server.is_empty():
		return local.duplicate(true)
	if local.is_empty():
		return server.duplicate(true)
	var newer: Dictionary = local if str(local.get("updated_at", "")) > str(server.get("updated_at", "")) else server
	var out := newer.duplicate(true)

	for k in ["pearls_total", "format", "version"]:
		out[k] = maxi(int(local.get(k, 0)), int(server.get(k, 0)))

	out["unlocked_animals"] = _union(local.get("unlocked_animals", []), server.get("unlocked_animals", []))
	out["stats"] = _max_each(local.get("stats", {}), server.get("stats", {}))
	out["achievements"] = _max_each(local.get("achievements", {}), server.get("achievements", {}))

	var mastery := {}
	var lm: Dictionary = local.get("mastery", {})
	var sm: Dictionary = server.get("mastery", {})
	for id in _union(lm.keys(), sm.keys()):
		mastery[id] = _max_each(lm.get(id, {}), sm.get(id, {}))
	if not mastery.is_empty():
		out["mastery"] = mastery

	if local.has("looks") or server.has("looks"):
		var looks: Dictionary = (newer.get("looks", {}) as Dictionary).duplicate(true)
		looks["owned"] = _union(local.get("looks", {}).get("owned", []), server.get("looks", {}).get("owned", []))
		out["looks"] = looks

	for k in ["badges", "avatars"]:
		if local.has(k) or server.has(k):
			out[k] = _union(local.get(k, []), server.get(k, []))
	if local.has("seasons") or server.has("seasons"):
		var seasons := {}
		var ls: Dictionary = local.get("seasons", {})
		var ss: Dictionary = server.get("seasons", {})
		for id in _union(ls.keys(), ss.keys()):
			seasons[id] = _max_each(ls.get(id, {}), ss.get(id, {}))
		out["seasons"] = seasons

	# a newer copy without a name (a fresh device) must not drop the name the player already has
	if not out.has("name"):
		var older: Dictionary = server if newer == local else local
		if older.has("name"):
			out["name"] = older.name

	# a selected animal must be one we own
	if not (out["unlocked_animals"] as Array).has(out.get("selected_animal", "")) and not (out["unlocked_animals"] as Array).is_empty():
		out["selected_animal"] = out["unlocked_animals"][0]
	return out


static func _union(a: Array, b: Array) -> Array:
	var seen := {}
	for x in a + b:
		seen[str(x)] = true
	var keys := seen.keys()
	keys.sort()
	return keys


static func _max_each(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	for k in _union(a.keys(), b.keys()):
		out[k] = maxi(int(a.get(k, 0)), int(b.get(k, 0)))
	return out
