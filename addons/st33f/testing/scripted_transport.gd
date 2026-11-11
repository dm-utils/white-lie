class_name St33fScriptedTransport
extends St33fTransport
## Test transport: answers from a handler, and records every request it saw.
## handler: func(method: int, path: String, headers: PackedStringArray, body: Variant) -> [status, data]

var handler: Callable
var requests: Array = []


func _init(p_handler: Callable = Callable()) -> void:
	handler = p_handler


func request(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var path := url.substr(url.find("/", url.find("://") + 3))
	var parsed: Variant = JSON.parse_string(body) if body != "" else null
	requests.append({"method": method, "path": path, "headers": headers, "body": parsed, "url": url})
	if not handler.is_valid():
		return {"status": 0, "body": ""}
	var answer: Array = handler.call(method, path, headers, parsed)
	return {"status": int(answer[0]), "body": JSON.stringify(answer[1]) if answer.size() > 1 and answer[1] != null else ""}


func request_raw(method: int, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	var path := url.substr(url.find("/", url.find("://") + 3))
	requests.append({"method": method, "path": path, "headers": headers, "body": null, "raw_size": body.size(), "url": url})
	if not handler.is_valid():
		return {"status": 0, "body": ""}
	var answer: Array = handler.call(method, path, headers, {"raw_size": body.size()})
	return {"status": int(answer[0]), "body": JSON.stringify(answer[1]) if answer.size() > 1 and answer[1] != null else ""}


func last() -> Dictionary:
	return requests[-1] if requests.size() > 0 else {}


func has_header(req: Dictionary, prefix: String) -> bool:
	for h in req.get("headers", PackedStringArray()):
		if str(h).begins_with(prefix):
			return true
	return false
