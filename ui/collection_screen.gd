extends Control
## Collection (FO §7, phase 10a): every animal as a card. Unlocked ones show their (equipped) look; locked ones are
## grey with "from N pearls"; animals the Treasure Path promises but that aren't built yet say "coming soon".
## Tap a card for the detail: name, kind, attack and special, mastery, looks (owned or how to get them), Choose.
## Debug entry: --scene=collection [--detail=crab]

var _grid: GridContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	Platform.entered("collection")
	var bg := TextureRect.new()
	bg.texture = UiTheme.sky_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var back := Button.new()
	back.text = tr("COMMON_BACK")
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(Boot.SCENES["menu"]))
	add_child(back)
	back.position = Vector2(60, 40)

	var title := Label.new()
	title.text = tr("MENU_COLLECTION")
	title.label_settings = UiTheme.heading(80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position.y = 30
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 170
	scroll.offset_left = 120
	scroll.offset_right = -120
	scroll.offset_bottom = -40
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 28)
	_grid.add_theme_constant_override("v_separation", 28)
	scroll.add_child(_grid)
	_fill()
	if Boot.args.has("detail"):
		open_detail.call_deferred(str(Boot.args.detail))


## Every animal: built ones from data/animals.json, then the ones the Treasure Path promises (coming soon).
static func entries() -> Array:
	var out: Array = []
	var built := {}
	for a in Content.animals():
		built[str(a.id)] = true
		out.append({"id": str(a.id), "name_key": str(a.name_key), "built": true, "at": 0})
	for rew in Content.load_json("res://data/path.json").rewards:
		if str(rew.kind) == "animal" and not built.has(str(rew.id)):
			out.append({"id": str(rew.id), "name_key": str(rew.name_key), "built": false, "at": int(rew.at)})
	return out


## All looks for one animal from palette.json: [{id, name_key, source}] where source says how to get it.
static func looks_for(animal: String) -> Array:
	var out: Array = []
	var pal: Dictionary = Content.load_json("res://data/palette.json")
	for look in pal.looks:
		if str(pal.looks[look].animal) != animal:
			continue
		var source := ""
		var name_key := ""
		for rew in Content.load_json("res://data/path.json").rewards:
			if str(rew.kind) == "look" and str(rew.id) == look:
				source = TranslationServer.translate("COLLECTION_FROM_PATH").format({"at": int(rew.at)})
				name_key = str(rew.name_key)
		for s in Season.all():
			for rew in s.rewards:
				if str(rew.kind) == "look" and str(rew.id) == look:
					source = TranslationServer.translate("COLLECTION_FROM_SEASON").format({"season": TranslationServer.translate(str(s.name_key)), "at": int(rew.at)})
					name_key = str(rew.name_key)
		out.append({"id": str(look), "name_key": name_key, "source": source})
	return out


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var p: Dictionary = Platform.load_profile()
	var unlocked: Array = p.get("unlocked_animals", [])
	for e in entries():
		_grid.add_child(_card(e, unlocked.has(e.id) and e.built, p))


func _card(e: Dictionary, available: bool, p: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 330)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	card.add_child(box)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(340, 220)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stage)
	if e.built:
		var c := Cutout.new()
		c.size_px = 170.0
		c.z_index = 5 # parts behind the body use negative z: keep them above the card's panel
		stage.add_child(c)
		c.build(str(e.id), Rewards.equipped_look(p, str(e.id)))
		c.position = Vector2(170, 205)
		if not available:
			c.modulate = Color(0.35, 0.35, 0.4, 0.55)
	else:
		var q := Label.new()
		q.text = "?"
		q.label_settings = UiTheme.heading(140, Color(UiTheme.INK, 0.25), 0)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stage.add_child(q)
	var name := Label.new()
	name.text = tr(str(e.name_key))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.add_theme_font_size_override("font_size", 30)
	box.add_child(name)
	var state := Label.new()
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 24)
	if not e.built:
		state.text = tr("COLLECTION_SOON")
	elif not available:
		state.text = tr("COLLECTION_FROM_PATH").format({"at": int(e.at)})
	elif str(p.get("selected_animal", "")) == e.id:
		state.text = tr("COLLECTION_CHOSEN")
	box.add_child(state)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and ev.pressed):
			open_detail(str(e.id)))
	return card


## The animal's detail in the standard dialog frame. Returns the shade (tests close it).
func open_detail(id: String) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.z_index = 50 # above the cards' animals (their parts draw with their own z)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed or ev is InputEventScreenTouch and ev.pressed:
			shade.queue_free())
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 0)
	shade.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	fill_detail(box, id, shade)
	return shade


## The rows of the detail dialog (also used by tests).
func fill_detail(box: VBoxContainer, id: String, shade: Control) -> void:
	var p: Dictionary = Platform.load_profile()
	var entry := {}
	for e in entries():
		if e.id == id:
			entry = e
	var title := Label.new()
	title.text = tr(str(entry.get("name_key", id)))
	title.label_settings = UiTheme.heading(60, UiTheme.INK, 0)
	box.add_child(title)
	var data := Content.animal(id)
	var available: bool = entry.get("built", false) and (p.get("unlocked_animals", []) as Array).has(id)
	if data.is_empty():
		box.add_child(_text(tr("COLLECTION_SOON_LONG")))
	else:
		box.add_child(_text(tr("ANIMAL_TYPE_" + str(data.type).to_upper())))
		box.add_child(_text("%s: %s" % [tr("COLLECTION_ATTACK"), tr("ATTACK_DESC_" + str(data.attack.kind).to_upper())]))
		box.add_child(_text("%s: %s" % [tr("COLLECTION_SPECIAL"), tr("SPECIAL_DESC_" + str(data.special.kind).to_upper())]))
		var counts: Dictionary = (p.get("mastery", {}) as Dictionary).get(id, {})
		var tier := Mastery.tier(counts)
		box.add_child(_text(tr("COLLECTION_MASTERY").format({"tier": Mastery.tier_name(tier) if tier > 0 else tr("COLLECTION_NO_TIER"),
			"matches": int(counts.get("matches", 0)), "wins": int(counts.get("wins", 0))})))
		# looks: the standard colours plus every look for this animal
		box.add_child(_text(tr("COLLECTION_LOOKS")))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 14)
		row.add_theme_constant_override("v_separation", 10)
		box.add_child(row)
		var owned: Array = (p.get("looks", {}) as Dictionary).get("owned", [])
		var current := Rewards.equipped_look(p, id)
		var options: Array = [{"id": "", "name_key": "COLLECTION_STANDARD", "source": ""}] + looks_for(id)
		for l in options:
			var b := Button.new()
			var has_it: bool = l.id == "" or owned.has(l.id)
			b.text = tr(str(l.name_key)) if has_it else "%s · %s" % [tr(str(l.name_key)), l.source]
			b.disabled = not has_it or not available
			b.toggle_mode = true
			b.button_pressed = has_it and l.id == current
			var look_id := str(l.id)
			b.pressed.connect(func() -> void:
				var pp: Dictionary = Platform.load_profile()
				Rewards.equip(pp, id, look_id)
				Platform.save_profile(pp)
				PublicProfile.publish()
				_fill()
				for c in row.get_children():
					(c as Button).button_pressed = c == b)
			row.add_child(b)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	if available:
		var choose := Button.new()
		choose.text = tr("COLLECTION_CHOOSE") if str(p.get("selected_animal", "")) != id else tr("COLLECTION_CHOSEN")
		choose.theme_type_variation = "PlayButton"
		choose.disabled = str(p.get("selected_animal", "")) == id
		choose.pressed.connect(func() -> void:
			var pp: Dictionary = Platform.load_profile()
			pp["selected_animal"] = id
			Platform.save_profile(pp)
			PublicProfile.publish()
			_fill()
			shade.queue_free())
		buttons.add_child(choose)
	var close := Button.new()
	close.text = tr("COMMON_CLOSE")
	close.pressed.connect(shade.queue_free)
	buttons.add_child(close)


func _text(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1000, 0)
	l.add_theme_font_size_override("font_size", 30)
	return l
