class_name PlayerRecords
extends RefCounted

const MAX_NAME_LENGTH := 24
const MAX_ENTRIES_PER_PARTITION := 100
const FORMAT_VERSION := 1
const MAX_FILE_BYTES := 1048576
const SAVE_LOCK_SCRIPT := preload("res://scripts/save_lock.gd")

var player_name: String = ""
var save_path: String
var last_recovery_backup_path: String = ""
var _entries: Array[Dictionary] = []


func _init(storage_path: String = "user://player_records.cfg") -> void:
	save_path = storage_path


func load_records() -> Error:
	if not FileAccess.file_exists(save_path):
		if DirAccess.dir_exists_absolute(save_path):
			return ERR_FILE_CANT_READ
		player_name = ""
		_entries.clear()
		return OK
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var oversized := file.get_length() > MAX_FILE_BYTES
	file.close()
	if oversized:
		return ERR_FILE_CORRUPT
	var config := ConfigFile.new()
	var error := config.load(save_path)
	if error != OK:
		return error
	if config.get_value("meta", "version", -1) != FORMAT_VERSION:
		return ERR_FILE_CORRUPT
	# Parse into a candidate: failed refreshes must retain the last valid cache.
	var loaded_name := ""
	var loaded_entries: Array[Dictionary] = []
	var saved_name: Variant = config.get_value("profile", "name", "")
	if saved_name is String and _valid_name(saved_name):
		loaded_name = _display_name(saved_name)
	var saved_entries: Variant = config.get_value("records", "entries", [])
	if saved_entries is Array:
		for value: Variant in saved_entries:
			if value is Dictionary and _valid_entry(value):
				_store_best(loaded_entries, _entry(value.name, value.mode, value.score, float(value.distance), value.resumed, value.escapes))
	_trim_entries(loaded_entries)
	player_name = loaded_name
	_entries = loaded_entries
	return OK


func recover_records() -> Error:
	# Recovery is explicit. Even unsupported future-format data is preserved
	# byte-for-byte before a current-format replacement is attempted.
	last_recovery_backup_path = ""
	var lock := SAVE_LOCK_SCRIPT.new()
	var error := lock.acquire(save_path + ".lock")
	if error != OK:
		return error
	error = _recover_locked()
	lock.release()
	return error


func _recover_locked() -> Error:
	var latest := PlayerRecords.new(save_path)
	var error := latest.load_records()
	if error == OK:
		player_name = latest.player_name
		_entries = latest._entries
		return OK
	if error != ERR_FILE_CORRUPT and error != ERR_PARSE_ERROR:
		return error
	var backup_prefix := save_path + ".recovered-%s" % Time.get_ticks_usec()
	var backup_path := backup_prefix
	var suffix := 0
	while FileAccess.file_exists(backup_path) or DirAccess.dir_exists_absolute(backup_path):
		suffix += 1
		backup_path = backup_prefix + "-%s" % suffix
	error = DirAccess.copy_absolute(save_path, backup_path)
	if error != OK:
		return error
	last_recovery_backup_path = backup_path
	# Keep any previously validated cache. A first load recovers to empty data.
	return _write_records(player_name, _entries)


func save_player_name(raw: String) -> Error:
	if not _valid_name(raw):
		return ERR_INVALID_PARAMETER
	var display := _display_name(raw)
	return _save(display, _entries, true)


func normalize_name(raw: String) -> String:
	return _display_name(raw).to_lower()


func display_player_name(raw: String) -> String:
	# Share profile validation with unsaved play when storage is unavailable.
	return _display_name(raw) if _valid_name(raw) else ""


func record_run(name: String, mode: int, score: int, distance: float, resumed: bool = false, escapes: int = 0) -> Error:
	var entry := _entry(name, mode, score, distance, resumed, escapes)
	if not _valid_name(name) or not _valid_entry(entry):
		return ERR_INVALID_PARAMETER
	var candidate: Array[Dictionary] = _entries.duplicate(true)
	_store_best(candidate, entry)
	_trim_entries(candidate)
	return _save(player_name, candidate, false)


func top_entries(mode: int, resumed: bool = false, limit: int = 10) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if limit <= 0 or mode < 0 or mode > 2 or (resumed and mode != 2):
		return result
	for entry in _entries:
		if entry.mode == mode and entry.resumed == resumed:
			result.append(entry.duplicate(true))
	result.sort_custom(_ranks_before)
	result.resize(mini(result.size(), mini(limit, MAX_ENTRIES_PER_PARTITION)))
	return result


func _entry(name: String, mode: int, score: int, distance: float, resumed: bool, escapes: int) -> Dictionary:
	return {"name": _display_name(name), "mode": mode, "score": score, "distance": distance, "resumed": resumed, "escapes": escapes}


func _valid_entry(entry: Dictionary) -> bool:
	for key in ["name", "mode", "score", "distance", "resumed", "escapes"]:
		if not entry.has(key):
			return false
	if not entry.name is String or not _valid_name(entry.name):
		return false
	if not entry.mode is int or entry.mode < 0 or entry.mode > 2:
		return false
	if not entry.score is int or entry.score < 0 or not entry.escapes is int or entry.escapes < 0:
		return false
	if not (entry.distance is float or entry.distance is int) or not is_finite(float(entry.distance)) or entry.distance < 0.0:
		return false
	return entry.resumed is bool and not (entry.resumed and entry.mode != 2)


func _valid_name(raw: String) -> bool:
	# Reject controls before trimming: names cannot conceal line breaks or bidi text.
	for index in range(raw.length()):
		var code := raw.unicode_at(index)
		if code < 32 or (code >= 127 and code <= 159) or code == 173 or code == 0xFEFF or (code >= 0x200B and code <= 0x200F) or (code >= 0x2028 and code <= 0x202E) or (code >= 0x2060 and code <= 0x206F):
			return false
	var display := _display_name(raw)
	return not display.is_empty() and display.length() <= MAX_NAME_LENGTH


func _display_name(raw: String) -> String:
	var result := ""
	var pending_space := false
	for index in range(raw.length()):
		var code := raw.unicode_at(index)
		if code == 32 or code == 0x00A0 or code == 0x1680 or (code >= 0x2000 and code <= 0x200A) or code == 0x202F or code == 0x205F or code == 0x3000:
			pending_space = not result.is_empty()
			continue
		if pending_space:
			result += " "
			pending_space = false
		result += String.chr(code)
	return result


func _store_best(entries: Array[Dictionary], candidate: Dictionary) -> void:
	var normalized := normalize_name(candidate.name)
	for index in range(entries.size()):
		var existing := entries[index]
		if existing.mode == candidate.mode and existing.resumed == candidate.resumed and normalize_name(existing.name) == normalized:
			if _ranks_before(candidate, existing):
				entries[index] = candidate
			return
	entries.append(candidate)


func _ranks_before(left: Dictionary, right: Dictionary) -> bool:
	if left.score != right.score:
		return left.score > right.score
	if left.distance != right.distance:
		return left.distance > right.distance
	if left.escapes != right.escapes:
		return left.escapes > right.escapes
	var left_name := normalize_name(left.name)
	var right_name := normalize_name(right.name)
	return left_name < right_name if left_name != right_name else left.name < right.name


func _trim_entries(entries: Array[Dictionary]) -> void:
	entries.sort_custom(_ranks_before)
	var counts: Dictionary = {}
	var kept: Array[Dictionary] = []
	for entry in entries:
		var partition := "%s:%s" % [entry.mode, entry.resumed]
		var count: int = counts.get(partition, 0)
		if count < MAX_ENTRIES_PER_PARTITION:
			kept.append(entry)
			counts[partition] = count + 1
	entries.assign(kept)


func _save(name: String, entries: Array[Dictionary], update_name: bool) -> Error:
	# Hold the same directory lock across reload, merge and atomic replacement.
	# Contention fails immediately; never touch another writer's temporary file.
	var lock := SAVE_LOCK_SCRIPT.new()
	var error := lock.acquire(save_path + ".lock")
	if error != OK:
		return error
	error = _save_locked(name, entries, update_name)
	lock.release()
	return error


func _save_locked(name: String, entries: Array[Dictionary], update_name: bool) -> Error:
	# Loading into a separate object keeps this cache intact on every failure.
	var latest := PlayerRecords.new(save_path)
	var error := latest.load_records()
	if error != OK:
		return error
	for entry in entries:
		_store_best(latest._entries, entry)
	_trim_entries(latest._entries)
	var saved_name := name if update_name or not FileAccess.file_exists(save_path) else latest.player_name
	return _write_records(saved_name, latest._entries)


func _write_records(name: String, entries: Array[Dictionary]) -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", FORMAT_VERSION)
	config.set_value("profile", "name", name)
	config.set_value("records", "entries", entries)
	var temporary_path := save_path + ".tmp"
	var error := config.save(temporary_path)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(temporary_path, save_path)
	if error != OK:
		DirAccess.remove_absolute(temporary_path)
	else:
		player_name = name
		_entries = entries.duplicate(true)
	return error
