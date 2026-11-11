class_name MyData
extends RefCounted
## "Download my data" and "Delete my account" (AVG/GDPR; phase 8a).
## The export always holds what is on this device; signed in, also what every platform service holds.
## The file goes to the browser's downloads (web) or the Downloads folder (desktop).

const FILE_NAME := "white-lie-my-data.json"


## Builds the export: {device: the local profile, platform: {accounts, leaderboards, feedback} | null, missing}.
static func gather() -> Dictionary:
	var out := {"format": 1, "game": "white-lie", "device": Platform.load_profile(), "platform": null, "missing": []}
	if St33f.client != null and St33f.is_signed_in():
		var r: Dictionary = await St33f.export_my_data()
		out.platform = r.data
		out.missing = r.missing
	return out


## Saves the text as a file the player can keep. Returns where it went ("" in the browser: it downloads).
static func save(text: String) -> String:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(text.to_utf8_buffer(), FILE_NAME, "application/json")
		return ""
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = OS.get_user_data_dir()
	var path := dir.path_join(FILE_NAME)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return path


## Export and save in one go. Returns {path, missing}.
static func download() -> Dictionary:
	var data: Dictionary = await gather()
	var path := save(JSON.stringify(data, "  "))
	return {"path": path, "missing": data.missing}
