extends CanvasLayer
## "Report a problem" on top of whatever is on screen (F8 anywhere, or from Settings). The game pauses underneath.
## The screenshot is taken by Platform just before this opens, so it shows the moment the player meant.

var screenshot := PackedByteArray()

var _category: OptionButton
var _text: TextEdit
var _shot: CheckBox
var _save: CheckBox
var _status: Label
var _send: Button
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.07, 0.29, 0.43, 0.55)
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(1000, 0)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)

	var title := Label.new()
	title.text = tr("REPORT_TITLE")
	title.label_settings = UiTheme.heading(56, UiTheme.INK, 0)
	box.add_child(title)
	_category = OptionButton.new()
	for key in ["REPORT_CATEGORY_BUG", "REPORT_CATEGORY_IDEA", "REPORT_CATEGORY_OTHER"]:
		_category.add_item(tr(key))
	box.add_child(_category)
	_text = TextEdit.new()
	_text.placeholder_text = tr("REPORT_TEXT_PLACEHOLDER")
	_text.custom_minimum_size = Vector2(0, 220)
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_text)
	_shot = CheckBox.new()
	_shot.text = tr("REPORT_ATTACH_SCREENSHOT")
	_shot.button_pressed = not screenshot.is_empty()
	_shot.disabled = screenshot.is_empty()
	box.add_child(_shot)
	_save = CheckBox.new()
	_save.text = tr("REPORT_ATTACH_SAVE")
	_save.button_pressed = true
	box.add_child(_save)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	var cancel := Button.new()
	cancel.text = tr("REPORT_CANCEL")
	cancel.pressed.connect(close)
	row.add_child(cancel)
	_send = Button.new()
	_send.text = tr("REPORT_SEND")
	_send.theme_type_variation = "BlueButton"
	_send.pressed.connect(_on_send)
	row.add_child(_send)
	_text.grab_focus()
	get_tree().paused = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func close() -> void:
	get_tree().paused = false
	queue_free()


func _on_send() -> void:
	if _busy:
		return
	var text := _text.text.strip_edges()
	if text.length() < 3:
		_status.text = tr("REPORT_EMPTY")
		return
	_busy = true
	_send.disabled = true
	_status.text = tr("REPORT_SENDING")
	var category: String = ["bug", "idea", "other"][_category.selected]
	var save := JSON.stringify(Platform.load_profile(), "", false, true) if _save.button_pressed else ""
	var shot := screenshot if _shot.button_pressed else PackedByteArray()
	var res: Dictionary = await St33f.report_problem(category, text, shot, save)
	_busy = false
	_send.disabled = false
	if not res.ok:
		_status.text = UiErrors.text(res.error)
		return
	_status.text = tr("REPORT_SENT") if res.attachments_ok else tr("REPORT_SENT_NO_ATTACHMENTS")
	_send.disabled = true
	await get_tree().create_timer(1.8, true, false, true).timeout
	close()
