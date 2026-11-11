class_name OnlineClient
extends Node
## A WebSocket to the pvp relay (phase 12c), JSON messages both ways. Works in native builds and in the browser.
## Messages are handed over as Dictionaries through `message`; numbers in commands are turned back into ints.
## The protocol helpers (batching own input, applying relay messages to a Rollback) are static and tested.

signal message(msg: Dictionary)
signal closed(code: int)

const MAX_PER_MESSAGE := 8 # the relay accepts up to 8 ticks per input message

var ws := WebSocketPeer.new()
var _was_open := false
var _closed_sent := false


func open(url: String) -> Error:
	return ws.connect_to_url(url)


func is_open() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(msg: Dictionary) -> void:
	if is_open():
		ws.send_text(JSON.stringify(msg))


func close() -> void:
	ws.close(1000, "bye")


func _process(_delta: float) -> void:
	ws.poll()
	var state := ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_was_open = true
		while ws.get_available_packet_count() > 0:
			var d: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if d is Dictionary:
				message.emit(d)
	elif state == WebSocketPeer.STATE_CLOSED and not _closed_sent:
		_closed_sent = true
		closed.emit(ws.get_close_code())


## Own input [[tick, cmd], ...] (consecutive ticks) as relay messages of up to 8 ticks.
static func batch(outbox: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < outbox.size():
		var t0 := int(outbox[i][0])
		var cs: Array = []
		while i < outbox.size() and cs.size() < MAX_PER_MESSAGE and int(outbox[i][0]) == t0 + cs.size():
			cs.append(outbox[i][1])
			i += 1
		out.append({"type": "in", "t": t0, "cs": cs})
	return out


static func ints(c: Variant) -> Array:
	var a: Array = c if c is Array else []
	return [int(a[0]), int(a[1]), int(a[2]), int(a[3])] if a.size() == 4 else [-1, -1, -1, -1]


## Applies a relay message to the rollback. Returns what happened: "start", "in", "leave", "desync" or "".
static func apply(rb: Rollback, msg: Dictionary) -> String:
	match str(msg.get("type", "")):
		"start":
			var left: Dictionary = msg.get("left", {})
			for s in left:
				rb.leave(int(s), int(left[s]))
			return "start"
		"in":
			var t := int(msg.get("t", -1))
			var cs: Array = msg.get("cs", [])
			for k in cs.size():
				rb.remote_input(int(msg.get("s", -1)), t + k, ints(cs[k]))
			return "in"
		"leave":
			rb.leave(int(msg.get("s", -1)), int(msg.get("t", 0)))
			return "leave"
		"desync":
			return "desync"
	return ""
