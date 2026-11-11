class_name St33fHttpTransport
extends St33fTransport
## Real HTTP through a short-lived HTTPRequest node per call.
## Web note: HTTPRequest.download_file always fails on the web, so we always read the body from the signal.

var timeout_s := 15.0
var _host: Node


func _init(host: Node) -> void:
	_host = host


func request(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	return await _send(method, url, headers, body.to_utf8_buffer())


func request_raw(method: int, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	return await _send(method, url, headers, body)


func _send(method: int, url: String, headers: PackedStringArray, body: PackedByteArray) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	http.use_threads = false
	_host.add_child(http)
	var err := http.request_raw(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"status": 0, "body": ""}
	var res: Array = await http.request_completed
	http.queue_free()
	# res = [result, response_code, headers, body]
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "body": ""}
	return {"status": int(res[1]), "body": (res[3] as PackedByteArray).get_string_from_utf8()}
