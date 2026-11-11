extends Node
## The St33f autoload: wires client, token store, profile sync and offline queue together and keeps their
## state under user://st33f/. Register it as autoload "St33f" and set the project setting `st33f/game`.
##
## Environment: a build with feature tag "prod_hosts" talks to production; everything else to dev.

signal signed_in(user_id: String)
signal signed_out

const STATE_PATH := "user://st33f/state.json"

var game := ""
var environment := "dev"
var client: St33fClient
var tokens: St33fTokenStore
var profile_sync: St33fProfileSync
var queue: St33fOfflineQueue
var crash: St33fCrashReporter
var user_id := ""
## The address the player signed in with, kept on this device only so settings can show it.
var email := ""

var _email := ""
var _challenges := PackedStringArray()
var _queue_timer := 0.0


func _ready() -> void:
	if client == null:
		configure(str(ProjectSettings.get_setting("st33f/game", "")))


## Tests pass their own transport, token store, base URL and state folder.
func configure(p_game: String, transport: St33fTransport = null, token_store: St33fTokenStore = null,
		base_url: Variant = "", merge := Callable(), queue_path := "") -> void:
	game = p_game
	environment = "prod" if OS.has_feature("prod_hosts") else "dev"
	var given := base_url is Dictionary or str(base_url) != ""
	var urls: Variant = base_url if given else St33fClient.URLS.get(environment, {})
	client = St33fClient.new(game, urls, transport if transport != null else St33fHttpTransport.new(self))
	tokens = token_store if token_store != null else St33fEncryptedFileTokenStore.new()
	client.token = tokens.load_token()
	profile_sync = St33fProfileSync.new(client, merge if merge.is_valid() else _server_wins)
	queue = St33fOfflineQueue.new(client, queue_path)
	crash = St33fCrashReporter.new(queue, game)
	_load_state()
	profile_sync.synced.connect(func(_p: Dictionary, _v: int) -> void: _save_state())


## --- remote settings ---
## The last values from the server, kept on disk so an offline start still has them. Games always pass a default.

const SETTINGS_PATH := "user://st33f/settings.json"
const SETTINGS_MAX_AGE_S := 60.0

var settings: Dictionary = {}
var settings_version := 0
var _settings_at := -1000.0


func get_setting(key: String, default_value: Variant) -> Variant:
	if settings.is_empty() and FileAccess.file_exists(SETTINGS_PATH):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if d is Dictionary:
			settings = d.get("values", {})
			settings_version = int(d.get("version", 0))
	return settings.get(key, default_value)


## Fetch fresh values (at most once a minute). Returns true when the values changed.
func fetch_settings(force := false) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - _settings_at < SETTINGS_MAX_AGE_S:
		return false
	_settings_at = now
	var res: Dictionary = await client.get_settings()
	if not res.ok:
		return false
	var changed := int(res.data.get("version", 0)) != settings_version or settings.is_empty()
	settings = res.data.get("values", {})
	settings_version = int(res.data.get("version", 0))
	DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"version": settings_version, "values": settings}))
	return changed


## Turn on crash reporting (the game calls this once at start). Browsers close tabs without notice, so the
## unclean-exit breadcrumb is only used in native builds.
func start_crash_reporting(scene_name: String) -> void:
	crash.install(scene_name if not OS.has_feature("web") else "")
	if OS.has_feature("web"):
		crash.clean_exit()


func _notification(what: int) -> void:
	if crash == null:
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PREDELETE:
			crash.clean_exit() # quitting or being sent to the background is not a crash
		NOTIFICATION_APPLICATION_RESUMED:
			if not OS.has_feature("web"):
				crash.breadcrumb("resumed")


## A player report with optional screenshot (JPEG bytes) and save (JSON text). The report is sent first, so it is
## kept even if an attachment fails. Returns {ok, id, attachments_ok, error}.
func report_problem(category: String, text: String, screenshot_jpg: PackedByteArray, save_json: String) -> Dictionary:
	var kinds: Array = []
	if not screenshot_jpg.is_empty():
		kinds.append("screenshot")
	if save_json != "":
		kinds.append("save")
	var device := "%s %s" % [OS.get_name(), OS.get_model_name()]
	var res: Dictionary = handle_result(await client.submit_feedback(category, text, str(ProjectSettings.get_setting("application/config/version", "0")), device, kinds))
	if not res.ok:
		return {"ok": false, "id": "", "attachments_ok": false, "error": res.error}
	var id := str(res.data.get("id", ""))
	var uploads: Dictionary = res.data.get("uploads", {})
	var attachments_ok := kinds.is_empty() or uploads.size() == kinds.size()
	if uploads.has("screenshot"):
		var u: Dictionary = await client.upload_attachment(id, "screenshot", str(uploads.screenshot), screenshot_jpg, "image/jpeg")
		attachments_ok = attachments_ok and u.ok
	if uploads.has("save"):
		var u: Dictionary = await client.upload_attachment(id, "save", str(uploads.save), save_json.to_utf8_buffer(), "application/json")
		attachments_ok = attachments_ok and u.ok
	return {"ok": true, "id": id, "attachments_ok": attachments_ok, "error": null}


func is_signed_in() -> bool:
	return client != null and client.token != ""


## Step 1: ask for a code. Up to 3 recent challenges are kept, so an older mail still works after a resend.
func sign_in_start(email: String) -> Dictionary:
	var res: Dictionary = await client.auth_start(email)
	if res.ok:
		var normalised := email.strip_edges().to_lower()
		if normalised != _email:
			_challenges.clear()
			_email = normalised
		_challenges.append(str(res.data.get("challenge", "")))
		while _challenges.size() > 3:
			_challenges.remove_at(0)
	return res


## Step 2: the 6-digit code from the mail.
func sign_in_verify(code: String) -> Dictionary:
	var res: Dictionary = await client.auth_verify(_email, _challenges, code.strip_edges())
	if res.ok:
		client.token = str(res.data.get("token", ""))
		user_id = str(res.data.get("userId", ""))
		email = _email
		tokens.save_token(client.token)
		_challenges.clear()
		_save_state()
		signed_in.emit(user_id)
	return res


func sign_out(everywhere := false) -> void:
	if is_signed_in():
		await client.logout(everywhere)
	_forget_session()


## Everything the platform holds about the signed-in player, from every service, in one dictionary (to save as
## a file). Returns {ok, data: {accounts, leaderboards, feedback}, missing: [services that did not answer]}.
func export_my_data() -> Dictionary:
	if not is_signed_in():
		return {"ok": false, "data": {}, "missing": ["signed_out"]}
	var data := {"exported_at": Time.get_datetime_string_from_system(true) + "Z", "game": game}
	var missing: Array = []
	for pair in [["accounts", client.export_account], ["leaderboards", client.export_leaderboards], ["feedback", client.export_feedback]]:
		var r: Dictionary = handle_result(await pair[1].call())
		if r.ok:
			data[pair[0]] = r.data
		else:
			missing.append(pair[0])
	return {"ok": missing.is_empty(), "data": data, "missing": missing}


## Delete the account: first what the other services hold (so it is gone at once), then the account itself, which
## leaves a tombstone so the services also wipe anything left within the hour. Ends the session on this device.
## Returns {ok, error}. The other services' answers don't block: their hourly safety net finishes the job.
func delete_account() -> Dictionary:
	if not is_signed_in():
		return {"ok": false, "error": "signed_out"}
	await client.delete_leaderboards()
	await client.delete_feedback()
	var r: Dictionary = await client.delete_account()
	if not r.ok:
		return {"ok": false, "error": r.error.code if r.error != null else "network"}
	_forget_session()
	return {"ok": true, "error": null}


## Any call that comes back signed_out ends the local session too.
func handle_result(res: Dictionary) -> Dictionary:
	if not res.ok and res.error != null and (res.error as St33fError).is_signed_out() and is_signed_in():
		_forget_session()
	return res


func _forget_session() -> void:
	var was := is_signed_in()
	client.token = ""
	user_id = ""
	email = ""
	tokens.clear()
	profile_sync.version = 0
	_save_state()
	if was:
		signed_out.emit()


func _process(delta: float) -> void:
	if crash != null:
		crash.flush() # crash reports are anonymous: they go out signed in or not
	if is_signed_in():
		profile_sync.tick(delta)
	_queue_timer -= delta
	if _queue_timer <= 0.0 and not queue.items.is_empty():
		_queue_timer = 5.0
		queue.flush(Time.get_unix_time_from_system())


static func _server_wins(_local: Dictionary, server: Dictionary) -> Dictionary:
	return server


func _load_state() -> void:
	if not FileAccess.file_exists(STATE_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	if typeof(d) == TYPE_DICTIONARY:
		user_id = str(d.get("user_id", ""))
		email = str(d.get("email", ""))
		profile_sync.version = int(d.get("profile_version", 0))


func _save_state() -> void:
	DirAccess.make_dir_recursive_absolute(STATE_PATH.get_base_dir())
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"user_id": user_id, "email": email, "profile_version": profile_sync.version}))
