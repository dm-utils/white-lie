extends Node
## Debug entry point: start straight into a scene with a seed. Makes every test and agent faster.
##   Desktop: godot --path . -- --scene=hide --seed=123
##   Web:     index.html?scene=hide&seed=123

const SCENES := {
	"menu": "res://ui/main_menu.tscn",
	"settings": "res://ui/settings_screen.tscn",
	"online": "res://ui/online_screen.tscn",
	"hide": "res://view/hide_view.tscn",
}

var args: Dictionary = {}
## Handed from the match to the result screen.
var last_result: Dictionary = {}
## Handed from the menu to the match (e.g. the daily challenge): {seed, animal, bots, daily}. Taken once.
var next_match: Dictionary = {}


func _ready() -> void:
	args = parse(OS.get_cmdline_user_args())
	if OS.has_feature("web"):
		var query: Variant = JavaScriptBridge.eval("location.search", true)
		if query != null:
			args.merge(parse_query(str(query)), true)


static func parse(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--") and "=" in a:
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


static func parse_query(query: String) -> Dictionary:
	var out := {}
	for part in query.trim_prefix("?").split("&", false):
		var kv := part.split("=", true, 1)
		if kv.size() == 2:
			out[kv[0].uri_decode()] = kv[1].uri_decode()
	return out


func debug_scene() -> String:
	return SCENES.get(args.get("scene", ""), "")


func seed_value() -> int:
	return int(args.get("seed", "0"))
