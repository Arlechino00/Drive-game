extends SceneTree

const Settings = preload("res://scripts/game_settings.gd")
const Director = preload("res://scripts/difficulty_director.gd")
const Game = preload("res://scripts/game.gd")
var failures: int = 0


func _initialize() -> void:
	_check(Game.parse_run_seed(PackedStringArray(["--seed=2468"])) == 2468, "command-line reproducible seed")
	_check(Game.parse_run_seed(PackedStringArray(["--seed=0"])) == 0, "zero is a valid seed")
	_check(Game.parse_run_seed(PackedStringArray(["--seed=broken", "--seed=-1"])) == -1, "invalid seed keeps random runs")
	var settings := Settings.new()
	settings.set_value("volume", 0.23)
	settings.set_value("shake", 0.0)
	settings.set_value("effects", 0.36)
	settings.set_value("fullscreen", 1.0)
	settings.set_value("quality", 2.0)
	settings.set_value("resolution", 1.0)
	_check(settings.save_settings("user://test-preferences.cfg") == OK, "preference save")
	var loaded := Settings.new()
	loaded.load_settings("user://test-preferences.cfg")
	_check(is_equal_approx(loaded.volume, 0.23) and loaded.shake == 0.0 and loaded.fullscreen, "preference round trip")
	_check(loaded.quality == Settings.Quality.HIGH and loaded.resolution == 1, "render choices round trip")
	_check(settings.save_settings("user://test-preferences.cfg") == OK, "preference replacement succeeds")
	_test_atomic_saving()
	loaded.set_value("quality", INF)
	_check(loaded.quality == Settings.Quality.HIGH, "nonfinite choices ignored")
	loaded.set_value("quality", -5.0)
	loaded.set_value("resolution", 900.0)
	_check(loaded.quality == Settings.Quality.LOW and loaded.resolution == Settings.RESOLUTIONS.size() - 1, "render choices bounded")
	loaded.set_value("effects", -1.0)
	loaded.set_value("shake", 2.0)
	_check(loaded.effects == 0.0 and loaded.shake == 1.0, "preferences clamp")
	var malformed := ConfigFile.new()
	malformed.set_value("settings", "volume", "broken")
	malformed.set_value("settings", "shake", INF)
	malformed.set_value("settings", "effects", -5.0)
	malformed.set_value("settings", "quality", "broken")
	malformed.set_value("settings", "resolution", INF)
	malformed.save("user://test-preferences.cfg")
	var safe := Settings.new()
	safe.load_settings("user://test-preferences.cfg")
	_check(safe.volume == 0.7 and safe.shake == 0.35 and safe.effects == 0.0, "malformed preferences use safe defaults")
	_check(safe.quality == Settings.Quality.BALANCED and safe.resolution == 0, "malformed render choices preserve defaults")
	DirAccess.remove_absolute("user://test-preferences.cfg")
	var director := Director.new()
	_check(is_equal_approx(director.get_base_speed(0.0), Director.INITIAL_SPEED), "stage two opening speed")
	_check(director.get_base_speed(1000000.0) > 62.0, "long-run speed exceeds former cap")
	_check(director.get_density(2000.0) > director.get_density(2700.0), "recovery wave reduces density")
	for distance in range(0, 20000, 100):
		var density := director.get_density(distance)
		_check(density >= 0.0 and density <= 1.0, "bounded difficulty")
	if failures == 0:
		print("SETTINGS PASS: atomic save/load, failure preservation, clamps, malformed defaults, continuous speed, recovery waves")
	quit(1 if failures > 0 else 0)


class ControlledTemporarySettings extends Settings:
	var temporary_override: String = ""

	func _temporary_path(path: String) -> String:
		return path + ".controlled-tmp" if temporary_override.is_empty() else temporary_override


func _test_atomic_saving() -> void:
	var path := "user://test-atomic-preferences.cfg"
	var settings := ControlledTemporarySettings.new()
	settings.volume = 0.23
	_check(settings.save_settings(path) == OK, "atomic preference fixture saved")
	var original := FileAccess.get_file_as_string(path)
	settings.volume = 0.91
	var temporary_path := path + ".controlled-tmp"
	_check(DirAccess.make_dir_absolute(temporary_path) == OK, "temporary-write failure fixture exists")
	var printed_errors := Engine.print_error_messages
	Engine.print_error_messages = false
	var error := settings.save_settings(path)
	Engine.print_error_messages = printed_errors
	_check(error != OK and FileAccess.get_file_as_string(path) == original, "temporary write failure preserves valid preferences")
	_check(DirAccess.dir_exists_absolute(temporary_path), "write failure leaves foreign temporary directory intact")
	DirAccess.remove_absolute(temporary_path)
	settings.temporary_override = path + ".missing-directory/preferences.tmp"
	Engine.print_error_messages = false
	error = settings.save_settings(path)
	Engine.print_error_messages = printed_errors
	_check(error != OK and FileAccess.get_file_as_string(path) == original, "failed temporary file creation preserves existing valid preferences")
	settings.temporary_override = ""
	if OS.get_name() == "Windows":
		# An open Windows file denies rename replacement, while direct writes still
		# succeed. This reproduces a failed commit against an existing valid file.
		var held_file := FileAccess.open(path, FileAccess.READ)
		_check(held_file != null, "existing preferences opened for rename-failure fixture")
		Engine.print_error_messages = false
		error = settings.save_settings(path)
		Engine.print_error_messages = printed_errors
		if held_file != null:
			held_file.close()
		_check(error != OK and FileAccess.get_file_as_string(path) == original, "rename failure preserves existing valid preferences")
		_check(not FileAccess.file_exists(temporary_path), "failed replacement cleans owned temporary file")
	_check(settings.save_settings(path) == OK, "retry after failure commits preferences")
	var loaded := Settings.new()
	loaded.load_settings(path)
	_check(is_equal_approx(loaded.volume, 0.91), "retry stores latest preferences")
	_check(not FileAccess.file_exists(temporary_path), "successful commit leaves no temporary file")
	var foreign_temporary := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	foreign_temporary.store_string("another writer's temporary data")
	foreign_temporary.close()
	_check(Settings.new().save_settings(path) == OK, "normal save uses its own temporary file")
	_check(FileAccess.get_file_as_string(path + ".tmp") == "another writer's temporary data", "save preserves foreign temporary data")
	DirAccess.remove_absolute(path + ".tmp")
	DirAccess.remove_absolute(path)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("SETTINGS FAIL: " + label)
