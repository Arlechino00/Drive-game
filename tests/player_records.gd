extends SceneTree

var failures: int = 0
var paths: PackedStringArray = []
var prefix := "user://test-player-records-%s" % Time.get_ticks_usec()


func _initialize() -> void:
	if not ResourceLoader.exists("res://scripts/player_records.gd"):
		_check(false, "persistent named records module exists")
		quit(1)
		return
	var records_script: Script = load("res://scripts/player_records.gd")
	_test_names(records_script)
	_test_ranking(records_script)
	_test_multiple_instances(records_script)
	_test_bounds(records_script)
	_test_malformed(records_script)
	_test_write_failure(records_script)
	_test_save_transaction_failures(records_script)
	for path in paths:
		DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(path + ".tmp")
		DirAccess.remove_absolute(path + ".lock")
	if failures == 0:
		print("PLAYER RECORDS PASS: Unicode names, best-per-driver partitions, deterministic ties, limits, malformed rows, multi-instance merging, locked atomic saves, write failures")
	quit(1 if failures > 0 else 0)


func _test_names(records_script: Script) -> void:
	var path := _path("names")
	var records: Variant = records_script.new(path)
	_check(records.load_records() == OK and records.player_name == "", "missing profile starts empty")
	_check(records.save_player_name("   ") == ERR_INVALID_PARAMETER, "whitespace name rejected")
	_check(records.save_player_name("Driver\nTwo") == ERR_INVALID_PARAMETER, "control characters rejected")
	_check(records.save_player_name("Driver\u007f") == ERR_INVALID_PARAMETER, "delete control rejected")
	_check(records.save_player_name("Driver\u2028Two") == ERR_INVALID_PARAMETER, "Unicode line separator rejected")
	_check(records.save_player_name("Driver\u2029Two") == ERR_INVALID_PARAMETER, "Unicode paragraph separator rejected")
	_check(records.save_player_name("\u200b") == ERR_INVALID_PARAMETER, "invisible name rejected")
	_check(records.save_player_name("x".repeat(25)) == ERR_INVALID_PARAMETER, "overlong name rejected rather than truncated")
	_check(records.save_player_name("  Ștefan   李 🚗  ") == OK, "visible Unicode name saved")
	_check(records.player_name == "Ștefan 李 🚗", "display name trims and collapses spaces")
	_check(records.normalize_name("  ȘTEFAN  李 🚗 ") == "ștefan 李 🚗", "normalized name is Unicode lowercase")
	_check(records.normalize_name("\u00a0Alex\u2003  Ion\u3000") == "alex ion", "Unicode spaces normalize")
	_check(records.save_player_name("Ș".repeat(24)) == OK, "24 Unicode characters accepted")
	var loaded: Variant = records_script.new(path)
	_check(loaded.load_records() == OK and loaded.player_name == "Ș".repeat(24), "last name survives reload")
	_check(loaded.save_player_name("\u2066Alex") == ERR_INVALID_PARAMETER, "direction control rejected")
	_check(loaded.player_name == "Ș".repeat(24), "invalid name preserves last name")


func _test_ranking(records_script: Script) -> void:
	var path := _path("ranking")
	var records: Variant = records_script.new(path)
	records.load_records()
	_check(records.record_run("Alex", 0, 100, 50.0) == OK, "ordinary result saved")
	_check(records.record_run("  ALEX  ", 0, 50, 200.0) == OK, "lower run accepted without replacing best")
	_check(records.top_entries(0).size() == 1 and records.top_entries(0)[0].score == 100, "normalized driver retains best score")
	_check(records.record_run("alex", 0, 100, 75.0) == OK, "distance breaks equal-score personal tie")
	_check(records.record_run("Zulu", 0, 100, 75.0) == OK, "equal result saved")
	_check(records.record_run("Beta", 0, 100, 75.0) == OK, "third equal result saved")
	_check(records.record_run("Winner", 0, 200, 1.0) == OK, "score outweighs distance")
	_check(records.record_run("Alex", 1, 800, 90.0) == OK, "infinite mode isolated")
	_check(records.record_run("Alex", 2, 700, 80.0, false, 2) == OK, "Secret result isolated")
	_check(records.record_run("Alex", 2, 900, 99.0, true, 3) == OK, "resumed Secret result isolated")
	var ordinary: Array[Dictionary] = records.top_entries(0)
	_check(ordinary.size() == 4, "ordinary partition contains only ordinary results")
	_check(ordinary[0].name == "Winner" and ordinary[1].name == "alex" and ordinary[2].name == "Beta" and ordinary[3].name == "Zulu", "ties sort by normalized driver name")
	_check(records.top_entries(1)[0].score == 800, "infinite partition retained")
	_check(records.top_entries(2)[0].score == 700 and not records.top_entries(2)[0].resumed, "Secret unassisted partition retained")
	_check(records.top_entries(2, true)[0].score == 900 and records.top_entries(2, true)[0].escapes == 3, "assisted partition retains metadata")
	_check(records.record_run("Invalid", 0, 500, 20.0, true) == ERR_INVALID_PARAMETER, "ordinary assisted record rejected")
	_check(records.record_run("Invalid", 7, 500, 20.0) == ERR_INVALID_PARAMETER, "unknown mode rejected")
	_check(records.record_run("Invalid", 0, -1, 20.0) == ERR_INVALID_PARAMETER, "negative score rejected")
	_check(records.record_run("Invalid", 0, 500, -1.0) == ERR_INVALID_PARAMETER, "negative distance rejected")
	_check(records.record_run("Invalid", 0, 500, INF) == ERR_INVALID_PARAMETER, "infinite distance rejected")
	_check(records.record_run("Invalid", 0, 500, NAN) == ERR_INVALID_PARAMETER, "NaN distance rejected")
	_check(records.record_run("Invalid", 2, 500, 20.0, false, -1) == ERR_INVALID_PARAMETER, "negative escapes rejected")
	_check(records.record_run("", 0, 500, 20.0) == ERR_INVALID_PARAMETER, "empty result name rejected")
	ordinary[0].score = 999999
	_check(records.top_entries(0)[0].score == 200, "returned rows cannot mutate saved rankings")
	_check(records.top_entries(0, false, 2).size() == 2 and records.top_entries(0, false, 0).is_empty(), "requested result limit respected")
	var loaded: Variant = records_script.new(path)
	_check(loaded.load_records() == OK and loaded.top_entries(0)[0].score == 200, "rankings survive reload")
	_check(loaded.top_entries(2, true)[0].score == 900, "assisted partition survives reload")


func _test_multiple_instances(records_script: Script) -> void:
	var path := _path("multiple-instances")
	var first: Variant = records_script.new(path)
	var second: Variant = records_script.new(path)
	_check(first.load_records() == OK and second.load_records() == OK, "two instances load before either saves")
	_check(first.save_player_name("Alice") == OK and second.save_player_name("Bob") == OK, "two instances save their driver names")
	_check(first.record_run("Alice", 0, 500, 50.0) == OK, "first instance saves Alice 500")
	_check(second.record_run("Bob", 0, 100, 10.0) == OK, "stale second instance saves Bob 100")
	var rows: Array[Dictionary] = second.top_entries(0)
	_check(rows.size() == 2 and rows[0].name == "Alice" and rows[0].score == 500 and rows[1].name == "Bob" and rows[1].score == 100, "stale save merges both drivers into its cache")
	var loaded: Variant = records_script.new(path)
	_check(loaded.load_records() == OK and loaded.top_entries(0).size() == 2 and loaded.top_entries(0)[0].score == 500, "both drivers survive durable reload")
	_check(loaded.player_name == "Bob", "run save preserves latest durable profile name")
	_check(first.save_player_name("Carol") == OK, "stale name save succeeds")
	_check(first.top_entries(0).size() == 2, "stale name save refreshes latest rankings")
	loaded.load_records()
	_check(loaded.player_name == "Carol" and loaded.top_entries(0).size() == 2, "stale name save preserves newer durable rankings")

	path = _path("same-driver-instances")
	first = records_script.new(path)
	second = records_script.new(path)
	first.load_records()
	second.load_records()
	_check(first.record_run("Alex", 0, 500, 50.0) == OK and second.record_run(" ALEX ", 0, 100, 90.0) == OK, "stale lower same-driver run saves")
	rows = second.top_entries(0)
	_check(rows.size() == 1 and rows[0].name == "Alex" and rows[0].score == 500 and rows[0].distance == 50.0, "stale same-driver save retains durable best")
	_check(second.record_run("alex", 0, 500, 75.0) == OK and first.record_run("Alex", 0, 500, 60.0) == OK, "stale equal-score run saves")
	loaded = records_script.new(path)
	loaded.load_records()
	_check(loaded.top_entries(0).size() == 1 and loaded.top_entries(0)[0].distance == 75.0, "latest distance tie-break survives stale save")

	path = _path("partition-instances")
	first = records_script.new(path)
	second = records_script.new(path)
	first.load_records()
	second.load_records()
	_check(first.record_run("Alex", 0, 500, 50.0) == OK and second.record_run("Alex", 1, 600, 60.0) == OK, "stale saves retain ordinary and infinite modes")
	_check(first.record_run("Alex", 2, 700, 70.0, false, 2) == OK and second.record_run("Alex", 2, 800, 80.0, true, 3) == OK, "stale saves retain both Secret partitions")
	loaded = records_script.new(path)
	loaded.load_records()
	_check(loaded.top_entries(0).size() == 1 and loaded.top_entries(0)[0].score == 500, "multi-instance ordinary partition retained")
	_check(loaded.top_entries(1).size() == 1 and loaded.top_entries(1)[0].score == 600, "multi-instance infinite partition retained")
	_check(loaded.top_entries(2).size() == 1 and loaded.top_entries(2)[0].score == 700 and loaded.top_entries(2)[0].escapes == 2, "multi-instance unassisted Secret partition retained")
	_check(loaded.top_entries(2, true).size() == 1 and loaded.top_entries(2, true)[0].score == 800 and loaded.top_entries(2, true)[0].escapes == 3, "multi-instance resumed Secret partition retained")


func _test_bounds(records_script: Script) -> void:
	var path := _path("bounds")
	var records: Variant = records_script.new(path)
	records.load_records()
	for index in range(130):
		_check(records.record_run("Driver %03d" % index, 0, index, float(index)) == OK, "bounded result save")
	var entries: Array[Dictionary] = records.top_entries(0, false, 10000)
	_check(entries.size() == 100 and entries[0].score == 129 and entries[-1].score == 30, "bounded collection retains highest 100 results")
	var loaded: Variant = records_script.new(path)
	loaded.load_records()
	_check(loaded.top_entries(0, false, 10000).size() == 100, "saved collection remains bounded")


func _test_malformed(records_script: Script) -> void:
	var path := _path("malformed")
	var config := ConfigFile.new()
	config.set_value("meta", "version", 1)
	config.set_value("profile", "name", "bad\nname")
	var valid := {"name": "Mara", "mode": 2, "score": 300, "distance": 90.0, "resumed": false, "escapes": 1}
	var rows: Array = [valid, "garbage", {"name": "Missing"}]
	for pair in [["name", ""], ["mode", "2"], ["mode", 9], ["score", "300"], ["score", -1], ["score", INF], ["distance", INF], ["distance", NAN], ["distance", "90"], ["resumed", "false"], ["escapes", -1]]:
		var invalid: Dictionary = valid.duplicate()
		invalid[pair[0]] = pair[1]
		rows.append(invalid)
	rows.append({"name": "  MARA  ", "mode": 2, "score": 200, "distance": 180.0, "resumed": false, "escapes": 2})
	config.set_value("records", "entries", rows)
	_check(config.save(path) == OK, "malformed fixture saved")
	var records: Variant = records_script.new(path)
	_check(records.load_records() == OK, "malformed rows do not reject valid rows")
	_check(records.player_name == "", "malformed last name ignored")
	_check(records.top_entries(2).size() == 1 and records.top_entries(2)[0].name == "Mara" and records.top_entries(2)[0].score == 300, "invalid rows excluded and duplicate best retained")
	config.set_value("records", "entries", "not an array")
	config.save(path)
	records.load_records()
	_check(records.top_entries(2).is_empty(), "malformed container resets loaded rankings")
	config.set_value("meta", "version", 99)
	config.set_value("records", "entries", [valid])
	config.save(path)
	_check(records.load_records() != OK and records.top_entries(2).is_empty(), "unknown version rejected safely")


func _test_write_failure(records_script: Script) -> void:
	var path := _path("write-error")
	var records: Variant = records_script.new(path)
	records.load_records()
	records.save_player_name("Saved")
	records.record_run("Saved", 0, 25, 12.0)
	records.save_path = prefix + "-missing-directory/records.cfg"
	_check(records.save_player_name("Lost") != OK and records.player_name == "Saved", "failed name write preserves in-memory profile")
	_check(records.record_run("Lost", 0, 200, 12.0) != OK and records.top_entries(0).size() == 1, "failed record write preserves rankings")
	var loaded: Variant = records_script.new(path)
	loaded.load_records()
	_check(loaded.player_name == "Saved" and loaded.top_entries(0)[0].score == 25, "failed writes preserve durable data")


func _test_save_transaction_failures(records_script: Script) -> void:
	var path := _path("transaction-errors")
	var records: Variant = records_script.new(path)
	records.load_records()
	_check(records.save_player_name("Saved") == OK and records.record_run("Saved", 0, 25, 12.0) == OK, "transaction fixture saved")
	var durable := FileAccess.get_file_as_string(path)
	_check(DirAccess.make_dir_absolute(path + ".tmp") == OK, "temporary-write failure fixture created")
	_check(records.save_player_name("Lost") != OK and records.record_run("Lost", 0, 200, 20.0) != OK, "temporary-write failures reported")
	_check(records.player_name == "Saved" and records.top_entries(0).size() == 1 and records.top_entries(0)[0].score == 25, "temporary-write failure preserves cache")
	_check(FileAccess.get_file_as_string(path) == durable and not DirAccess.dir_exists_absolute(path + ".lock"), "temporary-write failure preserves disk and releases lock")
	DirAccess.remove_absolute(path + ".tmp")

	var temporary := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	temporary.store_string("another writer owns this temporary file")
	temporary.close()
	_check(DirAccess.make_dir_absolute(path + ".lock") == OK, "held-lock fixture created")
	_check(records.save_player_name("Lost") != OK and records.record_run("Lost", 0, 200, 20.0) != OK, "held lock rejects both save operations")
	_check(FileAccess.get_file_as_string(path) == durable and FileAccess.get_file_as_string(path + ".tmp") == "another writer owns this temporary file", "held lock prevents durable and temporary overwrite")
	_check(DirAccess.dir_exists_absolute(path + ".lock") and records.player_name == "Saved" and records.top_entries(0).size() == 1, "lock contention preserves owner lock and cached data")
	DirAccess.remove_absolute(path + ".lock")
	DirAccess.remove_absolute(path + ".tmp")
	_check(records.record_run("Retry", 0, 50, 20.0) == OK, "save retries after lock release")
	var cached_rows: Array[Dictionary] = records.top_entries(0)
	durable = FileAccess.get_file_as_string(path)

	var config := ConfigFile.new()
	config.set_value("meta", "version", 99)
	config.set_value("profile", "name", "Changed")
	config.set_value("records", "entries", [])
	_check(config.save(path) == OK, "unknown-version transaction fixture saved")
	var corrupt := FileAccess.get_file_as_string(path)
	_check(records.save_player_name("Lost") != OK and records.record_run("Lost", 0, 200, 20.0) != OK, "latest invalid file rejects save rather than replacing it")
	_check(records.player_name == "Saved" and records.top_entries(0) == cached_rows, "latest-read failure preserves cached profile and rankings")
	_check(FileAccess.get_file_as_string(path) == corrupt and not DirAccess.dir_exists_absolute(path + ".lock"), "latest-read failure preserves disk and releases lock")
	var restore := FileAccess.open(path, FileAccess.WRITE)
	restore.store_string(durable)
	restore.close()
	_check(records.save_player_name("Saved") == OK, "save retries after latest file restored")

	var rename_path := _path("rename-error")
	_check(DirAccess.make_dir_absolute(rename_path) == OK, "rename failure fixture created")
	records.save_path = rename_path
	_check(records.save_player_name("Lost") != OK and records.record_run("Lost", 0, 200, 20.0) != OK, "rename failures reported")
	_check(records.player_name == "Saved" and records.top_entries(0) == cached_rows and FileAccess.get_file_as_string(path) == durable, "rename failure preserves cache and existing durable records")
	_check(DirAccess.dir_exists_absolute(rename_path) and not DirAccess.dir_exists_absolute(rename_path + ".lock") and not FileAccess.file_exists(rename_path + ".tmp"), "rename failure releases lock and removes temporary file")
	DirAccess.remove_absolute(rename_path)
	_check(records.save_player_name("Retry") == OK, "save retries after rename destination repaired")


func _path(suffix: String) -> String:
	var path := prefix + "-" + suffix + ".cfg"
	paths.append(path)
	return path


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("PLAYER RECORDS FAIL: " + label)
