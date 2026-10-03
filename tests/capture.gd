extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.run_seed = 2468
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/menu.png")
	game.start_game()
	# Scripted encounter framing, using the same pooled traffic as gameplay.
	game.obstacles.obstacle_pool[0].activate(Vector3(-5.0, 0.0, -30.0), RoadObstacle.Kind.CAR)
	game.obstacles.obstacle_pool[1].activate(Vector3(5.0, 0.0, -55.0), RoadObstacle.Kind.VAN)
	for frame in range(60):
		await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/gameplay.png")
	_key(KEY_SHIFT, true)
	for frame in range(35):
		await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/boost.png")
	_key(KEY_SHIFT, false)
	game.road.reset_road()
	game.road.advance(450.0)
	game.distance = 450.0
	game.progress.distance_points = 4500.0
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/city.png")
	game.road.reset_road()
	game.road.advance(850.0)
	game.distance = 850.0
	game.progress.distance_points = 8500.0
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/canopy.png")
	for obstacle in game.obstacles.obstacle_pool:
		obstacle.deactivate()
	game.player.position.x = RoadObstacle.PLAYER_HALF_WIDTH + 1.0 + 0.3
	game.obstacles.obstacle_pool[0].activate(Vector3(0.0, 0.0, -6.0), RoadObstacle.Kind.CAR, game.player.position.x)
	for frame in range(40):
		await physics_frame
	await RenderingServer.frame_post_draw
	if game.progress.near_misses != 1:
		failures += 1
		push_error("CAPTURE FAIL: real near-miss feedback")
	_save_frame("res://tests/near_miss.png")
	game.pause_game()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/paused.png")
	game.resume_game()
	game._on_player_hit()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/game_over.png")
	game.return_to_menu()
	game.ui._open_settings(game.ui.menu)
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/settings.png")
	game.ui._close_settings()
	game.ui.mode_buttons[1].pressed.emit()
	await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/menu_infinite.png")
	game.start_game()
	for obstacle in game.obstacles.obstacle_pool:
		obstacle.deactivate()
	game.obstacles.obstacle_pool[0].activate(Vector3(-5.0, 0.0, -115.0), RoadObstacle.Kind.CAR)
	game.obstacles.obstacle_pool[1].activate(Vector3(5.0, 0.0, -155.0), RoadObstacle.Kind.VAN)
	_key(KEY_SHIFT, true)
	for frame in range(120):
		await process_frame
	await RenderingServer.frame_post_draw
	_save_frame("res://tests/infinite_boost.png")
	_key(KEY_SHIFT, false)
	game.return_to_menu()
	game.audio.stop_all()
	await create_timer(0.12).timeout
	game.free()
	await process_frame
	if failures == 0:
		print("CAPTURE PASS: Fair/Infinite Boost menus and driving, city, canopy, near miss, pause, game over, settings")
	quit(1 if failures > 0 else 0)


func _save_frame(path: String) -> void:
	var image := root.get_texture().get_image()
	var result := image.save_png(path)
	if result != OK:
		failures += 1
		push_error("CAPTURE FAIL: %s (%s)" % [path, result])


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
