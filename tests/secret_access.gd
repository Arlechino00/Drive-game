extends SceneTree

# An unreadable file is injected at the I/O boundary; changing OS permissions
# would make this failure nondeterministic across machines and test runners.
class UnreadableAccess:
	extends "res://scripts/secret_access.gd"

	func _load_ledger() -> Error:
		return ERR_FILE_CANT_READ

var failures: int = 0
var paths: PackedStringArray = []
var prefix := "user://test-secret-access-%s" % Time.get_ticks_usec()

func _initialize() -> void:
	var script: Script = load("res://scripts/secret_access.gd")
	var probe: Variant = script.new()
	if not probe.has_method("validate_resume_code"):
		_check(false, "resume code is reusable and read from shared configuration")
		quit(1)
		return
	_test_unlock(script)
	_test_resume(script)
	_test_legacy_and_storage(script)
	_test_corrupt_recovery(script)
	for path in paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
	if failures == 0:
		print("SECRET ACCESS PASS: configured access/resume, persistent unlock, reusable code, live manual edits, missing/invalid codes, damaged-save recovery and storage failures")
	quit(1 if failures else 0)

func _test_unlock(script: Script) -> void:
	var path := _path("unlock")
	var config_path := _configuration("unlock", "CustomPhrase42", "ResumePhrase42")
	var access: Variant = script.new(path, config_path)
	_check(access.load_access() == OK and not access.secret_unlocked, "fresh access locked")
	_check(not access.unlock("wrong") and not access.unlock("customphrase42"), "wrong/case-mismatched access rejected")
	_check(access.unlock("CustomPhrase42"), "configured access unlocks")
	var loaded: Variant = script.new(path, config_path)
	_check(loaded.load_access() == OK and loaded.secret_unlocked, "unlock persists")
	var config := ConfigFile.new()
	config.load(config_path)
	config.set_value("secret_mode", "resume_code", "ChangedResume")
	config.save(config_path)
	_check(loaded.load_access() == OK and loaded.secret_unlocked, "resume edit preserves access unlock")
	config.set_value("secret_mode", "access_code", "ChangedAccess")
	config.save(config_path)
	_check(loaded.load_access() == OK and not loaded.secret_unlocked, "access edit revokes unlock")
	_check(not loaded.unlock("CustomPhrase42") and loaded.unlock("ChangedAccess"), "current access works")
	config.load(path)
	_check(config.get_value("access", "unlock_fingerprint", "") == "ChangedAccess".sha256_text(), "save contains fingerprint only")

func _test_resume(script: Script) -> void:
	var path := _path("resume")
	var config_path := _configuration("resume", "AccessOnly", "Fixed-Resume")
	var access: Variant = script.new(path, config_path)
	_check(not access.validate_resume_code("wrong") and not access.validate_resume_code("AccessOnly"), "resume has separate configured code")
	_check(not access.validate_resume_code("") and not access.validate_resume_code("fixed-resume"), "blank and wrong-case resume rejected")
	for attempt in range(20):
		_check(access.validate_resume_code(" Fixed-Resume "), "code remains reusable")
	_check(not FileAccess.file_exists(path), "resume needs no consumption save")
	var other: Variant = script.new(path, config_path)
	_check(other.validate_resume_code("Fixed-Resume"), "code works in later session")
	var config := ConfigFile.new()
	config.load(config_path)
	config.set_value("secret_mode", "resume_code", "Manually-Replaced")
	config.save(config_path)
	_check(not access.validate_resume_code("Fixed-Resume") and access.validate_resume_code("Manually-Replaced"), "manual edits read immediately")
	_check(other.validate_resume_code("Manually-Replaced"), "all instances use latest code")
	config.set_value("secret_mode", "resume_code", "   ")
	config.save(config_path)
	_check(not access.validate_resume_code("") and not access.validate_resume_code("Manually-Replaced"), "empty config disables resume")
	config.set_value("secret_mode", "resume_code", 42)
	config.save(config_path)
	_check(not access.validate_resume_code("42"), "non-string resume rejected")
	config.erase_section_key("secret_mode", "resume_code")
	config.save(config_path)
	_check(access.unlock("AccessOnly") and not access.validate_resume_code("SYSTEMATIC-RESUME"), "missing resume has no fallback and access still works")
	access = script.new(_path("missing-save"), _path("missing-config"))
	_check(access.load_access() != OK and not access.unlock("SYSTEMATIC"), "missing file has no access fallback")
	_check(not access.validate_resume_code("SYSTEMATIC-RESUME"), "missing file has no resume fallback")
	config_path = _configuration("empty-access", "   ", "ConfiguredResume")
	access = script.new(_path("empty-save"), config_path)
	_check(not access.unlock("") and access.validate_resume_code("ConfiguredResume"), "resume validation independent of access key")

func _test_legacy_and_storage(script: Script) -> void:
	var path := _path("legacy")
	var config_path := _configuration("legacy", "OldAccess", "NewResume")
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("access", "unlock_fingerprint", "OldAccess".sha256_text())
	config.set_value("resume", "hashes", ["A".repeat(32).sha256_text()])
	config.save(path)
	var access: Variant = script.new(path, config_path)
	_check(access.load_access() == OK and access.secret_unlocked, "old unlock save compatible")
	_check(not access.validate_resume_code("A".repeat(32)) and access.validate_resume_code("NewResume"), "old issued codes cannot bypass configured resume")
	config.set_value("access", "unlock_fingerprint", true)
	config.save(path)
	_check(access.load_access() != OK and not access.secret_unlocked, "bad unlock save fails closed")
	_check(access.validate_resume_code("NewResume"), "resume independent of obsolete save state")
	path = _path("write-error")
	access = script.new(path, config_path)
	_check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "write failure fixture")
	_check(not access.unlock("OldAccess") and not access.secret_unlocked, "failed unlock save stays locked")
	_check(not access.configuration_error.is_empty(), "failed unlock save reports storage problem")
	_check(access.validate_resume_code("NewResume"), "resume does not require writable save")
	DirAccess.remove_absolute(path + ".tmp")
	_check(DirAccess.make_dir_absolute(path + ".lock") == OK, "contention fixture")
	_check(not access.unlock("OldAccess") and access.validate_resume_code("NewResume"), "unlock contention does not block resume read")
	_check(not access.configuration_error.is_empty(), "unlock contention reports unavailable storage")
	DirAccess.remove_absolute(path + ".lock")
	_check(access.unlock("OldAccess"), "unlock retries after lock release")
	_check(access.configuration_error.is_empty(), "successful retry clears storage error")

func _test_corrupt_recovery(script: Script) -> void:
	var config_path := _configuration("recovery", "CurrentAccess", "CurrentResume")
	for fixture in ["[meta]\nversion=1\n[access]\nunlock_fingerprint=\"truncated\"\n", "[meta]\nversion=1\n[access]\nunlock_fingerprint=true\n"]:
		var path := _path("recovery-%s" % paths.size())
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(fixture)
		file.close()
		var access: Variant = script.new(path, config_path)
		_check(access.load_access() != OK and not access.secret_unlocked, "damaged saved unlock cannot grant access")
		_check(not access.unlock("wrong") and not access.secret_unlocked, "wrong phrase cannot repair damaged unlock")
		_check(FileAccess.get_file_as_string(path) == fixture, "wrong phrase preserves damaged save bytes")
		_check(access.configuration_error.is_empty(), "wrong phrase is distinguished from configuration or storage failure")
		_check(access.unlock(" CurrentAccess ") and access.secret_unlocked, "current phrase repairs damaged unlock")
		var loaded: Variant = script.new(path, config_path)
		_check(loaded.load_access() == OK and loaded.secret_unlocked, "repaired unlock survives reload")
		_check(not DirAccess.dir_exists_absolute(path + ".lock") and not FileAccess.file_exists(path + ".tmp"), "repair releases lock and commits temporary save")
	var path := _path("recovery-config-errors")
	var fixture := "[meta]\nversion=1\n[access]\nunlock_fingerprint=\"truncated\"\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(fixture)
	file.close()
	for invalid_access: Variant in ["   ", 42]:
		var config := ConfigFile.new()
		config.set_value("secret_mode", "access_code", invalid_access)
		config.save(config_path)
		var access: Variant = script.new(path, config_path)
		_check(not access.unlock("CurrentAccess") and not access.secret_unlocked and not access.configuration_error.is_empty(), "invalid access configuration cannot repair unlock")
		_check(FileAccess.get_file_as_string(path) == fixture, "invalid configuration preserves damaged save")
	var access: Variant = script.new(path, _path("recovery-missing-config"))
	_check(not access.unlock("CurrentAccess") and not access.secret_unlocked and not access.configuration_error.is_empty(), "missing access configuration cannot repair unlock")
	_check(FileAccess.get_file_as_string(path) == fixture, "missing configuration preserves damaged save")
	config_path = _configuration("read-error", "CurrentAccess", "CurrentResume")
	var unreadable := UnreadableAccess.new(path, config_path)
	_check(not unreadable.unlock("CurrentAccess") and not unreadable.secret_unlocked, "unreadable saved unlock is not treated as corruption")
	_check(not unreadable.configuration_error.is_empty(), "unreadable saved unlock reports storage problem")
	_check(FileAccess.get_file_as_string(path) == fixture, "unreadable saved unlock is not overwritten")
	access = script.new(path, config_path)
	_check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "damaged save repair write-failure fixture")
	_check(not access.unlock("CurrentAccess") and not access.secret_unlocked and not access.configuration_error.is_empty(), "failed repair reports storage problem and stays locked")
	_check(FileAccess.get_file_as_string(path) == fixture, "failed repair preserves damaged save")
	DirAccess.remove_absolute(path + ".tmp")
	_check(access.unlock("CurrentAccess") and access.configuration_error.is_empty(), "repair succeeds after write failure clears")

func _configuration(suffix: String, access_code: String, resume_code: String) -> String:
	var path := _path(suffix + "-config")
	var config := ConfigFile.new()
	config.set_value("secret_mode", "access_code", access_code)
	config.set_value("secret_mode", "resume_code", resume_code)
	_check(config.save(path) == OK, "configuration saved")
	return path

func _path(suffix: String) -> String:
	var path := prefix + "-" + suffix + ".cfg"
	paths.append(path)
	return path

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("SECRET ACCESS FAIL: " + label)
