extends SceneTree

class ExportedAccess extends SecretAccess:
	var executable_path: String = ""
	var exported: bool = true

	func _is_exported_build() -> bool:
		return exported

	func _executable_path() -> String:
		return executable_path

var failures := 0
var paths: PackedStringArray = []
var prefix := "user://test-persistence-config-%s" % Time.get_ticks_usec()


func _initialize() -> void:
	_test_refresh()
	_test_recovery()
	_test_external_configuration()
	for path in paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
		DirAccess.remove_absolute(path + ".lock")
	DirAccess.remove_absolute(prefix)
	if failures == 0:
		print("PERSISTENCE CONFIG PASS: atomic refresh, preserved recovery, external configuration and live code changes")
	quit(1 if failures else 0)


func _test_refresh() -> void:
	var path := _path("refresh")
	var first: Variant = PlayerRecords.new(path)
	var second: Variant = PlayerRecords.new(path)
	_check(first.has_method("display_player_name"), "validated display-name API exists for unsaved play")
	if first.has_method("display_player_name"):
		_check(first.display_player_name("  ȘTEFAN  李  ") == "ȘTEFAN 李", "unsaved display preserves Unicode and casing while normalizing spacing")
		_check(first.display_player_name("bad\nname").is_empty() and first.display_player_name(" ").is_empty() and first.display_player_name("x".repeat(25)).is_empty(), "unsaved display rejects invalid names before fallback")
	_check(first.save_player_name("Alice") == OK and first.record_run("Alice", 0, 50, 10.0) == OK, "valid cache fixture saved")
	_check(second.load_records() == OK, "second instance reads first")
	_check(first.record_run("Bob", 0, 90, 20.0) == OK, "another instance saves new leaderboard row")
	_check(second.load_records() == OK and second.top_entries(0).size() == 2, "explicit refresh reads another instance's newer rows")
	var cached: Array[Dictionary] = second.top_entries(0)
	DirAccess.remove_absolute(path)
	_check(DirAccess.make_dir_absolute(path) == OK, "invalid directory storage fixture created")
	_check(second.load_records() != OK and second.player_name == "Alice" and second.top_entries(0) == cached, "directory storage failure retains valid cache")
	DirAccess.remove_absolute(path)
	_write(path, "[meta]\nversion=99\n[profile]\nname=\"Future\"\n")
	_check(second.load_records() != OK, "unsupported refresh rejected")
	_check(second.player_name == "Alice" and second.top_entries(0) == cached, "failed refresh keeps prior name and rows")
	_check(second.save_player_name("Lost") != OK, "ordinary save refuses unsupported original")
	DirAccess.remove_absolute(path)
	_check(second.load_records() == OK and second.player_name.is_empty() and second.top_entries(0).is_empty(), "missing durable file refresh commits empty cache")


func _test_recovery() -> void:
	for fixture in ["[profile]\nname=\"Incomplete\"\n", "[meta]\nversion=99\n[future]\nopaque=\"Preserve Ș 李\"\n", "oversized".repeat(PlayerRecords.MAX_FILE_BYTES / 9 + 1)]:
		var path := _path("recover-%s" % paths.size())
		_write(path, fixture)
		var original := FileAccess.get_file_as_bytes(path)
		var records: Variant = PlayerRecords.new(path)
		_check(records.load_records() != OK, "damaged or future-format fixture rejected")
		_check(records.has_method("recover_records"), "explicit preserved recovery API exists")
		if not records.has_method("recover_records"):
			continue
		_check(DirAccess.make_dir_absolute(path + ".lock") == OK, "recovery contention fixture created")
		_check(records.recover_records() == ERR_BUSY and records.last_recovery_backup_path.is_empty(), "held writer lock rejects recovery")
		_check(FileAccess.get_file_as_bytes(path) == original and DirAccess.dir_exists_absolute(path + ".lock"), "recovery contention preserves original and owner's lock")
		DirAccess.remove_absolute(path + ".lock")
		_check(records.recover_records() == OK, "damaged original recovered")
		var backup: String = records.last_recovery_backup_path
		paths.append(backup)
		_check(not backup.is_empty() and backup != path and FileAccess.file_exists(backup), "recovery reports separate preserved backup")
		_check(FileAccess.get_file_as_bytes(backup) == original, "original bytes remain exact in backup")
		_check(records.save_player_name("Recovered") == OK and records.record_run("Recovered", 0, 100, 20.0) == OK, "recovered file accepts profile and runs")
		var loaded: Variant = PlayerRecords.new(path)
		_check(loaded.load_records() == OK and loaded.player_name == "Recovered" and loaded.top_entries(0)[0].score == 100, "recovered supported file survives reload")
		_check(loaded.recover_records() == OK and loaded.last_recovery_backup_path.is_empty(), "valid supported file refresh needs no backup")
		_write(path, fixture)
		_check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "recovery write-failure fixture created")
		var cached: Array[Dictionary] = records.top_entries(0)
		_check(records.recover_records() != OK, "failed recovery write reported")
		paths.append(records.last_recovery_backup_path)
		_check(FileAccess.get_file_as_bytes(path) == original and records.player_name == "Recovered" and records.top_entries(0) == cached, "failed recovery preserves original and validated cache")
		_check(not DirAccess.dir_exists_absolute(path + ".lock"), "failed recovery releases lock")
		DirAccess.remove_absolute(path + ".tmp")
		_check(records.recover_records() == OK, "recovery retries after write failure")
		paths.append(records.last_recovery_backup_path)
		_check(records.last_recovery_backup_path != backup and FileAccess.get_file_as_bytes(backup) == original, "later backups never overwrite first original")
		_check(records.player_name == "Recovered" and records.top_entries(0) == cached, "recovery retains already validated cache")


func _test_external_configuration() -> void:
	_check(DirAccess.make_dir_absolute(prefix) == OK, "isolated executable directory created")
	var external := prefix.path_join("secret_mode.cfg")
	paths.append(external)
	var access: Variant = ExportedAccess.new(_path("access"))
	access.executable_path = prefix.path_join("game.exe")
	_check(access.has_method("get_configuration_path"), "configuration selection API exists")
	if not access.has_method("get_configuration_path"):
		return
	_check(access.get_configuration_path() == "res://config/secret_mode.cfg", "export without loose file uses bundled config")
	_configuration(external, "ExternalAccess", "ExternalResume")
	_check(access.get_configuration_path() == external, "export prefers file beside executable")
	_check(access.load_access() == OK and access.unlock("ExternalAccess"), "external access unlocks and persists fingerprint")
	_check(access.validate_resume_code("ExternalResume"), "external resume phrase works")
	_configuration(external, "ChangedAccess", "ChangedResume")
	_check(access.load_access() == OK and not access.secret_unlocked, "changed external access invalidates old fingerprint")
	_check(not access.unlock("ExternalAccess") and access.unlock("ChangedAccess"), "changed access phrase takes effect immediately")
	_check(not access.validate_resume_code("ExternalResume") and access.validate_resume_code("ChangedResume"), "changed resume phrase takes effect immediately")
	_configuration(external, "", "")
	_check(access.load_access() != OK and not access.secret_unlocked and not access.unlock("SYSTEMATIC"), "invalid external access fails closed without bundled fallback")
	_check(not access.validate_resume_code("SYSTEMATIC-RESUME"), "invalid external resume fails closed")
	DirAccess.remove_absolute(external)
	_check(access.get_configuration_path() == "res://config/secret_mode.cfg", "removing loose file restores bundled selection")
	_check(DirAccess.make_dir_absolute(external) == OK, "invalid external path fixture created")
	_check(access.get_configuration_path() == external and access.load_access() != OK and not access.secret_unlocked, "invalid external path fails closed rather than selecting bundled code")
	DirAccess.remove_absolute(external)
	_configuration(external, "ExternalAgain", "ResumeAgain")
	_check(access.unlock("ExternalAgain") and access.validate_resume_code("ResumeAgain"), "adding loose file takes effect in running instance")
	access.exported = false
	_check(access.get_configuration_path() == "res://config/secret_mode.cfg", "source project retains bundled source config")
	var explicit_path := _path("explicit")
	_configuration(explicit_path, "ExplicitAccess", "ExplicitResume")
	var explicit: Variant = ExportedAccess.new(_path("explicit-save"), explicit_path)
	explicit.executable_path = access.executable_path
	_check(explicit.get_configuration_path() == explicit_path and explicit.unlock("ExplicitAccess") and explicit.validate_resume_code("ExplicitResume"), "explicit config path overrides exported selection")


func _configuration(path: String, access_code: String, resume_code: String) -> void:
	var config := ConfigFile.new()
	config.set_value("secret_mode", "access_code", access_code)
	config.set_value("secret_mode", "resume_code", resume_code)
	_check(config.save(path) == OK, "event config fixture saved")


func _write(path: String, value: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func _path(suffix: String) -> String:
	var path := prefix + "-" + suffix + ".cfg"
	paths.append(path)
	return path


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("PERSISTENCE CONFIG FAIL: " + label)
