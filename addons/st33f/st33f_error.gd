class_name St33fError
extends RefCounted
## An error from the platform (or the network). `code` is the server's stable snake_case code,
## or "network" when no answer came back at all.

var status: int
var code: String
var message: String
var data: Dictionary


func _init(p_status: int = 0, p_code: String = "", p_message: String = "", p_data: Dictionary = {}) -> void:
	status = p_status
	code = p_code
	message = p_message
	data = p_data


## Worth retrying later: no connection, rate limited, or a server-side problem.
func is_transient() -> bool:
	return status == 0 or status == 429 or status >= 500


## Seconds the server asked us to wait (0 when it did not say).
func retry_after() -> int:
	return int(data.get("retryAfter", 0))


func is_signed_out() -> bool:
	return code == "signed_out"


func _to_string() -> String:
	return "St33fError(%d %s)" % [status, code]
