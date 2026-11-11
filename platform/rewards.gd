class_name Rewards
extends RefCounted
## Granting rewards from any path (Treasure Path, season path) into the profile. One place, so every kind is kept:
##   animal -> unlocked_animals · look -> looks.owned · badge -> badges · avatar -> avatars
## Looks, badges and avatars are for show only; nothing here gives power (FO §7).


static func grant(profile: Dictionary, rew: Dictionary) -> void:
	var id := str(rew.get("id", ""))
	match str(rew.get("kind", "")):
		"animal":
			_add(profile, "unlocked_animals", id)
		"look":
			var looks: Dictionary = profile.get("looks", {})
			var owned: Array = looks.get("owned", [])
			if not owned.has(id):
				owned.append(id)
			looks["owned"] = owned
			profile["looks"] = looks
		"badge":
			_add(profile, "badges", id)
		"avatar":
			_add(profile, "avatars", id)


static func _add(profile: Dictionary, key: String, id: String) -> void:
	var list: Array = profile.get(key, [])
	if not list.has(id):
		list.append(id)
	profile[key] = list


## Walks a path's rewards for a pearl count going from before to after: {unlocked, next, prev_at}.
static func walk(rewards: Array, before: int, after: int) -> Dictionary:
	var unlocked: Array = []
	var next: Dictionary = {}
	var prev_at := 0
	for rew in rewards:
		if int(rew.at) > before and int(rew.at) <= after:
			unlocked.append(rew)
		if int(rew.at) <= after:
			prev_at = int(rew.at)
		elif next.is_empty():
			next = rew
	return {"unlocked": unlocked, "next": next, "prev_at": prev_at}


## Looks: which look an animal wears (equipped and owned), "" = the standard colours.
static func equipped_look(profile: Dictionary, animal: String) -> String:
	var looks: Dictionary = profile.get("looks", {})
	var look := str((looks.get("equipped", {}) as Dictionary).get(animal, ""))
	return look if (looks.get("owned", []) as Array).has(look) else ""


static func equip(profile: Dictionary, animal: String, look: String) -> void:
	var looks: Dictionary = profile.get("looks", {})
	var eq: Dictionary = looks.get("equipped", {})
	if look == "":
		eq.erase(animal)
	else:
		eq[animal] = look
	looks["equipped"] = eq
	profile["looks"] = looks
