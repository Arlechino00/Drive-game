class_name PlayerRecords
extends RefCounted

const MAX_NAME_LENGTH := 24
const MAX_ENTRIES_PER_PARTITION := 100
const FORMAT_VERSION := 1
const MAX_FILE_BYTES := 1048576

var player_name: String = ""
var save_path: String
var _entries: Array[Dictionary] = []


func _init(storage_path: String = "user://player_records.cfg") -> void:
	save_path = storage_path


func load_records() -> Error:
	player_name = ""
	_entries.clear()
	if not FileAccess.file_exists(save_path):
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
	if config.get_value("meta", "version", null) != FORMAT_VERSION:
		return ERR_FILE_CORRUPT
	var saved_name: Variant = config.get_value("profile", "name", "")
	if saved_name is String and _valid_name(saved_name):
		player_name = _display_name(saved_name)
	var saved_entries: Variant = config.get_value("records", "entries", [])
	if saved_entries is Array:
		for value: Variant in saved_entries:
			if value is Dictionary and _valid_entry(value):
				_store_best(_entries, _entry(value.name, value.mode, value.score, float(value.distance), value.resumed, value.escapes))
	_trim_entries(_entries)
	return OK


func save_player_name(raw: String) -> Error:
	if not _valid_name(raw):
		return ERR_INVALID_PARAMETER
	var display := _display_name(raw)
	return _save(display, _entries, true)


func normalize_name(raw: String) -> String:
	return _display_name(raw).to_lower()


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
	var lock_path := save_path + ".lock"
	var error := DirAccess.make_dir_absolute(lock_path)
	if error != OK:
		return ERR_BUSY if DirAccess.dir_exists_absolute(lock_path) else error
	error = _save_locked(name, entries, update_name)
	DirAccess.remove_absolute(lock_path)
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
	var config := ConfigFile.new()
	config.set_value("meta", "version", FORMAT_VERSION)
	config.set_value("profile", "name", saved_name)
	config.set_value("records", "entries", latest._entries)
	var temporary_path := save_path + ".tmp"
	error = config.save(temporary_path)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(temporary_path, save_path)
	if error != OK:
		DirAccess.remove_absolute(temporary_path)
	else:
		player_name = saved_name
		_entries = latest._entries
	return error
