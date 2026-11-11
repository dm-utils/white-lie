class_name St33fTokenStore
extends RefCounted
## Where the session token lives. Never in plain settings, logs or crash reports.
## This base class keeps it in memory only (tests); the game uses St33fEncryptedFileTokenStore
## (or a native keychain plugin later).

var _token := ""


func load_token() -> String:
	return _token


func save_token(token: String) -> void:
	_token = token


func clear() -> void:
	_token = ""
