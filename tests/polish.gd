extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.run_seed = 2468
	game.start_game()
	_check(game.obstacles.active_seed == 2468, "root forwards reproducible seed")
	_key(KEY_SHIFT, true)
	for frame in range(20):
		await physics_frame
	_check(game.progress.boosting and game.speed > 35.0, "boost accelerates and responds to Shift")
	_check(game.player.boosting, "boost visual follows gameplay")
	_key(KEY_D, true)
	for frame in range(5):
		await physics_frame
	await process_frame
	for obstacle in game.obstacles.obstacle_pool:
		if obstacle.active:
			_check(is_equal_approx(obstacle._previous_player_x, game.player.position.x), "pass samples current steering tick")
	game.pause_game()
	var paused_charge: float = game.progress.boost_charge
	var paused_score: int = game.get_score()
	var paused_speed: float = game.speed
	var paused_camera: Vector3 = game.camera.position
	_key(KEY_D, true)
	for frame in range(12):
		await physics_frame
	_check(game.progress.boost_charge == paused_charge and game.get_score() == paused_score, "pause freezes boost and score")
	_check(game.speed == paused_speed and game.camera.position == paused_camera, "pause freezes speed and camera")
	_key(KEY_D, false)
	_key(KEY_SHIFT, false)
	game.progress.boost_empty_lock = true
	game.progress.boost_charge = 0.4
	_key(KEY_SHIFT, true)
	_key(KEY_SHIFT, false)
	_key(KEY_SHIFT, true)
	game.resume_game()
	for frame in range(2):
		await physics_frame
	_check(game.progress.boosting, "fresh boost press after release during pause")
	_key(KEY_SHIFT, false)
	await physics_frame
	var target = game.obstacles.obstacle_pool[0]
	game.player.position.x = RoadObstacle.PLAYER_HALF_WIDTH + 1.0 + 0.3
	target.activate(Vector3(0.0, 0.0, -6.0), target.Kind.CAR, game.player.position.x)
	for frame in range(40):
		await physics_frame
	_check(game.state == game.GameState.PLAYING, "real close pass survives")
	_check(game.progress.near_misses == 1 and game.progress.multiplier > 1.0, "traffic reward reaches combo HUD")
	_check(game.progress.bonus_points > 0 and game.ui.combo_label.text.contains("1.5"), "near-miss bonus and HUD")
	for frame in range(8):
		await physics_frame
	_check(game.progress.near_misses == 1, "passed traffic cannot award twice")
	target.activate(Vector3(game.player.position.x, 0.0, -5.0), target.Kind.CAR, game.player.position.x)
	for frame in range(25):
		await physics_frame
	_check(game.state == game.GameState.GAME_OVER, "moving traffic crashes")
	_check(game.progress.near_misses == 1, "crash does not reward a close pass")
	_check(not game.progress.boosting and not game.player.boosting, "crash disables boost")
	var saved := ConfigFile.new()
	_check(saved.load("user://highscore.cfg") == OK, "run records persist")
	_check(float(saved.get_value("scores", "distance", 0.0)) >= game.distance, "distance record persists")
	game.start_game()
	_check(game.progress.near_misses == 0 and game.progress.bonus_points == 0, "restart resets risk rewards")
	_check(game.progress.boost_charge == 0.4, "restart resets boost")
	game._on_player_hit()
	game.start_game()
	_check(not game.crash_effect.visible, "immediate restart hides old sparks")
	_check(not game.audio.cues["crash"].playing, "immediate restart stops crash sound")
	var audio_nodes: int = game.audio.get_child_count()
	for restart in range(25):
		game.start_game()
		await process_frame
	_check(game.audio.get_child_count() == audio_nodes, "restart does not multiply sounds")
	game.pause_game()
	game.return_to_menu()
	_check(not paused and game.state == game.GameState.MENU and game.ui.menu.visible, "main menu unpauses and shows title")
	_check(not game.player.active and game.obstacles.get_active_count() == 0, "main menu clears active encounters")
	game.audio.stop_all()
	# AudioServer releases stopped playback on its next mix, not synchronously.
	await create_timer(0.12).timeout
	game.free()
	await process_frame
	if failures == 0:
		print("POLISH PASS: boost, pause, real near miss, combo HUD, traffic crash, records, restart, main menu, bounded audio")
	quit(1 if failures > 0 else 0)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("POLISH FAIL: " + label)
