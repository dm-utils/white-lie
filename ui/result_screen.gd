extends Control
## After a session: place, points and pearls. Saves through Platform, so the cloud copy follows when signed in.


func _ready() -> void:
	theme = UiTheme.get_theme()
	Platform.entered("result")
	var bg := TextureRect.new()
	bg.texture = UiTheme.sky_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var r: Dictionary = Boot.last_result if not Boot.last_result.is_empty() else {"place": 3, "points": 20, "character": "skipper"}
	var outcome := apply_result(r)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 22)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(_label(tr("RESULT_PLACE").format({"place": r.place}), UiTheme.heading(200)))
	box.add_child(_label(tr("RESULT_POINTS").format({"points": int(r.get("points", 0))}), UiTheme.heading(56, UiTheme.INK, 0)))
	box.add_child(_label(tr("RESULT_PEARLS").format({"count": outcome.earned}), UiTheme.heading(44, UiTheme.GOLD, 8)))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	box.add_child(row)
	var again := Button.new()
	again.text = tr("RESULT_AGAIN")
	again.theme_type_variation = "PlayButton"
	again.pressed.connect(func() -> void: get_tree().change_scene_to_file(Boot.SCENES["hide"]))
	row.add_child(again)
	var menu := Button.new()
	menu.text = tr("RESULT_MENU")
	menu.pressed.connect(func() -> void: get_tree().change_scene_to_file(Boot.SCENES["menu"]))
	row.add_child(menu)


func _label(text: String, settings: LabelSettings) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.label_settings = settings
	return l


## Pure bookkeeping, also used by tests: pearls for the place, stats, mastery per character.
static func apply_result(r: Dictionary) -> Dictionary:
	var path: Dictionary = Content.load_json("res://data/path.json")
	var table: Array = path.pearls_for_place
	var earned := int(table[clampi(int(r.place), 1, table.size() - 1)])
	var p: Dictionary = Platform.load_profile()
	var before := int(p.get("pearls_total", 0))
	p["pearls_total"] = before + earned
	var stats: Dictionary = p.get("stats", {})
	stats["matches"] = int(stats.get("matches", 0)) + 1
	stats["wins"] = int(stats.get("wins", 0)) + (1 if int(r.place) == 1 else 0)
	p["stats"] = stats
	var mastery: Dictionary = p.get("mastery", {})
	var mine: Dictionary = mastery.get(str(r.get("character", "")), {})
	mine["matches"] = int(mine.get("matches", 0)) + 1
	mine["wins"] = int(mine.get("wins", 0)) + (1 if int(r.place) == 1 else 0)
	mastery[str(r.get("character", ""))] = mine
	p["mastery"] = mastery
	Platform.save_profile(p)
	return {"earned": earned, "before": before, "after": before + earned}
