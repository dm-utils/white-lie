extends Control
## White Lie main menu: title, play against bots, play online, settings. Meta screens (collection, season) come in
## phase 5 on the same building blocks.


func _ready() -> void:
	theme = UiTheme.get_theme()
	Platform.entered("menu")
	var bg := TextureRect.new()
	bg.texture = UiTheme.sky_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var version := Label.new()
	version.text = tr("MENU_VERSION").format({"version": str(ProjectSettings.get_setting("application/config/version", "0.1.0"))})
	add_child(version)
	version.position = Vector2(40, 30)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var title := Label.new()
	title.text = tr("TITLE")
	title.label_settings = UiTheme.heading(150)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var who := Button.new()
	who.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	who.custom_minimum_size = Vector2(460, 0)
	who.text = _who_text()
	who.pressed.connect(func() -> void:
		var p: Dictionary = Platform.load_profile()
		p["selected_character"] = next_character(p)
		Platform.save_profile(p)
		who.text = _who_text())
	box.add_child(who)
	for key in ["MENU_PLAY", "MENU_ONLINE", "MENU_SETTINGS"]:
		var b := Button.new()
		b.text = tr(key)
		b.custom_minimum_size = Vector2(460, 0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if key == "MENU_PLAY":
			b.theme_type_variation = "PlayButton"
		b.pressed.connect(_open.bind({"MENU_PLAY": "hide", "MENU_ONLINE": "online", "MENU_SETTINGS": "settings"}[key]))
		box.add_child(b)


func _who_text() -> String:
	var p: Dictionary = Platform.load_profile()
	var c := Content.character(str(p.get("selected_character", "skipper")))
	return tr("MENU_CHARACTER").format({"name": tr(str(c.get("name_key", "CHAR_SKIPPER")))})


## The next character you may play (skipper always; the rest once unlocked on the path), wrapping round.
static func next_character(p: Dictionary) -> String:
	var owned: Array = ["skipper"] + (p.get("unlocked_characters", []) as Array)
	var all: Array = Content.characters().map(func(c): return str(c.id)).filter(func(id): return owned.has(id))
	var i := all.find(str(p.get("selected_character", "skipper")))
	return all[(i + 1) % all.size()]


func _open(scene: String) -> void:
	get_tree().change_scene_to_file(Boot.SCENES[scene])
