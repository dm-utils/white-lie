extends Control
## Looking for an online match (phase 12c): joins the lobby with the chosen animal, shows how many players were
## found and when it starts (bots fill empty seats), then hands the seat over to the match scene.
## Strandbal (phase 14c) has its own queue: the switch button changes the mode and queues again.
## Debug entry: --scene=online [--mode=ball]

var _client: OnlineClient
var _status: Label
var _done := false
var _mode := ""
var _switch: Button
var _title: Label


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
	_mode = "ball" if str(Boot.args.get("mode", "")) == "ball" else ""
	_title = Label.new()
	_title.label_settings = UiTheme.heading(90)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_status = Label.new()
	_status.text = tr("ONLINE_CONNECTING")
	_status.label_settings = UiTheme.heading(44, UiTheme.INK, 0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	var cancel := Button.new()
	cancel.text = tr("ONLINE_CANCEL")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(_back)
	_switch = Button.new()
	_switch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_switch.pressed.connect(func() -> void:
		_mode = "" if _mode == "ball" else "ball"
		_queue())
	box.add_child(_switch)
	box.add_child(cancel)
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
	var animal := str(Platform.load_profile().get("selected_animal", "octopus"))
	_client = OnlineClient.new()
	add_child(_client)
	_client.message.connect(_on_message)
	_client.closed.connect(_on_closed)
	_client.open(St33f.client.pvp_lobby_url(animal, _mode))


func _on_closed(_c: int) -> void:
	if not _done:
		_status.text = tr("ONLINE_OFFLINE")


func _show_mode() -> void:
	_title.text = tr("ONLINE_TITLE") if _mode == "" else tr("ONLINE_TITLE_BALL")
	_switch.text = tr("ONLINE_SWITCH_BALL") if _mode == "" else tr("ONLINE_SWITCH_NORMAL")


func _on_message(msg: Dictionary) -> void:
	match str(msg.get("type", "")):
		"waiting":
			_status.text = tr("ONLINE_WAITING").format({"players": int(msg.players), "seconds": int(ceil(float(msg.get("startsInMs", 0)) / 1000.0))})
		"match":
			_done = true
			Boot.next_match = {"online": msg, "mode": str(msg.get("mode", _mode))}
			get_tree().change_scene_to_file(Boot.SCENES["match"])


func _back() -> void:
	_done = true
	if _client != null:
		_client.close()
	get_tree().change_scene_to_file(Boot.SCENES["menu"])
