class_name SaveLock
extends RefCounted

# Only a proved-dead owner may be reclaimed. Age is never evidence of death.
const OWNER_FILE := "owner.json"
const MAX_OWNER_BYTES := 4096

var _path := ""
var _token := ""


func acquire(lock_path: String) -> Error:
	if not _path.is_empty():
		return ERR_ALREADY_IN_USE
	var error := DirAccess.make_dir_absolute(lock_path)
	if error != OK and DirAccess.dir_exists_absolute(lock_path):
		if not _recover_dead_owner(lock_path):
			return ERR_BUSY
		error = DirAccess.make_dir_absolute(lock_path)
	if error != OK:
		return ERR_BUSY if DirAccess.dir_exists_absolute(lock_path) else error
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	if token.length() != 32:
		DirAccess.remove_absolute(lock_path)
		return ERR_CANT_CREATE
	var file := FileAccess.open(lock_path.path_join(OWNER_FILE), FileAccess.WRITE)
	if file == null:
		error = FileAccess.get_open_error()
		DirAccess.remove_absolute(lock_path)
		return error
	file.store_string(JSON.stringify({"version": 1, "pid": OS.get_process_id(), "platform": OS.get_name(), "token": token}))
	file.flush()
	error = file.get_error()
	file.close()
	var owner := _read_owner(lock_path)
	if error != OK or owner.get("token", "") != token:
		# A partial identity is conservatively retained; no save may begin.
		return error if error != OK else ERR_FILE_CANT_WRITE
	_path = lock_path
	_token = token
	return OK


func release() -> void:
	if _path.is_empty():
		return
	# Never delete another owner's metadata after an external replacement.
	if _read_owner(_path).get("token", "") == _token:
		DirAccess.remove_absolute(_path.path_join(OWNER_FILE))
		DirAccess.remove_absolute(_path)
	_path = ""
	_token = ""


func _read_owner(lock_path: String) -> Dictionary:
	var file := FileAccess.open(lock_path.path_join(OWNER_FILE), FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_OWNER_BYTES:
		file.close()
		return {}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		return {}
	var owner: Dictionary = json.data
	var pid: Variant = owner.get("pid")
	var token: Variant = owner.get("token")
	if owner.get("version") != 1 or not (pid is int or pid is float):
		return {}
	if not is_finite(float(pid)) or pid < 1 or pid > 4294967295 or pid != floor(float(pid)):
		return {}
	if not token is String or not _valid_token(token):
		return {}
	if owner.get("platform") != OS.get_name():
		return {}
	return owner


func _valid_token(token: String) -> bool:
	if token.length() != 32:
		return false
	for index in range(token.length()):
		var code := token.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


func _owner_is_dead(owner: Dictionary) -> bool:
	if owner.is_empty() or OS.get_name() != "Windows" or int(owner.pid) == OS.get_process_id():
		return false
	# Godot 4.6's is_process_running contract covers spawned children only.
	# Enumerate all Windows processes instead; failures/partial output are unknown.
	var system_root := OS.get_environment("SystemRoot")
	if system_root.is_empty():
		return false
	var tasklist := system_root.path_join("System32").path_join("tasklist.exe")
	if not FileAccess.file_exists(tasklist):
		return false
	var output: Array = []
	if OS.execute(tasklist, PackedStringArray(["/FO", "CSV", "/NH"]), output, true) != 0 or output.size() != 1:
		return false
	var row := RegEx.new()
	if row.compile('^"(?:[^\\"]|\\"\\")*","([0-9]+)","(?:[^\\"]|\\"\\")*","[0-9]+","(?:[^\\"]|\\"\\")*"$') != OK:
		return false
	var found_self := false
	for line in String(output[0]).split("\n", false):
		line = line.strip_edges()
		if line.is_empty():
			continue
		var match := row.search(line)
		if match == null:
			return false
		var pid := match.get_string(1).to_int()
		if pid == int(owner.pid):
			return false
		if pid == OS.get_process_id():
			found_self = true
	return found_self


func _recover_dead_owner(lock_path: String) -> bool:
	var owner := _read_owner(lock_path)
	if not _owner_is_dead(owner):
		return false
	# Binding the claim to the observed owner token prevents competing recovery.
	# Moving the whole claimed directory avoids a remove/recreate race at lock_path.
	var claim := lock_path.path_join("reclaim-" + String(owner.token))
	if DirAccess.make_dir_absolute(claim) != OK:
		return false
	if not _owner_is_dead(owner) or _read_owner(lock_path) != owner:
		DirAccess.remove_absolute(claim)
		return false
	var quarantine := lock_path + ".abandoned-" + String(owner.token) + "-" + Crypto.new().generate_random_bytes(16).hex_encode()
	if FileAccess.file_exists(quarantine) or DirAccess.dir_exists_absolute(quarantine):
		DirAccess.remove_absolute(claim)
		return false
	if DirAccess.rename_absolute(lock_path, quarantine) != OK:
		DirAccess.remove_absolute(claim)
		return false
	# No operation below targets the now-available original path. Unknown extras
	# (including a recovery interrupted by another crash) remain for inspection.
	var contents := DirAccess.open(quarantine)
	var claimed := DirAccess.open(quarantine.path_join(claim.get_file()))
	if contents == null or claimed == null:
		return true
	if contents.get_files() != PackedStringArray([OWNER_FILE]) or contents.get_directories() != PackedStringArray([claim.get_file()]):
		return true
	if not claimed.get_files().is_empty() or not claimed.get_directories().is_empty():
		return true
	DirAccess.remove_absolute(quarantine.path_join(OWNER_FILE))
	DirAccess.remove_absolute(quarantine.path_join(claim.get_file()))
	DirAccess.remove_absolute(quarantine)
	return true
