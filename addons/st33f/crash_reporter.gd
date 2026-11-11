class_name St33fCrashReporter
extends RefCounted
## Anonymous crash reports (no account, no token is ever sent with them).
##  - Script and engine errors come in through a Logger (Godot 4.5+). They may arrive on any thread, so they are only
##    collected under a mutex here and sent from the main thread by flush().
##  - Duplicates are dropped per session; at most `max_per_session` reports per run.
##  - A breadcrumb file marks a running game. If it is still there at the next start, the game did not exit cleanly
##    (native crash, killed, out of memory) and an "unclean_exit" report says which scene was last active.
## Reports go through the offline queue, so they survive being offline.

const BREADCRUMB := "user://st33f/running.json"

var queue: St33fOfflineQueue
var game: String
var build: String
var max_per_session := 5

var _seen := {}
var _sent := 0
var _pending: Array = []
var _mutex := Mutex.new()
var _logger: Logger


class CaptureLogger:
	extends Logger
	var owner: WeakRef

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var reporter = owner.get_ref()
		if reporter == null:
			return
		var message := rationale if rationale != "" else code
		var frames: Array = []
		for bt in script_backtraces:
			for i in bt.get_frame_count():
				frames.append("%s:%d in %s" % [bt.get_frame_file(i), bt.get_frame_line(i), bt.get_frame_function(i)])
		if frames.is_empty():
			frames.append("%s:%d in %s" % [file, line, function])
		reporter.capture("script_error" if error_type == Logger.ERROR_TYPE_SCRIPT else "other", message, frames)

	func _log_message(_message: String, _error: bool) -> void:
		pass


func _init(p_queue: St33fOfflineQueue, p_game: String) -> void:
	queue = p_queue
	game = p_game
	build = str(ProjectSettings.get_setting("application/config/version", "0"))


## Installs the logger and handles a breadcrumb left by the previous run.
func install(scene_name: String) -> void:
	_logger = CaptureLogger.new()
	_logger.owner = weakref(self)
	OS.add_logger(_logger)
	if FileAccess.file_exists(BREADCRUMB):
		var last: Variant = JSON.parse_string(FileAccess.get_file_as_string(BREADCRUMB))
		var where := str(last.get("scene", "?")) if last is Dictionary else "?"
		capture("unclean_exit", "the previous run did not exit cleanly (last scene: %s)" % where, ["scene:" + where])
	breadcrumb(scene_name)


func uninstall() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


## Call when the active scene changes, so an unclean exit can say where it happened.
func breadcrumb(scene_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(BREADCRUMB.get_base_dir())
	var f := FileAccess.open(BREADCRUMB, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"scene": scene_name}))


## Call on a clean exit.
func clean_exit() -> void:
	if FileAccess.file_exists(BREADCRUMB):
		DirAccess.remove_absolute(BREADCRUMB)


## Thread-safe: only records the report.
func capture(kind: String, message: String, frames: Array) -> void:
	_mutex.lock()
	var key := kind + "|" + message.substr(0, 200) + "|" + (str(frames[0]) if not frames.is_empty() else "")
	if not _seen.has(key) and _sent + _pending.size() < max_per_session:
		_seen[key] = true
		_pending.append({"kind": kind, "message": message.substr(0, 1000), "stack": frames.slice(0, 50)})
	_mutex.unlock()


## Main thread: moves captured reports into the offline queue (anonymous: auth = false).
func flush() -> int:
	_mutex.lock()
	var batch := _pending
	_pending = []
	_mutex.unlock()
	for r in batch:
		var body := {"game": game, "kind": r.kind, "message": r.message, "stack": r.stack, "build": build, "os": OS.get_name()}
		queue.enqueue("POST", "/v1/crashes", body, false, "feedback")
		_sent += 1
	return batch.size()
