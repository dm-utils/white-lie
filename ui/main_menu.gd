extends Control
## Main menu skeleton: two taps to play (FO §2). Real screens arrive in phase 3+.

var _toast: Label
var _toast_t := 0.0
var _daily: Button
var _daily_busy := false


func _ready() -> void:
	theme = UiTheme.get_theme()
	Platform.entered("menu")
	var bg := TextureRect.new()
	bg.texture = UiTheme.sky_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var profile: Dictionary = Platform.load_profile()
	var animal := Content.animal(str(profile.get("selected_animal", "octopus")))

	# left menu
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 22)
	add_child(menu)
	menu.position = Vector2(60, 200)
	menu.custom_minimum_size = Vector2(420, 0)
	for key in ["MENU_ONLINE", "MENU_BALL", "MENU_COLLECTION", "MENU_PATH", "MENU_LEADERBOARD", "MENU_PROFILE", "MENU_SETTINGS"]:
		var b := Button.new()
		b.text = tr(key)
		if key == "MENU_SETTINGS":
			b.pressed.connect(func() -> void: get_tree().change_scene_to_file(Boot.SCENES["settings"]))
		elif key == "MENU_ONLINE":
			b.pressed.connect(func() -> void: get_tree().change_scene_to_file(Boot.SCENES["online"]))
		elif key == "MENU_BALL":
			b.pressed.connect(func() -> void:
				Boot.next_match = {"mode": "ball"}
				get_tree().change_scene_to_file(Boot.SCENES["match"]))
		elif key == "MENU_COLLECTION":
			b.pressed.connect(func() -> void: get_tree().change_scene_to_file(Boot.SCENES["collection"]))
		elif key == "MENU_LEADERBOARD":
			b.pressed.connect(func() -> void: get_tree().change_scene_to_file(Boot.SCENES["leaderboard"]))
		else:
			b.pressed.connect(_soon)
		menu.add_child(b)

	# centre: the selected animal, big and breathing on a little shadow
	var shadow := Panel.new()
	var shadow_box := StyleBoxFlat.new()
	shadow_box.bg_color = Color(UiTheme.INK, 0.18)
	shadow_box.set_corner_radius_all(60)
	shadow.add_theme_stylebox_override("panel", shadow_box)
	shadow.size = Vector2(260, 44)
	shadow.position = Vector2(960 - 130, 640 - 22)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shadow)
	var hero := Cutout.new()
	hero.size_px = 380.0
	hero.z_index = 5 # parts behind the body use negative z: keep them above the background
	add_child(hero)
	hero.build(str(animal.get("id", "octopus")), Rewards.equipped_look(profile, str(animal.get("id", "octopus"))))
	hero.position = Vector2(960, 650)

	var name_label := Label.new()
	name_label.text = tr(str(animal.get("name_key", "")))
	name_label.label_settings = UiTheme.heading(64, UiTheme.INK, 0)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name_label)
	name_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	name_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	name_label.position.y -= 330

	var count := Label.new()
	count.text = tr("MENU_ANIMALS_LOADED").format({"count": Content.animals().size()})
	add_child(count)
	count.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	count.position.y -= 260
	count.grow_horizontal = Control.GROW_DIRECTION_BOTH

	# right: daily + play
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 26)
	add_child(right)
	right.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	right.offset_left = -620
	right.offset_right = -60
	right.offset_bottom = -60
	_daily = Button.new()
	_daily.theme_type_variation = "BlueButton"
	_daily.pressed.connect(_play_daily)
	_daily.visible = bool(Platform.get_config("show_daily", true)) # remote setting
	right.add_child(_daily)
	_update_daily()

	# remote setting: event banner (owner-controlled text, empty = none)
	var banner_text := str(Platform.get_config("event_banner", ""))
	if banner_text != "":
		var banner := Label.new()
		banner.text = banner_text
		banner.label_settings = UiTheme.heading(48, UiTheme.GOLD, 10)
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(banner)
		banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		banner.position.y = 110
		banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var play := Button.new()
	play.theme_type_variation = "PlayButton"
	play.text = tr("MENU_PLAY")
	play.pressed.connect(_play)
	right.add_child(play)

	# the running season: name and days left (FO 7)
	var season := Season.active(Time.get_unix_time_from_system())
	if not season.is_empty():
		var chip := Label.new()
		chip.text = tr("MENU_SEASON").format({"season": tr(str(season.name_key)), "days": Season.days_left(season, Time.get_unix_time_from_system())})
		chip.label_settings = UiTheme.heading(34, UiTheme.INK, 0)
		add_child(chip)
		chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		chip.offset_left = -600
		chip.offset_right = -60
		chip.offset_top = 96
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var version := Label.new()
	version.text = tr("MENU_VERSION").format({"version": ProjectSettings.get_setting("application/config/version")})
	version.add_theme_font_size_override("font_size", 24)
	add_child(version)
	version.position = Vector2(60, 40)

	var pearls := Label.new()
	pearls.text = tr("MENU_PEARLS").format({"count": int(profile.get("pearls_total", 0))})
	pearls.label_settings = UiTheme.heading(40, UiTheme.INK, 0)
	add_child(pearls)
	pearls.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pearls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pearls.offset_left = -400
	pearls.offset_right = -60
	pearls.offset_top = 40
	pearls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_toast = Label.new()
	_toast.label_settings = UiTheme.heading(44, Color.WHITE, 10)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.position.y = 60
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _process(delta: float) -> void:
	_update_daily()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)


func _soon() -> void:
	_toast.text = tr("MENU_COMING_SOON")
	_toast_t = 1.6


## The daily button counts down to midnight UTC, when a new challenge starts for everyone.
func _update_daily() -> void:
	if _daily_busy:
		return
	var text := "%s
%s" % [tr("MENU_DAILY"), tr("MENU_DAILY_ENDS").format({"time": Daily.countdown(Time.get_unix_time_from_system())})]
	if _daily.text != text:
		_daily.text = text


func _play_daily() -> void:
	if _daily_busy:
		return
	_daily_busy = true
	_daily.disabled = true
	_daily.text = tr("MENU_DAILY_LOADING")
	Boot.next_match = await Daily.plan(Time.get_unix_time_from_system())
	get_tree().change_scene_to_file(Boot.SCENES["match"])


func _play() -> void:
	get_tree().change_scene_to_file(Boot.SCENES["hide"]) # Verstoppertje against bots (phase 3)
