extends Control
## Leaderboard (FO §8): tabs Day (the daily challenge) / Week; each player's best; your own place always visible.
## Scores that wait for the replay check are marked. Names come from word lists (PlayerName); tap a row for the
## player's public profile (name, favourite animal, mastery, collection).
## Debug entry: --scene=leaderboard [--board=week] [--dialog=friends]

const BOARDS := ["day", "week"]

var _board := "day"
var _list: VBoxContainer
var _status: Label
var _tabs: Array[Button] = []
var _loading := 0 # request counter: a late answer for an old tab is ignored
var _friends_only := false


func _ready() -> void:
	theme = UiTheme.get_theme()
	Platform.entered("leaderboard")
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
	title.text = tr("MENU_LEADERBOARD")
	title.label_settings = UiTheme.heading(80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position.y = 30
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 20)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(tabs)
	tabs.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	tabs.position.y = 150
	tabs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	for b in BOARDS:
		var t := Button.new()
		t.text = tr("BOARD_TAB_DAY") if b == "day" else tr("BOARD_TAB_WEEK")
		t.toggle_mode = true
		t.custom_minimum_size = Vector2(260, 0)
		t.pressed.connect(func() -> void: _show(b))
		tabs.add_child(t)
		_tabs.append(t)
	tabs.add_child(VSeparator.new())
	var only := Button.new()
	only.text = tr("BOARD_FRIENDS_ONLY")
	only.toggle_mode = true
	only.toggled.connect(func(on: bool) -> void:
		_friends_only = on
		_show(_board))
	tabs.add_child(only)
	var friends := Button.new()
	friends.text = tr("FRIENDS_TITLE")
	friends.theme_type_variation = "BlueButton"
	friends.pressed.connect(open_friends)
	tabs.add_child(friends)

	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.custom_minimum_size = Vector2(1100, 760)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = 260
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 10)
	scroll.add_child(inner)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(_status)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	inner.add_child(_list)

	_show(str(Boot.args.get("board", "day")) if BOARDS.has(str(Boot.args.get("board", ""))) else "day")
	if str(Boot.args.get("dialog", "")) == "friends":
		open_friends()


func _show(board: String) -> void:
	_board = board
	for i in BOARDS.size():
		_tabs[i].button_pressed = BOARDS[i] == board
	for c in _list.get_children():
		c.queue_free()
	_status.text = tr("BOARD_LOADING")
	_loading += 1
	var ticket := _loading
	if _friends_only and not St33f.is_signed_in():
		_status.text = tr("FRIENDS_SIGN_IN")
		return
	var res: Dictionary = await St33f.client.get_board(board, _friends_only) if St33f.client != null else {"ok": false, "error": null}
	if ticket != _loading or not is_inside_tree():
		return
	if not res.ok:
		_status.text = tr("BOARD_OFFLINE")
		return
	fill(res.data)


## Builds the rows from a board answer (also used by tests).
func fill(data: Dictionary) -> void:
	for c in _list.get_children():
		c.queue_free()
	var entries: Array = data.get("entries", [])
	var me: Variant = data.get("me")
	var my_player := str(me.player) if me is Dictionary else ""
	_status.text = tr("BOARD_EMPTY") if entries.is_empty() else tr("BOARD_PLAYERS").format({"count": int(data.get("players", entries.size()))})
	if not St33f.is_signed_in():
		_status.text += "\n" + tr("BOARD_SIGN_IN")
	var shown_me := false
	for e in entries:
		var mine := str(e.player) == my_player
		shown_me = shown_me or mine
		_list.add_child(_row(e, mine))
	if me is Dictionary and not shown_me:
		_list.add_child(_label("…", UiTheme.INK))
		_list.add_child(_row(me, true))


func _row(e: Dictionary, mine: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var player_id := str(e.get("player", ""))
	row.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT or ev is InputEventScreenTouch and ev.pressed:
			open_profile(player_id))
	var shown := PlayerName.text(e.get("name")) if e.get("name") is Dictionary else tr("BOARD_PLAYER").format({"id": str(e.player).left(6)})
	var name := "%s (%s)" % [shown, tr("BOARD_YOU")] if mine else shown
	var colour := UiTheme.GOLD.darkened(0.35) if mine else UiTheme.INK
	var rank := _label("#%d" % int(e.rank), colour)
	rank.custom_minimum_size = Vector2(120, 0)
	row.add_child(rank)
	var who := _label(name, colour)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(who)
	if bool(e.get("pending", false)):
		row.add_child(_label(tr("BOARD_PENDING"), Color(UiTheme.INK, 0.6)))
	var pts := _label(str(int(e.score)), colour)
	pts.custom_minimum_size = Vector2(160, 0)
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pts)
	return row


## The player's public profile in the standard dialog frame: fits the screen, closes with a tap outside or Close.
## The standard dialog frame: dims the screen, fits it, closes with a tap outside or Close. Returns {shade, body}.
func _dialog(loading_text: String) -> Dictionary:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed or ev is InputEventScreenTouch and ev.pressed:
			shade.queue_free())
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 0)
	shade.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	box.add_child(body)
	body.add_child(_label(loading_text, UiTheme.INK))
	var close := Button.new()
	close.text = tr("COMMON_CLOSE")
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(shade.queue_free)
	box.add_child(close)
	return {"shade": shade, "body": body}


func open_profile(player_id: String) -> Control:
	var d := _dialog(tr("PROFILE_LOADING"))
	var shade: Control = d.shade
	var body: VBoxContainer = d.body
	if player_id != "" and St33f.client != null:
		var res: Dictionary = await St33f.client.get_player(player_id)
		if is_instance_valid(body):
			fill_profile(body, res.data if res.ok else {})
	return shade


## Friends: your own code to share, a field to add someone's code, and the list (remove with x). One way.
func open_friends() -> Control:
	var d := _dialog(tr("FRIENDS_LOADING"))
	var body: VBoxContainer = d.body
	if not St33f.is_signed_in() or St33f.client == null:
		fill_friends(body, {}, "")
		return d.shade
	var res: Dictionary = await St33f.client.get_friends()
	if is_instance_valid(body):
		fill_friends(body, res.data if res.ok else {}, "" if res.ok else tr("BOARD_OFFLINE"))
	return d.shade


const FRIEND_ERRORS := {"bad_code": "FRIENDS_BAD_CODE", "unknown_code": "FRIENDS_UNKNOWN_CODE", "own_code": "FRIENDS_OWN_CODE",
	"too_many_friends": "FRIENDS_TOO_MANY", "rate_limited": "FRIENDS_SLOW_DOWN"}


func _who(f: Dictionary) -> String:
	return PlayerName.text(f.get("name")) if f.get("name") is Dictionary else tr("BOARD_PLAYER").format({"id": str(f.get("player", "")).left(6)})


## Rows of the friends dialog ({} = signed out or unreachable, with a message). Also used by tests.
func fill_friends(body: VBoxContainer, data: Dictionary, message: String) -> void:
	for c in body.get_children():
		c.queue_free()
	var title := _label(tr("FRIENDS_TITLE"), UiTheme.INK)
	title.label_settings = UiTheme.heading(56, UiTheme.INK, 0)
	body.add_child(title)
	if data.is_empty():
		body.add_child(_label(message if message != "" else tr("FRIENDS_SIGN_IN"), UiTheme.INK))
		return
	var code := str(data.get("code", ""))
	var mine := HBoxContainer.new()
	mine.add_theme_constant_override("separation", 20)
	mine.add_child(_label(tr("FRIENDS_YOUR_CODE"), UiTheme.INK))
	var code_label := _label("%s-%s" % [code.left(4), code.substr(4)], UiTheme.GOLD.darkened(0.35))
	code_label.add_theme_font_size_override("font_size", 48)
	mine.add_child(code_label)
	var copy := Button.new()
	copy.text = tr("FRIENDS_COPY")
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(code)
		copy.text = tr("FRIENDS_COPIED"))
	mine.add_child(copy)
	body.add_child(mine)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 16)
	var field := LineEdit.new()
	field.placeholder_text = tr("FRIENDS_CODE_HINT")
	field.max_length = 12
	field.custom_minimum_size = Vector2(380, 0)
	add_row.add_child(field)
	var add := Button.new()
	add.text = tr("FRIENDS_ADD")
	add_row.add_child(add)
	body.add_child(add_row)
	var status := _label("", UiTheme.INK)
	body.add_child(status)
	var list := VBoxContainer.new()
	body.add_child(list)
	var friends: Array = data.get("friends", [])
	if friends.is_empty():
		list.add_child(_label(tr("FRIENDS_NONE"), UiTheme.INK))
	for f in friends:
		var row := HBoxContainer.new()
		var who := _label(_who(f), UiTheme.INK)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(who)
		var remove := Button.new()
		remove.text = tr("FRIENDS_REMOVE")
		var pid := str(f.get("player", ""))
		remove.pressed.connect(func() -> void:
			remove.disabled = true
			var r: Dictionary = await St33f.client.remove_friend(pid)
			if r.ok and is_instance_valid(row):
				row.queue_free())
		row.add_child(remove)
		list.add_child(row)
	add.pressed.connect(func() -> void:
		add.disabled = true
		var r: Dictionary = await St33f.client.add_friend(field.text)
		if not is_instance_valid(status):
			return
		add.disabled = false
		if r.ok:
			status.text = tr("FRIENDS_ADDED").format({"name": _who(r.data)})
			field.text = ""
			if _friends_only:
				_show(_board)
		else:
			status.text = tr(FRIEND_ERRORS.get(r.error.code if r.error != null else "", "BOARD_OFFLINE")))


## Rows of a profile dialog from the service's answer ({} = no public profile). Also used by tests.
func fill_profile(body: VBoxContainer, p: Dictionary) -> void:
	for c in body.get_children():
		c.queue_free()
	if p.is_empty():
		body.add_child(_label(tr("PROFILE_UNAVAILABLE"), UiTheme.INK))
		return
	var title := _label(PlayerName.text(p.get("name")), UiTheme.INK)
	title.label_settings = UiTheme.heading(56, UiTheme.INK, 0)
	body.add_child(title)
	var fav := Content.animal(str(p.get("animal", "")))
	body.add_child(_label(tr("PROFILE_FAVOURITE").format({"animal": tr(str(fav.get("name_key", "?")))}), UiTheme.INK))
	body.add_child(_label(tr("PROFILE_BADGES"), UiTheme.GOLD.darkened(0.35)))
	var badges: Array = p.get("badges", [])
	if badges.is_empty():
		body.add_child(_label(tr("PROFILE_NO_BADGES"), UiTheme.INK))
	for b in badges:
		var parts := str(b).split(":")
		if parts.size() == 2:
			var a := Content.animal(parts[0])
			body.add_child(_label("%s · %s" % [tr(str(a.get("name_key", parts[0]))), Mastery.tier_name(int(parts[1]))], UiTheme.INK))
	body.add_child(_label(tr("PROFILE_COLLECTION").format({"count": (p.get("collection", []) as Array).size()}), UiTheme.INK))


func _label(text: String, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", colour)
	l.add_theme_font_size_override("font_size", 36)
	return l
