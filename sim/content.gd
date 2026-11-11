class_name Content
extends RefCounted
## Content is data: animals, islands, the path, achievements live in res://data/*.json.
## Pure loader, no nodes.


static func load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("missing data file: " + path)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func animals() -> Array:
	var d: Variant = load_json("res://data/animals.json")
	if typeof(d) != TYPE_DICTIONARY:
		return []
	return d.get("animals", [])


static func animal(id: String) -> Dictionary:
	for a in animals():
		if a.get("id", "") == id:
			return a
	return {}
