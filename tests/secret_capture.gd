extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.obstacles.spawning_enabled = false
	game.run_seed = 2468
	var config := ConfigFile.new()
	config.set_value("secret_mode", "access_code", "CAPTURE-ACCESS")
	config.set_value("secret_mode", "resume_code", "CAPTURE-RESUME")
	config.save("user://secret_capture_config.cfg")
	DirAccess.remove_absolute("user://secret_capture_records.cfg")
	DirAccess.remove_absolute("user://secret_capture_access.cfg")
	game.records = load("res://scripts/player_records.gd").new("user://secret_capture_records.cfg")
	game.access = load("res://scripts/secret_access.gd").new("user://secret_capture_access.cfg", "user://secret_capture_config.cfg")
	game.access.load_access()
	game.ui.configure_secret(false)
	game.request_start_game()
	game.community.name_input.text = "Delia Ștefan"
	await _save("driver_name.png")
	game.community.dismiss()
	game.community.request_access()
	await _save("secret_access.png")
	game._on_secret_code_submitted("CAPTURE-ACCESS")
	await _save("secret_menu.png")
	game._on_name_submitted("Delia Ștefan")
	_clear(game)
	game.set_physics_process(false)
	game.player.active = false
	game.player.position.x = -5.0
	game.obstacles._take_obstacle().activate(Vector3(0, 0, -42), RoadObstacle.Kind.WIDE)
	game.obstacles._take_obstacle().activate(Vector3(5, 0, -25), RoadObstacle.Kind.POTHOLE)
	await _frames(20)
	await _save("secret_level.png")
	game.set_physics_process(true)
	_start_clear(game)
	game.distance = 700.0
	game.progress.distance_points = 8500.0
	game.speed = 62.0
	game.obstacles._take_obstacle().activate(Vector3(0, 0, -4.0), RoadObstacle.Kind.CAR)
	await _frames(60)
	_check(game.pursuit.active and game.state == game.GameState.PLAYING, "actual traffic impact starts visible pursuit")
	await _save("secret_pursuit.png")
	for hit in range(2):
		game.obstacles._take_obstacle().activate(Vector3.ZERO, RoadObstacle.Kind.CAR)
		await _frames(4)
	game.set_physics_process(false)
	game.player.active = false
	_check(game.pursuit.active and game.community.rearview_panel.visible, "repeat impacts leave a visible closer police car")
	await _save("secret_pursuit_close.png")
	# A visibly separated pursuit must disengage for five seconds after pressure decays.
	game.set_physics_process(true)
	_start_clear(game)
	game.obstacles._take_obstacle().activate(Vector3.ZERO, RoadObstacle.Kind.ROADWORKS)
	await _frames(4)
	game.set_physics_process(false)
	game.player.active = false
	for unit in game.pursuit.units:
		unit.z = 240.0
		unit.speed = 62.0
	game.pursuit.advance(game.pursuit.clean_escape_seconds + 0.2, game.player.position, 62.0, 62.0)
	await _frames(3)
	_check(game.secret_escapes == 1 and game.state == game.GameState.PLAYING, "real separation and sustained disengagement escape")
	await _save("secret_escape.png")
	_start_clear(game)
	game.progress.distance_points = 15600.0
	game.obstacles._take_obstacle().activate(Vector3.ZERO, RoadObstacle.Kind.ROADWORKS)
	await _frames(4)
	game.set_physics_process(false)
	game.player.active = false
	for unit in game.pursuit.units:
		unit.z = 4.0
		unit.x = game.player.position.x
		unit.speed = 0.0
	game.pursuit.advance(game.pursuit.capture_seconds + 1.0, game.player.position, 0.0, 62.0)
	await _frames(240)
	_check(game.state == game.GameState.GAME_OVER and game.aftermath.arrived and game.community.resume_button.visible, "capture and police arrival reveal continuation")
	await _save("secret_caught.png")
	game.community.resume_button.pressed.emit()
	await _save("secret_bribe.png")
	game._on_resume_code_submitted("CAPTURE-RESUME")
	await _frames(15)
	_check(game.run_resumed and game.state == game.GameState.PLAYING, "configured resume starts assisted run")
	await _save("secret_resumed.png")
	game._finish_run("Your resumed run is complete.")
	await _save("secret_resumed_results.png")
	game.return_to_menu()
	game.records.record_run("Alex", 2, 42780, 4280, false, 2)
	game.records.record_run("Mara", 2, 26390, 2750, false, 1)
	game._on_leaderboard_requested(2, false)
	await _save("secret_leaderboard.png")
	game._on_leaderboard_requested(2, true)
	await _save("secret_resumed_leaderboard.png")
	game.community.dismiss()
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("SECRET CAPTURE PASS: 13 named/access/level/pursuit/escape/capture/continuation/ranking views from real contacts and separation and sustained capture")
	quit(1 if failures else 0)


func _start_clear(game: Node3D) -> void:
	game.set_physics_process(true)
	game.start_game()
	_clear(game)


func _clear(game: Node3D) -> void:
	for obstacle in game.obstacles.obstacle_pool:
		obstacle.deactivate()


func _frames(count: int) -> void:
	for frame in range(count):
		await process_frame


func _save(file_name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://tests/" + file_name) == OK, "capture saved")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("SECRET CAPTURE FAIL: " + label)
