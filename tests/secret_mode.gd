extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if not game.has_method("request_start_game") or not game.has_method("_on_resume_code_submitted"):
		_check(false, "named Secret Mode and resume integration exist")
		await _close(game)
		quit(1)
		return
	var settings := ConfigFile.new()
	settings.set_value("secret_mode", "access_code", "TEST-ACCESS-2468")
	settings.set_value("secret_mode", "resume_code", "TEST-RESUME-2468")
	settings.save("user://secret_integration_config.cfg")
	DirAccess.remove_absolute("user://secret_integration_records.cfg")
	DirAccess.remove_absolute("user://secret_integration_access.cfg")
	game.records = load("res://scripts/player_records.gd").new("user://secret_integration_records.cfg")
	game.records.load_records()
	game.access = load("res://scripts/secret_access.gd").new("user://secret_integration_access.cfg", "user://secret_integration_config.cfg")
	game.access.load_access()
	game.ui.configure_secret(false)
	game.obstacles.spawning_enabled = false
	game.select_mode(2)
	_check(game.selected_mode != 2, "locked level cannot be selected")
	game.request_start_game()
	_check(game.state == game.GameState.MENU and game.community.name_dialog.visible, "title start requires a driver name")
	game._on_name_submitted("   ")
	_check(game.state == game.GameState.MENU, "blank driver cannot start")
	game._on_name_submitted("Delia Ștefan")
	_check(game.state == game.GameState.PLAYING and game.player_name == "Delia Ștefan", "valid Unicode name starts driving")
	game.return_to_menu()
	game.community.request_access()
	game._on_secret_code_submitted("wrong")
	_check(not game.access.secret_unlocked and game.community.access_dialog.visible, "incorrect access code stays locked")
	game._on_secret_code_submitted("TEST-ACCESS-2468")
	_check(game.access.secret_unlocked and game.selected_mode == 2, "configured access unlocks and selects Secret Mode")
	game.start_game()
	_clear(game)
	_check(game.run_mode == 2 and not game.progress.infinite_boost and game.progress.boost_charge == 0.4, "Secret Mode starts with earned fuel")
	game.progress.distance_points = 6000.0
	game.distance = 700.0
	game.speed = 62.0
	game.obstacles._take_obstacle().activate(Vector3(0, 0, -4.0), RoadObstacle.Kind.CAR)
	await _frames(4)
	_check(game.state == game.GameState.PLAYING and game.pursuit.active and game.speed < 40.0, "actual traffic crash starts chase with substantial slowdown")
	_check(game.player.active and game.get_score() < 5100, "Secret impact continues driving with a score penalty")
	_key(KEY_SHIFT, true)
	var fuel: float = game.progress.boost_charge
	await _frames(20)
	_check(game.progress.boosting and game.progress.boost_charge < fuel, "finite boost remains usable during Secret damage")
	_key(KEY_SHIFT, false)
	game.pause_game()
	var frozen_gap: float = game.pursuit.gap_m
	var frozen_clean: float = game.pursuit.clean_seconds
	await _frames(30)
	_check(game.pursuit.gap_m == frozen_gap and game.pursuit.clean_seconds == frozen_clean, "pause freezes police pursuit")
	game.resume_game()
	await _frames(1050)
	_check(game.state == game.GameState.PLAYING and not game.pursuit.active and game.secret_escapes == 1, "actual clean driving escapes the first pursuit")
	_check(not game.audio.police_loop.playing, "escape stops the siren")
	# Two real holes trigger the same moving pursuit instead of ordinary game over.
	game.start_game()
	_clear(game)
	game.obstacles._take_obstacle().activate(Vector3.ZERO, RoadObstacle.Kind.POTHOLE)
	await _frames(4)
	_check(not game.pursuit.active, "first Secret pothole retains the warning rule")
	game.obstacles._take_obstacle().activate(Vector3.ZERO, RoadObstacle.Kind.POTHOLE)
	await _frames(4)
	_check(game.pursuit.active and game.state == game.GameState.PLAYING, "second real hole starts pursuit")
	game.start_game()
	_clear(game)
	game.progress.distance_points = 9000.0
	game.obstacles._take_obstacle().activate(Vector3.ZERO, RoadObstacle.Kind.ROADWORKS)
	await _frames(4)
	_check(game.pursuit.active and game.progress.score_valid and game.state == game.GameState.PLAYING, "Secret worksite starts a recoverable pursuit")
	# Repeated impacts close the police gap, and must eventually cause capture.
	for hit in range(5):
		if game.state != game.GameState.PLAYING:
			break
		game.obstacles._take_obstacle().activate(Vector3.ZERO, RoadObstacle.Kind.CAR)
		await _frames(4)
	_check(game.state == game.GameState.GAME_OVER and game.end_reason.contains("Police"), "repeat real impacts let the police catch the driver")
	_check(game.aftermath.active and not game.pursuit.active, "capture freezes gameplay and starts police arrival")
	var code := "TEST-RESUME-2468"
	game._on_resume_code_submitted(code)
	_check(game.state == game.GameState.GAME_OVER, "code cannot resume before police arrive")
	game.aftermath.advance(4.0)
	await process_frame
	game._on_resume_code_submitted("wrong")
	_check(game.state == game.GameState.GAME_OVER, "wrong bribe code cannot continue")
	var retained_score: int = game.get_score()
	var retained_distance: float = game.distance
	var retained_fuel: float = game.progress.boost_charge
	game._on_resume_code_submitted(code)
	_check(game.state == game.GameState.PLAYING and game.run_resumed, "configured reusable code resumes Secret run")
	_check(game.get_score() == retained_score and game.distance == retained_distance and game.player_name == "Delia Ștefan", "resume preserves driver and run progress")
	_check(game.progress.boost_charge == retained_fuel and not game.aftermath.active and not game.pursuit.active and game.obstacles.get_active_count() == 0, "resume clears hazards/police without granting free fuel")
	var resumed_hazard: RoadObstacle = game.obstacles._take_obstacle()
	resumed_hazard.activate(Vector3(5.0, 0.0, -50.0), RoadObstacle.Kind.POTHOLE, game.player.position.x)
	await _frames(4)
	_check(resumed_hazard.position.z > -50.0 and game.state == game.GameState.PLAYING, "resumed run restores moving encounters after capture")
	resumed_hazard.deactivate()
	_check(game.access.validate_resume_code(code), "configured code stays valid after continuation")
	game._finish_run("Resumed test ending", false, true)
	game.aftermath.advance(4.0)
	game._on_resume_code_submitted(code)
	_check(game.state == game.GameState.GAME_OVER, "same run cannot have a second continuation")
	_check(game.records.top_entries(2, true).size() == 1 and game.records.top_entries(0).is_empty(), "resumed Secret score goes to a separate named ranking")
	var ordinary_rows: Array[Dictionary] = game.records.top_entries(2, false)
	_check(not ordinary_rows.is_empty() and ordinary_rows[0].score <= retained_score, "unassisted ranking contains only score earned before resume")
	game.start_game()
	_clear(game)
	for hit in range(6):
		if game.state != game.GameState.PLAYING:
			break
		game._on_player_hit()
	_check(game.state == game.GameState.GAME_OVER, "later Secret run can be caught")
	game.aftermath.advance(4.0)
	game._on_resume_code_submitted(code)
	_check(game.state == game.GameState.PLAYING and game.run_resumed, "same configured code works in a later run")
	game.return_to_menu()
	game.select_mode(1)
	game.start_game()
	game._on_player_hit()
	_check(not game.community.resume_button.visible, "ordinary modes never offer a bribe")
	game.start_game()
	_check(not game.run_resumed and not game.pursuit.active and not game.aftermath.active, "new run clears Secret transients and assistance")
	# Config revocation during a paused restart must lead to an usable title gate.
	game.return_to_menu()
	game.select_mode(2)
	game.start_game()
	game.pause_game()
	settings.set_value("secret_mode", "access_code", "REPLACED-ACCESS")
	settings.save("user://secret_integration_config.cfg")
	_key(KEY_R, true)
	await process_frame
	_key(KEY_R, false)
	_check(game.state == game.GameState.MENU and not paused and game.community.access_dialog.visible, "revoked paused restart returns to a live access gate")
	game._on_secret_code_submitted("REPLACED-ACCESS")
	_check(game.access.secret_unlocked and game.selected_mode == 2 and game.state == game.GameState.MENU, "new configured code works after restart revocation")
	await _close(game)
	if failures == 0:
		print("SECRET MODE PASS: name/access gates, real mistake pursuits, finite damaged boost, pause, escape/capture, configured resume reuse, one continuation per run and ranking isolation")
	quit(1 if failures else 0)


func _clear(game: Node3D) -> void:
	for obstacle in game.obstacles.obstacle_pool:
		obstacle.deactivate()


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
	await process_frame


func _close(game: Node3D) -> void:
	_key(KEY_SHIFT, false)
	game.return_to_menu()
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await process_frame
	game.free()
	await process_frame


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("SECRET MODE FAIL: " + label)
