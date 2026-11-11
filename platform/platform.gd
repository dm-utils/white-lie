extends Node
## The one door between the game and everything that may live on a server later:
## profile/cloud save, achievements, results/leaderboards, remote config, crash reports.
## Game code only calls these functions. The backend behind them is swappable:
## RemoteBackend: local-first, synced to the St33f Engine when signed in (St33f autoload, loaded before us).

signal profile_changed(profile: Dictionary)

const RemoteBackend := preload("res://platform/remote_backend.gd")

var backend: RefCounted


const ReportOverlay := preload("res://ui/report_overlay.gd")


func _ready() -> void:
	backend = RemoteBackend.new(St33f)
	apply_language()
	var args := OS.get_cmdline_user_args()
	if not args.has("--no-crash-reports"):
		St33f.start_crash_reporting("boot")
	if not args.has("--no-network"):
		St33f.fetch_settings()
		St33f.signed_in.connect(func(_u: String) -> void: PublicProfile.publish(true))
		if St33f.is_signed_in():
			PublicProfile.publish()


const LANGUAGES := ["en", "nl"]


## The player's choice, else the system language when we have it, else English. Debug entry: lang=nl.
func language() -> String:
	var chosen := str(load_profile().get("settings", {}).get("language", ""))
	if Boot.args.has("lang"):
		chosen = str(Boot.args.lang)
	if LANGUAGES.has(chosen):
		return chosen
	var system := OS.get_locale_language()
	return system if LANGUAGES.has(system) else "en"


func apply_language() -> void:
	TranslationServer.set_locale(language())


func set_language(code: String) -> void:
	var p := load_profile()
	var s: Dictionary = p.get("settings", {})
	s["language"] = code
	p["settings"] = s
	save_profile(p)
	apply_language()


## Every main screen calls this, so an unclean exit can say where it happened.
func entered(scene_name: String) -> void:
	if St33f.crash != null and not OS.has_feature("web"):
		St33f.crash.breadcrumb(scene_name)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		open_report()
		get_viewport().set_input_as_handled()


## Opens "Report a problem" over the current screen, with a screenshot of this moment.
func open_report() -> void:
	if get_tree().root.has_node("ReportOverlay"):
		return
	var overlay = ReportOverlay.new()
	overlay.name = "ReportOverlay"
	overlay.screenshot = _screenshot_jpg()
	get_tree().root.add_child(overlay)


func _screenshot_jpg() -> PackedByteArray:
	var tex := get_viewport().get_texture()
	if tex == null:
		return PackedByteArray()
	var img := tex.get_image()
	if img == null or img.is_empty():
		return PackedByteArray()
	if img.get_width() > 1280:
		img.resize(1280, int(img.get_height() * 1280.0 / img.get_width()), Image.INTERPOLATE_BILINEAR)
	return img.save_jpg_to_buffer(0.8)


func is_signed_in() -> bool:
	return backend.is_signed_in()


func load_profile() -> Dictionary:
	return backend.load_profile()


func save_profile(profile: Dictionary) -> void:
	backend.save_profile(profile)
	profile_changed.emit(profile)


func unlock_achievement(id: String, tier: int = 1) -> void:
	backend.unlock_achievement(id, tier)


func submit_result(board: String, result: Dictionary, replay: Dictionary) -> void:
	backend.submit_result(board, result, replay)


func get_config(key: String, default_value: Variant = null) -> Variant:
	return backend.get_config(key, default_value)


func report_crash(message: String, stack: Array = []) -> void:
	backend.report_crash(message, stack)
