extends SceneTree

const Records = preload("res://scripts/player_records.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.obstacles.spawning_enabled = false
	# Identical real swept traffic contacts must begin identical pursuits,
	# including when the contact ends a race first.
	for in_race in [false, true]:
		game.start_game()
		_clear(game)
		game.run_mode = game.GameMode.SECRET
		game.progress.distance_points = 10000.0
		game.distance = 2000.0
		game.speed = 62.0
		if in_race:
			var rival: RoadObstacle = game.obstacles._take_obstacle()
			rival.activate(Vector3(-5, 0, -13), RoadObstacle.Kind.WIDE, 0.0, 8)
			game._update_apex_race(0.0)
		var impact: RoadObstacle = game.obstacles._take_obstacle()
		impact.activate(Vector3(0, 0, -10), RoadObstacle.Kind.CAR, 0.0, 0)
		impact.advance_pass(10.0, 0.0)
		_check(game.pursuit.active and is_equal_approx(game.pursuit.gap_m, 64.0), "first traffic impact has one pursuit consequence, racing=%s" % in_race)
		_check(game.get_score() == 9000 and game.speed == 32.0, "impact has exactly one score/speed penalty")
		game._on_player_hit()
		_check(is_equal_approx(game.pursuit.gap_m, 50.0), "later impact closes existing pursuit by fourteen meters")
	# An actual queued near pass at the terminal clean tick must cancel escape.
	game.start_game()
	_clear(game)
	game.run_mode = game.GameMode.SECRET
	game.distance = 2000.0
	game.speed = 62.0
	game.pursuit.begin(game.player.position)
	game.pursuit.clean_seconds = 15.99
	game.pursuit._elapsed = 16.0
	var close_pass: RoadObstacle = game.obstacles._take_obstacle()
	close_pass.activate(Vector3(2.85, 0, 5.1), RoadObstacle.Kind.CAR, 0.0, 0)
	game._physics_process(1.0 / 60.0)
	await process_frame
	await process_frame
	_check(game.progress.near_misses == 1, "actual near pass remains awarded")
	_check(game.pursuit.active and game.secret_escapes == 0 and game.pursuit.clean_seconds == 0.0, "same-tick near pass prevents clean escape")
	# A valid but unsupported records file reproduces damaged-save behavior
	# without intentionally logging a ConfigFile syntax error.
	game.return_to_menu()
	var path := "user://audit_game_records.cfg"
	_remove_records(path)
	var damaged := ConfigFile.new()
	damaged.set_value("meta", "version", 99)
	damaged.set_value("future", "keep", "original data")
	damaged.save(path)
	var original := FileAccess.get_file_as_bytes(path)
	game.records = Records.new(path)
	game.request_start_game()
	game._on_name_submitted("Recovered Driver")
	_check(game.state == game.GameState.PLAYING and game.player_name == "Recovered Driver", "damaged records cannot block starting a run")
	if "last_recovery_backup_path" in game.records and not game.records.last_recovery_backup_path.is_empty():
		_check(FileAccess.get_file_as_bytes(game.records.last_recovery_backup_path) == original, "original damaged records are preserved byte for byte")
		DirAccess.remove_absolute(game.records.last_recovery_backup_path)
	else:
		_check(false, "recovery exposes preserved backup")
	game.return_to_menu()
	_remove_records(path)
	game.records = Records.new(path)
	game.records.load_records()
	var writer := Records.new(path)
	_check(writer.record_run("Another Instance", 0, 9876, 120.0) == OK, "second instance saves ranking")
	game._on_leaderboard_requested(0, false)
	_check(not game.records.top_entries(0).is_empty() and game.records.top_entries(0)[0].name == "Another Instance", "opening leaderboard refreshes another instance's score")
	# A held save lock must permit play without deleting another writer's lock.
	game.community.dismiss()
	DirAccess.make_dir_absolute(path + ".lock")
	game.request_start_game()
	game._on_name_submitted("Unsaved Driver")
	_check(game.state == game.GameState.PLAYING and game.player_name == "Unsaved Driver", "unwritable records allow unsaved play")
	_check(DirAccess.dir_exists_absolute(path + ".lock"), "fallback preserves another writer's lock")
	DirAccess.remove_absolute(path + ".lock")
	game.return_to_menu()
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await process_frame
	game.free()
	_remove_records(path)
	if failures == 0:
		print("AUDIT REGRESSIONS PASS: impact pressure, deferred close pass, preserved recovery, refreshed rankings, unsaved play")
	quit(1 if failures else 0)


func _clear(game: Node3D) -> void:
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()


func _remove_records(path: String) -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("AUDIT REGRESSIONS FAIL: " + label)
