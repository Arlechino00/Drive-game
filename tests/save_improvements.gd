extends SceneTree

class PreferenceProbe:
	extends "res://scripts/game_settings.gd"
	var writes: int = 0
	var write_error: Error = OK
	func save_settings(_path: String = "user://settings.cfg") -> Error:
		writes += 1
		return write_error

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := "user://highscore.cfg"
	var existed := FileAccess.file_exists(path)
	var original := FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.obstacles.spawning_enabled = false
	game.start_game()
	var broken := "[scores]\nbest=\"unfinished\n"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(broken)
	file.close()
	game.best_score = 1234
	game.best_distance = 56.0
	# These fixture failures are intentional; keep the normal suite log strict.
	var printed := Engine.print_error_messages
	Engine.print_error_messages = false
	var saved: Dictionary = game._save_best_score()
	Engine.print_error_messages = printed
	var backup: String = saved.get("recovered_backup", "")
	_check(saved.error == OK, "syntax-corrupt score file recovers on save")
	_check(not backup.is_empty() and FileAccess.get_file_as_string(backup) == broken, "recovery preserves the exact damaged file")
	var loaded := ConfigFile.new()
	_check(loaded.load(path) == OK and loaded.get_value("scores", "best", 0) == 1234, "recovered records survive a fresh load")
	if not backup.is_empty():
		DirAccess.remove_absolute(backup)
	_check(game._save_best_score().error == OK, "later record saves continue normally")

	for police_scene in [false, true]:
		game.start_game()
		DirAccess.make_dir_absolute(path + ".lock")
		Engine.print_error_messages = false
		game._finish_run("Test ending", false, police_scene)
		Engine.print_error_messages = printed
		var detail: Label = game.ui.game_over_menu.get_meta("detail")
		_check("could not be saved" in detail.text and detail.is_visible_in_tree(), "save failure remains visible on ordinary and police results")
		DirAccess.remove_absolute(path + ".lock")

	var preferences := PreferenceProbe.new()
	game.start_game()
	game.settings = preferences
	for step in range(20):
		game._on_settings_changed("volume", float(step) / 20.0)
	_check(preferences.writes == 0 and is_equal_approx(preferences.volume, 0.95), "slider changes apply immediately without immediate writes")
	game._process(0.2)
	_check(preferences.writes == 0, "short idle interval keeps changes pending")
	game.pause_game()
	game._process(0.2)
	_check(preferences.writes == 1, "idle changes save once even while paused")
	preferences.write_error = ERR_FILE_CANT_WRITE
	game._on_settings_changed("volume", 0.6)
	Engine.print_error_messages = false
	game._process(0.4)
	Engine.print_error_messages = printed
	var footer: Label = game.ui.settings_menu.get_meta("footer", null)
	_check(footer != null and "could not be saved" in footer.text, "failed preference save is shown in settings")
	game._process(1.0)
	_check(preferences.writes == 2, "failed save does not repeatedly write every frame")
	preferences.write_error = OK
	game._flush_settings()
	_check(preferences.writes == 3 and is_equal_approx(preferences.volume, 0.6) and game.ui.settings_menu.get_meta("footer").text.find("could not be saved") < 0, "exit/background flush retries pending preferences after transient storage failure")
	game._on_settings_changed("volume", 0.5)
	if game.has_method("_flush_settings"):
		game._flush_settings()
	_check(preferences.writes == 4 and is_equal_approx(preferences.volume, 0.5), "explicit flush preserves the final setting before exit")
	paused = false
	game.return_to_menu()
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await process_frame
	game.free()
	if existed:
		file = FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(path)
	print("SAVE IMPROVEMENTS PASS: damaged-file backup/recovery, visible failures, debounced preferences and exit flush" if failures == 0 else "SAVE IMPROVEMENTS FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
