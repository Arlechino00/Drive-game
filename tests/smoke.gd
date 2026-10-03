extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_check(game.state == game.GameState.MENU, "initial menu")
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await process_frame
	_check(game.community.name_dialog.visible and game.state == game.GameState.MENU, "start requests player name")
	game.community.name_input.text = "Smoke Driver"
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	for frame in range(2):
		await physics_frame
	_check(game.state == game.GameState.PLAYING, "start")
	_check(game.road.segments.size() == game.road.SEGMENT_COUNT, "initial road count")
	_check(game.obstacles.get_active_count() > 0, "initial obstacles")
	for frame in range(20):
		await physics_frame
	_check(game.distance > 0.0 and game.get_score() > 0, "distance scoring")
	game.pause_game()
	var paused_distance: float = game.distance
	var paused_position: Vector3 = game.player.position
	var paused_velocity: float = game.player.lateral_velocity
	_key(KEY_D, true)
	for frame in range(12):
		await physics_frame
	_check(is_equal_approx(game.distance, paused_distance), "pause stops distance")
	_check(game.player.position.is_equal_approx(paused_position), "pause stops steering")
	_check(is_equal_approx(game.player.lateral_velocity, paused_velocity), "pause stops steering acceleration")
	game.resume_game()
	for frame in range(12):
		await physics_frame
	_check(game.distance > paused_distance, "resume")
	_check(game.player.position.x > paused_position.x, "D steering after resume")
	_key(KEY_D, false)
	for frame in range(30):
		await physics_frame
	_check(is_zero_approx(game.player.lateral_velocity), "steering settles after release")
	var target: RoadObstacle
	for obstacle in game.obstacles.obstacle_pool:
		if obstacle.active:
			target = obstacle
			break
	_check(target != null, "collision target")
	if target == null:
		quit(1)
		return
	game.player.position.x = target.position.x
	target.position.z = -8.0
	for frame in range(20):
		await physics_frame
	_check(game.state == game.GameState.GAME_OVER, "collision game over")
	var final_distance: float = game.distance
	for frame in range(5):
		await physics_frame
	_check(is_equal_approx(game.distance, final_distance), "game over stops scoring")
	var saved_score := ConfigFile.new()
	_check(saved_score.load("user://highscore.cfg") == OK, "high score saved")
	_check(int(saved_score.get_value("scores", "best", 0)) >= game.get_score(), "high score value")
	_key(KEY_R, true)
	_key(KEY_R, false)
	for frame in range(2):
		await physics_frame
	_check(game.state == game.GameState.PLAYING and game.distance < 2.0, "R restart")
	_check(is_zero_approx(game.player.position.x) and is_zero_approx(game.player.lateral_velocity), "restart resets steering")
	var distance_after_recycling := 0.0
	for step in range(200):
		distance_after_recycling += 10.0
		game.road.advance(10.0)
		game.obstacles.advance(10.0, distance_after_recycling, 1.0)
	_check(game.road.segments.size() == game.road.SEGMENT_COUNT, "bounded road segments")
	_check(game.obstacles.obstacle_pool.size() <= 20, "bounded obstacle pool")
	game.return_to_menu()
	game.audio.stop_all()
	await create_timer(0.12).timeout
	game.free()
	await process_frame
	if failures == 0:
		print("SMOKE PASS: start, steering, release, pause, collision, score saving, restart, bounded generation")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("SMOKE FAIL: " + label)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
