extends Control
## Settings: controls, account (sign in by e-mail code / sign out), report a problem (FO §9, §10).

var _box: VBoxContainer
var _account: VBoxContainer
var _status: Label
var _email_edit: LineEdit
var _code_edit: LineEdit
var _resend: Button
var _resend_left := 0.0
var _busy := false
var _delete: Button
var _delete_armed := 0.0
var _privacy_status: Label
const PRIVACY_PARAGRAPHS := 7


func _ready() -> void:
	theme = UiTheme.get_theme()
	Platform.entered("settings")
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
	title.text = tr("SETTINGS_TITLE")
	title.label_settings = UiTheme.heading(80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.position.y = 30
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var panel := PanelContainer.new()
	add_child(panel)
	# fixed distance below the title, fixed height to the bottom; the content scrolls when it is taller
	# (styleguide: every dialog fits the screen and scrolls; longer texts in Dutch or German)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.custom_minimum_size = Vector2(1100, 1080 - 170 - 40)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.position.y = 170
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 22)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)

	# controls
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	_box.add_child(row)
	row.add_child(_heading(tr("SETTINGS_CONTROLS")))
	var controls := OptionButton.new()
	controls.add_item(tr("CONTROLS_KEYS"))
	controls.add_item(tr("CONTROLS_MOUSE"))
	controls.add_item(tr("CONTROLS_TOUCH"))
	var profile: Dictionary = Platform.load_profile()
	controls.selected = maxi(0, ["keys", "mouse", "touch"].find(Controls.choose(profile, {}, DisplayServer.is_touchscreen_available())))
	controls.item_selected.connect(_on_controls)
	row.add_child(controls)

	# language: names in their own language, never translated
	var lang_row := HBoxContainer.new()
	lang_row.add_theme_constant_override("separation", 30)
	_box.add_child(lang_row)
	lang_row.add_child(_heading(tr("SETTINGS_LANGUAGE")))
	var lang := OptionButton.new()
	var names := {"en": "English", "nl": "Nederlands"}
	for code in Platform.LANGUAGES:
		lang.add_item(names.get(code, code))
	lang.selected = Platform.LANGUAGES.find(Platform.language())
	lang.item_selected.connect(func(i: int) -> void:
		Platform.set_language(Platform.LANGUAGES[i])
		get_tree().reload_current_scene())
	lang_row.add_child(lang)

	# player name: generated from word lists, never typed (nothing to moderate); "another" rolls a new one
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 30)
	_box.add_child(name_row)
	name_row.add_child(_heading(tr("SETTINGS_NAME")))
	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 40)
	var p0: Dictionary = Platform.load_profile()
	var had_name := PlayerName.valid(p0.get("name"))
	name_label.text = PlayerName.text(PlayerName.ensure(p0))
	if not had_name:
		Platform.save_profile(p0)
	name_row.add_child(name_label)
	var reroll := Button.new()
	reroll.text = tr("SETTINGS_NAME_OTHER")
	reroll.pressed.connect(func() -> void:
		var p: Dictionary = Platform.load_profile()
		p["name"] = PlayerName.random()
		Platform.save_profile(p)
		name_label.text = PlayerName.text(p.name))
	name_row.add_child(reroll)

	# sound effects volume (a test sound plays when you let go)
	var sound_row := HBoxContainer.new()
	sound_row.add_theme_constant_override("separation", 30)
	_box.add_child(sound_row)
	sound_row.add_child(_heading(tr("SETTINGS_SOUND")))
	var sound := HSlider.new()
	sound.min_value = 0
	sound.max_value = 100
	sound.step = 5
	sound.value = Sfx.volume()
	sound.custom_minimum_size = Vector2(420, 48)
	sound.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sound.value_changed.connect(func(v: float) -> void: Sfx.set_volume(int(v)))
	sound.drag_ended.connect(func(_changed: bool) -> void: Sfx.play("snack"))
	sound_row.add_child(sound)

	# account
	_box.add_child(_heading(tr("SETTINGS_ACCOUNT")))
	_account = VBoxContainer.new()
	_account.add_theme_constant_override("separation", 14)
	_box.add_child(_account)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(1000, 0)

	# report
	var report := Button.new()
	report.text = tr("SETTINGS_REPORT")
	report.pressed.connect(func() -> void: Platform.open_report())
	_box.add_child(report)
	var hint := Label.new()
	hint.text = tr("REPORT_HOTKEY")
	hint.add_theme_font_size_override("font_size", 24)
	_box.add_child(hint)

	# privacy: what we keep and why, download everything, delete the account (AVG/GDPR)
	_box.add_child(_heading(tr("PRIVACY_TITLE")))
	var privacy_row := HBoxContainer.new()
	privacy_row.add_theme_constant_override("separation", 20)
	_box.add_child(privacy_row)
	var read := Button.new()
	read.text = tr("PRIVACY_READ")
	read.pressed.connect(_open_privacy)
	privacy_row.add_child(read)
	var download := Button.new()
	download.text = tr("PRIVACY_DOWNLOAD")
	privacy_row.add_child(download)
	_delete = Button.new()
	_delete.text = tr("PRIVACY_DELETE")
	_delete.visible = St33f.is_signed_in()
	privacy_row.add_child(_delete)
	_privacy_status = Label.new()
	_privacy_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_privacy_status.custom_minimum_size = Vector2(1000, 0)
	_box.add_child(_privacy_status)
	download.pressed.connect(func() -> void:
		download.disabled = true
		_privacy_status.text = tr("PRIVACY_GATHERING")
		var r: Dictionary = await MyData.download()
		download.disabled = false
		var where := tr("PRIVACY_SAVED_WEB") if str(r.path) == "" else tr("PRIVACY_SAVED_AT").format({"path": r.path})
		_privacy_status.text = where + ("" if (r.missing as Array).is_empty() else "\n" + tr("PRIVACY_PARTIAL")))
	_delete.pressed.connect(_on_delete)
	if str(Boot.args.get("dialog", "")) == "privacy": # debug entry for the smoke shots
		_open_privacy.call_deferred()

	_show_account()
	St33f.signed_in.connect(func(_u: String) -> void:
		_delete.visible = true
		_show_account())
	St33f.signed_out.connect(_show_account)


func _process(delta: float) -> void:
	if _delete_armed > 0.0:
		_delete_armed -= delta
		if _delete_armed <= 0.0:
			_delete.text = tr("PRIVACY_DELETE")
			_privacy_status.text = ""
	if _resend_left > 0.0 and _resend != null:
		_resend_left -= delta
		_resend.disabled = _resend_left > 0.0
		_resend.text = tr("SIGNIN_RESEND_IN").format({"seconds": int(ceil(_resend_left))}) if _resend_left > 0.0 else tr("SIGNIN_RESEND")


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = UiTheme.heading(40, UiTheme.INK, 0)
	return l


func _on_controls(index: int) -> void:
	var p: Dictionary = Platform.load_profile()
	var s: Dictionary = p.get("settings", {})
	s["controls"] = ["keys", "mouse", "touch"][clampi(index, 0, 2)]
	p["settings"] = s
	Platform.save_profile(p)


func _clear_account() -> void:
	for c in _account.get_children():
		if c != _status:
			c.queue_free()
	if _status.get_parent() == null:
		_account.add_child(_status)
	_status.text = ""
	_resend = null


## Signed in: who and sign-out buttons. Signed out: the e-mail step.
func _show_account() -> void:
	_clear_account()
	if St33f.is_signed_in():
		_add_label(tr("ACCOUNT_SIGNED_IN").format({"email": St33f.email if St33f.email != "" else "…"}))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		_account.add_child(row)
		var out := Button.new()
		out.text = tr("ACCOUNT_SIGN_OUT")
		out.pressed.connect(func() -> void: St33f.sign_out(false))
		row.add_child(out)
		var all := Button.new()
		all.text = tr("ACCOUNT_SIGN_OUT_ALL")
		all.pressed.connect(func() -> void: St33f.sign_out(true))
		row.add_child(all)
		_account.move_child(_status, -1)
		return
	_add_label(tr("ACCOUNT_GUEST"))
	_add_label(tr("SIGNIN_EMAIL_HINT"))
	_email_edit = LineEdit.new()
	_email_edit.placeholder_text = tr("SIGNIN_EMAIL_PLACEHOLDER")
	_email_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_email_edit.text_submitted.connect(func(_t: String) -> void: _send_code())
	_account.add_child(_email_edit)
	var send := Button.new()
	send.text = tr("SIGNIN_SEND")
	send.theme_type_variation = "BlueButton"
	send.pressed.connect(_send_code)
	_account.add_child(send)
	_account.move_child(_status, -1)


func _show_code_step(email: String) -> void:
	_clear_account()
	_add_label(tr("SIGNIN_CODE_HINT").format({"email": email}))
	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = tr("SIGNIN_CODE_PLACEHOLDER")
	_code_edit.max_length = 6
	_code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_code_edit.text_submitted.connect(func(_t: String) -> void: _verify())
	_account.add_child(_code_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_account.add_child(row)
	var verify := Button.new()
	verify.text = tr("SIGNIN_VERIFY")
	verify.theme_type_variation = "BlueButton"
	verify.pressed.connect(_verify)
	row.add_child(verify)
	_resend = Button.new()
	_resend.pressed.connect(_send_code)
	row.add_child(_resend)
	_resend_left = 60.0
	var other := Button.new()
	other.text = tr("SIGNIN_OTHER_ADDRESS")
	other.pressed.connect(_show_account)
	row.add_child(other)
	_account.move_child(_status, -1)
	_code_edit.grab_focus()


func _add_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(1000, 0)
	_account.add_child(l)


var _pending_email := ""


func _send_code() -> void:
	if _busy:
		return
	var email := _email_edit.text.strip_edges() if _email_edit != null and is_instance_valid(_email_edit) else _pending_email
	_busy = true
	var res: Dictionary = await St33f.sign_in_start(email)
	_busy = false
	if res.ok:
		_pending_email = email
		_show_code_step(email)
	else:
		_status.text = UiErrors.text(res.error)


func _verify() -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await St33f.sign_in_verify(_code_edit.text)
	_busy = false
	if res.ok:
		_show_account()
		_status.text = tr("SIGNIN_DONE")
	else:
		_status.text = UiErrors.text(res.error)

## Two taps: the first arms the button for five seconds, the second deletes.
func _on_delete() -> void:
	if _delete_armed <= 0.0:
		_delete_armed = 5.0
		_delete.text = tr("PRIVACY_DELETE_CONFIRM")
		_privacy_status.text = tr("PRIVACY_DELETE_EXPLAIN")
		return
	_delete.disabled = true
	_privacy_status.text = tr("PRIVACY_DELETING")
	var r: Dictionary = await St33f.delete_account()
	_delete.disabled = false
	_delete_armed = 0.0
	_delete.text = tr("PRIVACY_DELETE")
	if r.ok:
		_delete.visible = false
		_privacy_status.text = tr("PRIVACY_DELETED")
		_show_account()
	else:
		_privacy_status.text = tr("PRIVACY_DELETE_FAILED")


func _open_privacy() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed or ev is InputEventScreenTouch and ev.pressed:
			shade.queue_free())
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1300, 860)
	shade.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_heading(tr("PRIVACY_TITLE")))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 16)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	for i in range(1, PRIVACY_PARAGRAPHS + 1):
		var l := Label.new()
		l.text = tr("PRIVACY_P%d" % i)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(1200, 0)
		l.add_theme_font_size_override("font_size", 30)
		text.add_child(l)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	if St33f.client != null:
		var full := Button.new()
		full.text = tr("PRIVACY_FULL")
		full.pressed.connect(func() -> void: OS.shell_open(St33f.client.privacy_url(Platform.language())))
		buttons.add_child(full)
	var close := Button.new()
	close.text = tr("COMMON_CLOSE")
	close.pressed.connect(shade.queue_free)
	buttons.add_child(close)
