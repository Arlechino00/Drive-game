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
	_start_clear(game)
	game.set_physics_process(false)
	game.player.active = false
	game.player.position.x = -5.0
	game.obstacles._take_obstacle().activate(Vector3(0, 0, -22), RoadObstacle.Kind.ROADWORKS)
	game.obstacles._take_obstacle().activate(Vector3(5, 0, -22), RoadObstacle.Kind.ROADWORKS)
	game.obstacles._take_obstacle().activate(Vector3(5, 0, -65), RoadObstacle.Kind.POTHOLE)
	await _frames(25)
	await _save("roadworks.png")
	game.set_physics_process(true)
	_start_clear(game)
	game.progress.distance_points = 3200.0
	game.obstacles._take_obstacle().activate(Vector3.ZERO, RoadObstacle.Kind.POTHOLE)
	await _frames(5)
	_check(game.state == game.GameState.PLAYING and game.progress.pothole_remaining > 0.0, "actual first hit and warning")
	await _save("pothole_warning.png")
	_start_clear(game)
	game.obstacles._take_obstacle().activate(Vector3(5, 0, -13), RoadObstacle.Kind.POTHOLE)
	game.set_physics_process(false)
	game.player.active = false
	await _frames(8)
	await _save("pothole.png")
	game.set_physics_process(true)
	_start_clear(game)
	game.progress.distance_points = 8500.0
	game.obstacles._take_obstacle().activate(Vector3(0, 0, -6), RoadObstacle.Kind.ROADWORKS)
	await _frames(75)
	_check(game.state == game.GameState.GAME_OVER and not game.progress.score_valid, "real construction violation")
	await _save("police_approaching.png")
	await _frames(150)
	_check_scene_framing(game, false)
	await _save("police_roadworks.png")
	_start_clear(game)
	game.progress.distance_points = 9200.0
	game.obstacles._take_obstacle().activate(Vector3(0, 0, -4.6), RoadObstacle.Kind.CAR)
	await _frames(225)
	_check(game.state == game.GameState.GAME_OVER and game.progress.score_valid, "real traffic crash")
	_check_scene_framing(game, true)
	await _save("police_crash.png")
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("HAZARD CAPTURE PASS: potholes, two-lane roadworks, real damage warning, approaching police, disqualification and stopped crash vehicles")
	quit(1 if failures else 0)


func _start_clear(game: Node3D) -> void:
	game.start_game()
	for obstacle in game.obstacles.obstacle_pool:
		obstacle.deactivate()


func _check_scene_framing(game: Node3D, has_wreck: bool) -> void:
	_check(game.aftermath.active and game.aftermath.arrived, "police park alongside")
	var panel: PanelContainer = game.ui.game_over_menu.get_meta("panel")
	var panel_left := panel.get_global_rect().position.x
	var actors: Array[Node3D] = [game.player, game.aftermath.police]
	if has_wreck:
		actors.append(game.aftermath.wreck)
	for actor in actors:
		var point := actor.global_position + Vector3(0, 0.8, 0)
		var projected: Vector2 = game.camera.unproject_position(point)
		_check(not game.camera.is_position_behind(point) and projected.x > 0 and projected.x < panel_left - 10 and projected.y > 0 and projected.y < 720, "stopped vehicle visible beside result panel")


func _frames(count: int) -> void:
	for frame in range(count):
		await process_frame


func _save(file_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://tests/" + file_name) == OK, "capture saved")


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("HAZARD CAPTURE FAIL: " + label)
