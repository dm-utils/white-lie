class_name PlayerName
extends RefCounted
## Player names (FO §8): adjective + noun + number from data/names.json, e.g. "Swift Otter 42" / "Snelle Otter 42".
## Stored as {a, n, num} (list positions), so the server never holds free text and everyone reads the name in their
## own language. Lists may only grow at the end (data/names.json says so).


static func lists() -> Dictionary:
	return Content.load_json("res://data/names.json")


static func random(rng: RandomNumberGenerator = null) -> Dictionary:
	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	var l := lists()
	return {"a": r.randi_range(0, l.adjectives.size() - 1), "n": r.randi_range(0, l.nouns.size() - 1), "num": r.randi_range(1, 99)}


static func valid(name: Variant) -> bool:
	if not name is Dictionary:
		return false
	var l := lists()
	return int(name.get("a", -1)) >= 0 and int(name.get("a", -1)) < l.adjectives.size() \
		and int(name.get("n", -1)) >= 0 and int(name.get("n", -1)) < l.nouns.size() \
		and int(name.get("num", 0)) >= 1 and int(name.get("num", 0)) <= 99


## The name as text in the current language; an unknown index (newer game version) still gives a readable name.
static func text(name: Variant) -> String:
	if not name is Dictionary:
		return ""
	var l := lists()
	var a := int(name.get("a", 0))
	var n := int(name.get("n", 0))
	var adj: String = TranslationServer.translate("NAME_ADJ_" + str(l.adjectives[a])) if a >= 0 and a < l.adjectives.size() else "?"
	var noun: String = TranslationServer.translate("NAME_NOUN_" + str(l.nouns[n])) if n >= 0 and n < l.nouns.size() else "?"
	return str(TranslationServer.translate("NAME_FORMAT")).format({"adjective": adj, "noun": noun, "number": int(name.get("num", 0))})


## The profile's name, made on first use (kept in the profile, so it travels with the cloud save).
static func ensure(profile: Dictionary) -> Dictionary:
	if not valid(profile.get("name")):
		profile["name"] = random()
	return profile.name
