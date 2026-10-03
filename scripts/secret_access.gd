class_name SecretAccess
extends RefCounted

const FORMAT_VERSION := 1
const MAX_FILE_BYTES := 131072

var secret_unlocked: bool = false
var configuration_error: String = ""
var resume_configuration_error: String = ""
var save_path: String
var configuration_path: String
var _access_phrase: String = ""
var _unlock_fingerprint: String = ""


func _init(storage_path: String = "user://secret_access.cfg", config_path: String = "res://config/secret_mode.cfg") -> void:
	save_path = storage_path
	configuration_path = config_path


func load_access() -> Error:
	secret_unlocked = false
	_unlock_fingerprint = ""
	var configuration_result := _load_configuration()
	var ledger_result := _load_ledger()
	if configuration_result != OK:
		return configuration_result
	if ledger_result != OK:
		return ledger_result
	secret_unlocked = _unlock_fingerprint == _access_phrase.sha256_text()
	return OK


func unlock(code: String) -> bool:
	configuration_error = ""
	if not _acquire_lock():
		configuration_error = "Secret Mode access is busy or unavailable. Close other game instances and try again."
		return false
	var result := _unlock_locked(code)
	_release_lock()
	return result


func validate_resume_code(code: String) -> bool:
	# Read on every attempt so manual edits take effect without restarting.
	# This reusable phrase has no expiry and is never consumed or rewritten.
	resume_configuration_error = ""
	var config := ConfigFile.new()
	if config.load(configuration_path) != OK:
		resume_configuration_error = "Resume is unavailable. Ask the team."
		return false
	var configured: Variant = config.get_value("secret_mode", "resume_code", "")
	if not configured is String or configured.strip_edges().is_empty():
		resume_configuration_error = "Resume is unavailable. Ask the team."
		return false
	return code.strip_edges() == configured.strip_edges()


func _unlock_locked(code: String) -> bool:
	# A saved fingerprint cannot grant access when damaged, but the current
	# configured phrase can reauthenticate and replace it under this lock.
	var loaded := load_access()
	if not configuration_error.is_empty():
		return false
	if loaded != OK and loaded != ERR_FILE_CORRUPT and loaded != ERR_PARSE_ERROR:
		configuration_error = "Secret Mode access could not be read. Try again or ask the team."
		return false
	if code.strip_edges() != _access_phrase:
		return false
	var fingerprint := _access_phrase.sha256_text()
	if _save(fingerprint) != OK:
		configuration_error = "Secret Mode access could not be saved. Try again or ask the team."
		return false
	_unlock_fingerprint = fingerprint
	secret_unlocked = true
	return true


func _load_configuration() -> Error:
	configuration_error = ""
	_access_phrase = ""
	var config := ConfigFile.new()
	var error := config.load(configuration_path)
	if error != OK:
		configuration_error = "Secret Mode access code is not configured."
		return error
	var configured: Variant = config.get_value("secret_mode", "access_code", "")
	if not configured is String or configured.strip_edges().is_empty():
		configuration_error = "Secret Mode access code is empty or invalid."
		return ERR_UNCONFIGURED
	_access_phrase = configured.strip_edges()
	return OK


func _load_ledger() -> Error:
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
	if config.get_value("meta", "version", 0) != FORMAT_VERSION:
		return ERR_FILE_CORRUPT
	var fingerprint: Variant = config.get_value("access", "unlock_fingerprint", false)
	if not fingerprint is String or (not fingerprint.is_empty() and (fingerprint.length() != 64 or not _is_hex(fingerprint))):
		return ERR_FILE_CORRUPT
	_unlock_fingerprint = fingerprint
	return OK


func _is_hex(value: String) -> bool:
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 70) or (code >= 97 and code <= 102)):
			return false
	return not value.is_empty()


func _acquire_lock() -> bool:
	# Serialize unlock saves from simultaneous local game instances.
	return DirAccess.make_dir_absolute(save_path + ".lock") == OK


func _release_lock() -> void:
	DirAccess.remove_absolute(save_path + ".lock")


func _save(fingerprint: String) -> Error:
	var config := ConfigFile.new()
	config.set_value("meta", "version", FORMAT_VERSION)
	config.set_value("access", "unlock_fingerprint", fingerprint)
	var temporary_path := save_path + ".tmp"
	var error := config.save(temporary_path)
	if error != OK:
		return error
	error = DirAccess.rename_absolute(temporary_path, save_path)
	if error != OK:
		DirAccess.remove_absolute(temporary_path)
	return error
