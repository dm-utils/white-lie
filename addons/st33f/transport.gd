class_name St33fTransport
extends RefCounted
## How requests leave the game. Swappable: St33fHttpTransport in the game, a scripted one in tests.
## request() / request_raw() return {"status": int, "body": String}; status 0 means no answer
## (offline, timeout, DNS).


func request(_method: int, _url: String, _headers: PackedStringArray, _body: String) -> Dictionary:
	return {"status": 0, "body": ""}


## Binary body (screenshots). Default: not supported.
func request_raw(_method: int, _url: String, _headers: PackedStringArray, _body: PackedByteArray) -> Dictionary:
	return {"status": 0, "body": ""}
