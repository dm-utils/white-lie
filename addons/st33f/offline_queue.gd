class_name St33fOfflineQueue
extends RefCounted
## Fire-and-forget calls (unlocks, scores) that must survive being offline. Kept on disk, retried with
## exponential back-off from 10 s up to 10 min. A permanent answer (a 4xx other than 429) drops the item.

const METHODS := {"POST": HTTPClient.METHOD_POST, "PUT": HTTPClient.METHOD_PUT, "DELETE": HTTPClient.METHOD_DELETE}

var client: St33fClient
var path := "user://st33f/queue.json"
var base_backoff_s := 10.0
var max_backoff_s := 600.0
var max_items := 500
var items: Array = []

var _flushing := false


func _init(p_client: St33fClient, p_path: String = "") -> void:
	client = p_client
	if p_path != "":
		path = p_path
	load_items()


func enqueue(method: String, api_path: String, body: Dictionary, auth := true, service := "accounts") -> void:
	items.append({"method": method, "path": api_path, "body": body, "auth": auth, "service": service, "tries": 0, "next_at": 0.0})
	while items.size() > max_items:
		items.pop_front()
	save_items()


func backoff(tries: int) -> float:
	return minf(max_backoff_s, base_backoff_s * pow(2.0, float(maxi(0, tries - 1))))


## Sends every item that is due. `now` is Unix seconds (injected for tests).
func flush(now: float) -> int:
	if _flushing:
		return 0
	_flushing = true
	var sent := 0
	for item in items.duplicate():
		if float(item.next_at) > now:
			continue
		if item.get("auth", true) and client.token == "":
			continue # keep it until the player signs in again; never drop it for that
		var res: Dictionary = await client.call_api(METHODS.get(item.method, HTTPClient.METHOD_POST), item.path, item.body, item.auth,
			str(item.get("service", "accounts")))
		if res.ok:
			items.erase(item)
			sent += 1
			continue
		var e: St33fError = res.error
		if not e.is_transient():
			items.erase(item) # permanent: retrying will not help
			continue
		item.tries = int(item.tries) + 1
		item.next_at = now + maxf(backoff(item.tries), float(e.retry_after()))
	save_items()
	_flushing = false
	return sent


func load_items() -> void:
	if not FileAccess.file_exists(path):
		items = []
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	items = d if typeof(d) == TYPE_ARRAY else []


func save_items() -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(items, "", false, true))
