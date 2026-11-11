class_name PublicProfile
extends RefCounted
## What other players may see (FO §8 "profielen bekijken"): name, favourite animal, mastery badges and collection.
## Sent to the leaderboards service when signed in, and only when it changed (hash kept on this device).

const HASH_PATH := "user://st33f/public_profile.hash"


static func from(profile: Dictionary) -> Dictionary:
	var p := profile.duplicate(true)
	return {
		"name": PlayerName.ensure(p),
		"animal": str(p.get("selected_animal", "octopus")),
		"badges": Mastery.badges(p),
		"collection": p.get("unlocked_animals", []),
	}


## Publish if signed in and changed. Safe to call often (after a match, a name change, signing in).
static func publish(force := false) -> void:
	if St33f.client == null or not St33f.is_signed_in():
		return
	var profile: Dictionary = Platform.load_profile()
	if not PlayerName.valid(profile.get("name")):
		PlayerName.ensure(profile)
		Platform.save_profile(profile)
	var body := from(profile)
	var h := str(JSON.stringify(body).hash())
	if not force and FileAccess.file_exists(HASH_PATH) and FileAccess.get_file_as_string(HASH_PATH) == h:
		return
	var res: Dictionary = await St33f.client.put_public_profile(body)
	if res.ok:
		DirAccess.make_dir_recursive_absolute(HASH_PATH.get_base_dir())
		var f := FileAccess.open(HASH_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(h)
