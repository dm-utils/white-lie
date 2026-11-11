class_name Content
extends RefCounted
## Content is data: characters, maps, props, rules live in res://data/*.json. Pure loader, no nodes.


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("missing data file: " + path)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func characters() -> Array:
	var d: Variant = load_json("res://data/characters.json")
	if typeof(d) != TYPE_DICTIONARY:
		return []
	return d.get("characters", [])


static func character(id: String) -> Dictionary:
	for c in characters():
		if c.get("id", "") == id:
			return c
	return {}
