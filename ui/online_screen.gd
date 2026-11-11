extends Control
## Playing online (phase 4): the open lobby by default (bots fill after a few seconds), or a friends room with a
## 4-character code: make one and read the code out, or type a friend's code; anyone in the room presses Start.
## Debug entry: --scene=online [--room=K7PQ]

var _client: OnlineClient
var _status: Label
var _done := false
var _mode := ""
var _title: Label
var _room := "" # friends room code, "" = the open lobby
var _code_edit: LineEdit
var _start: Button
var _friend_row: HBoxContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	Platform.entered("online")
	var bg := TextureRect.new()
	bg.texture = UiTheme.sky_gradient()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 30)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title = Label.new()
	_title.label_settings = UiTheme.heading(90)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_status = Label.new()
	_status.text = tr("ONLINE_CONNECTING")
	_status.label_settings = UiTheme.heading(44, UiTheme.INK, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	_start = Button.new()
	_start.text = tr("ONLINE_START_NOW")
	_start.theme_type_variation = "PlayButton"
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start.pressed.connect(func() -> void:
		if _client != null:
			_client.send({"type": "start"}))
	box.add_child(_start)
	_friend_row = HBoxContainer.new()
	_friend_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_friend_row.add_theme_constant_override("separation", 20)
	box.add_child(_friend_row)
	var make := Button.new()
	make.text = tr("ONLINE_MAKE_ROOM")
	make.pressed.connect(func() -> void:
		_room = St33fClient.pvp_room_code()
		_queue())
	_friend_row.add_child(make)
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = tr("ONLINE_CODE_HINT")
	_code_edit.custom_minimum_size = Vector2(220, 0)
	_code_edit.max_length = 4
	_code_edit.text_changed.connect(func(t: String) -> void:
		var c := clean_code(t)
		if c != t:
			_code_edit.text = c
			_code_edit.caret_column = c.length())
	_friend_row.add_child(_code_edit)
	var join := Button.new()
	join.text = tr("ONLINE_JOIN_ROOM")
	join.pressed.connect(func() -> void:
		if clean_code(_code_edit.text).length() == 4:
			_room = clean_code(_code_edit.text)
			_queue())
	_friend_row.add_child(join)
	var cancel := Button.new()
	cancel.text = tr("ONLINE_CANCEL")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_back)
	box.add_child(cancel)
	_room = clean_code(str(Boot.args.get("room", "")))
	if _room.length() != 4:
		_room = ""
	_show_mode()

	if St33f.client == null:
		_status.text = tr("ONLINE_OFFLINE")
		return
	_queue()


## (Re)joins the lobby for the current mode; leaving the old queue is just closing its socket.
func _queue() -> void:
	_show_mode()
	if St33f.client == null:
		return
	if _client != null:
		_client.closed.disconnect(_on_closed)
		_client.close()
		_client.queue_free()
	_status.text = tr("ONLINE_CONNECTING")
	var who := str(Platform.load_profile().get("selected_character", "skipper"))
	_client = OnlineClient.new()
	add_child(_client)
	_client.message.connect(_on_message)
	_client.closed.connect(_on_closed)
	_client.open(St33f.client.pvp_lobby_url(who, _mode, _room))


func _on_closed(_c: int) -> void:
	if not _done:
		_status.text = tr("ONLINE_OFFLINE")


func _show_mode() -> void:
	_title.text = tr("ONLINE_TITLE") if _room == "" else tr("ONLINE_ROOM_TITLE").format({"code": _room})
	_start.visible = _room != ""
	_friend_row.visible = _room == ""


## What a typed code becomes: capitals, only the characters codes use, at most 4 (pure, tested).
static func clean_code(text: String) -> String:
	var out := ""
	for ch in text.to_upper():
		if "23456789ABCDEFGHJKMNPQRSTUVWXYZ".contains(ch) and out.length() < 4:
			out += ch
	return out


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"waiting":
			if bool(msg.get("friends", false)):
				_status.text = tr("ONLINE_ROOM_WAITING").format({"players": int(msg.players)})
			else:
				_status.text = tr("ONLINE_WAITING").format({"players": int(msg.players), "seconds": int(ceil(float(msg.get("startsInMs", 0)) / 1000.0))})
		"match":
			_done = true
			Boot.next_match = {"online": msg, "mode": str(msg.get("mode", _mode))}
			get_tree().change_scene_to_file(Boot.SCENES["hide"])


func _back() -> void:
	_done = true
	if _client != null:
		_client.close()
	get_tree().change_scene_to_file(Boot.SCENES["menu"])
