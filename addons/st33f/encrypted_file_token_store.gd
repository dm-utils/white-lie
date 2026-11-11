class_name St33fEncryptedFileTokenStore
extends St33fTokenStore
## Token in an encrypted file. Key = SHA-256 of the device id plus a random per-install key file,
## so a copied save folder alone does not reveal the token.

var dir := "user://st33f"


func _path() -> String:
	return dir.path_join("session.bin")


func _key() -> String:
	var key_file := dir.path_join("install.key")
	if not FileAccess.file_exists(key_file):
		DirAccess.make_dir_recursive_absolute(dir)
		var f := FileAccess.open(key_file, FileAccess.WRITE)
		if f == null:
			return ""
		f.store_string(Crypto.new().generate_random_bytes(32).hex_encode())
		f.close()
	var install := FileAccess.get_file_as_string(key_file).strip_edges()
	# OS.get_unique_id() is not available in browsers
	var device := "web" if OS.has_feature("web") else OS.get_unique_id()
	return (device + ":" + install).sha256_text()


func load_token() -> String:
	if not FileAccess.file_exists(_path()):
		return ""
	var key := _key()
	if key == "":
		return ""
	var f := FileAccess.open_encrypted_with_pass(_path(), FileAccess.READ, key)
	if f == null:
		return ""
	return f.get_as_text().strip_edges()


func save_token(token: String) -> void:
	var key := _key()
	if key == "":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open_encrypted_with_pass(_path(), FileAccess.WRITE, key)
	if f != null:
		f.store_string(token)
		f.close()


func clear() -> void:
	if FileAccess.file_exists(_path()):
		DirAccess.remove_absolute(_path())
