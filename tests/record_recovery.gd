extends SceneTree

var failures: int = 0
var games: Array[Node3D] = []
const SAVE_PATH := "user://highscore.cfg"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# The Windows runner redirects user:// to a disposable validation profile.
	var saved := FileAccess.get_file_as_bytes(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else PackedByteArray()
	var first = _game()
	var second = _game()
	await _malformed_fields(first)
	_multi_instance(first, second)
	_save_failures(second)
	for game in games:
		game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	for game in games:
		game.free()
	games.clear()
	await process_frame
	if saved.is_empty():
		DirAccess.remove_absolute(SAVE_PATH)
	else:
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	if failures == 0:
		print("RECORD RECOVERY PASS: independent malformed fields and stale-instance best/stat preservation")
	quit(1 if failures else 0)


func _game():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.obstacles.spawning_enabled = false
	games.append(game)
	return game


func _malformed_fields(game) -> void:
	var fixture := ConfigFile.new()
	fixture.set_value("scores", "best", {"unexpected": 400})
	fixture.set_value("scores", "distance", 987.0)
	fixture.set_value("scores", "combo", 4.0)
	fixture.set_value("scores", "speed", 80.0)
	_check(fixture.save(SAVE_PATH) == OK, "malformed best fixture saves")
	game.start_game()
	_check(game.best_score == 0 and game.best_distance == 987.0 and game.best_combo == 4.0 and game.best_speed == 80.0, "invalid best leaves other valid records loaded")
	game.progress.distance_points = 100.0
	game.distance = 10.0
	game._finish_run("Record recovery test")
	fixture.load(SAVE_PATH)
	_check(fixture.get_value("scores", "best") == 100 and fixture.get_value("scores", "distance") == 987.0 and fixture.get_value("scores", "combo") == 4.0 and fixture.get_value("scores", "speed") == 80.0, "short run repairs malformed score and preserves valid stats")
	# Each field is independent, including non-finite numeric values.
	for invalid: Variant in [{"unexpected": 400}, "bad", true, INF, NAN, -1.0]:
		fixture.set_value("scores", "best", 500)
		fixture.set_value("scores", "distance", invalid)
		fixture.set_value("scores", "combo", invalid)
		fixture.set_value("scores", "speed", invalid)
		fixture.save(SAVE_PATH)
		game._load_best_score()
		_check(game.best_score == 500 and game.best_distance == 0.0 and game.best_combo == 1.0 and game.best_speed == 0.0, "invalid stats use finite defaults without aborting score load")
	game.return_to_menu()
	await process_frame


func _multi_instance(first, second) -> void:
	DirAccess.remove_absolute(SAVE_PATH)
	first.start_game()
	second.start_game()
	first.progress.distance_points = 500.0
	first.distance = 50.0
	first.progress.top_combo = 4.0
	first.progress.top_speed = 80.0
	first._finish_run("First instance ending")
	second.progress.distance_points = 100.0
	second.distance = 10.0
	second._finish_run("Stale instance ending")
	var saved := ConfigFile.new()
	saved.load(SAVE_PATH)
	_check(saved.get_value("scores", "best") == 500 and saved.get_value("scores", "distance") == 50.0 and saved.get_value("scores", "combo") == 4.0 and saved.get_value("scores", "speed") == 80.0, "stale instance keeps durable best score and all stats")
	_check(second.best_score == 500 and second.ui.best_score_label.text == "BEST 000500", "stale result displays the actual durable best")
	_check(not second.ui.record_label.visible, "lower stale result is not a new record")
	first.return_to_menu()
	second.return_to_menu()
	second.select_mode(1)
	second.start_game()
	second.progress.distance_points = 200.0
	second._finish_run("Other partition ending")
	saved.load(SAVE_PATH)
	_check(saved.get_value("scores", "best") == 500 and saved.get_value("scores_infinite", "best") == 200, "merged writes keep other modes intact")
	first.return_to_menu()
	second.return_to_menu()
	second.select_mode(0)
	first.start_game()
	second.start_game()
	first.progress.distance_points = 600.0
	second.progress.distance_points = 600.0
	first._finish_run("Equal score first ending")
	second._finish_run("Equal score stale ending")
	_check(not second.ui.record_label.visible and second.best_score == 600, "equal stale score is a tie, not a new durable best")


func _save_failures(game) -> void:
	var original := FileAccess.get_file_as_string(SAVE_PATH)
	var temporary := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	temporary.store_string("another writer owns this temporary file")
	temporary.close()
	_check(DirAccess.make_dir_absolute(SAVE_PATH + ".lock") == OK, "record lock fixture exists")
	game.best_score = 999
	var saved: Dictionary = game._save_best_score()
	_check(saved.error != OK and FileAccess.get_file_as_string(SAVE_PATH) == original and FileAccess.get_file_as_string(SAVE_PATH + ".tmp") == "another writer owns this temporary file", "held lock preserves durable and owner temporary data")
	_check(DirAccess.dir_exists_absolute(SAVE_PATH + ".lock") and game.best_score == 999, "held lock preserves its owner and cached candidate")
	DirAccess.remove_absolute(SAVE_PATH + ".lock")
	DirAccess.remove_absolute(SAVE_PATH + ".tmp")
	_check(DirAccess.make_dir_absolute(SAVE_PATH + ".tmp") == OK, "record write failure fixture exists")
	saved = game._save_best_score()
	_check(saved.error != OK and FileAccess.get_file_as_string(SAVE_PATH) == original and game.best_score == 999, "write failure preserves durable data and cached candidate")
	_check(not DirAccess.dir_exists_absolute(SAVE_PATH + ".lock"), "failed record write releases lock")
	DirAccess.remove_absolute(SAVE_PATH + ".tmp")
	saved = game._save_best_score()
	_check(saved.error == OK and not FileAccess.file_exists(SAVE_PATH + ".tmp") and not DirAccess.dir_exists_absolute(SAVE_PATH + ".lock"), "record retry commits and cleans transaction files")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("RECORD RECOVERY FAIL: " + label)
