extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.selected_mode = game.GameMode.INFINITE_BOOST
	game.start_game()
	game.obstacles.spawning_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.enforcement.sector_at = INF
	game.enforcement.radar_at = INF
	game.enforcement.sector_end = INF
	game.distance = 2000.0
	game.run_seconds = 630.0
	_key(KEY_SHIFT, true)
	for tick in range(360):
		game._physics_process(1.0 / 60.0)
	_check(game.speed * 3.6 > 300.0, "actual held boost reaches above three hundred km/h")
	_key(KEY_SHIFT, false)
	game.speed = 300.0 / 3.6
	var start_distance: float = game.distance
	_key(KEY_S, true)
	for tick in range(60):
		game._physics_process(1.0 / 60.0)
	_check(game.speed * 3.6 >= 270.0, "one second of braking at three hundred retains over two hundred seventy")
	var elapsed := 1.0
	while game.speed * 3.6 > 30.0 and elapsed < 20.0:
		game._physics_process(1.0 / 60.0)
		elapsed += 1.0 / 60.0
	var travel: float = game.distance - start_distance
	_check(elapsed >= 10.0 and elapsed <= 12.0, "three hundred to thirty takes roughly eleven seconds")
	_check(travel >= 450.0 and travel <= 550.0, "three hundred to thirty consumes roughly five hundred meters")
	_key(KEY_S, false)
	var max_speed: float = game.director.MAX_BOOST_SPEED
	var minimum_speed: float = 30.0 / 3.6
	var braking_distance: float = (max_speed * max_speed - minimum_speed * minimum_speed) / (2.0 * game.BRAKE_DECELERATION)
	game.enforcement.next_limit = 30
	game.enforcement.configure_progression(max_speed, game.run_seconds)
	_check(game.enforcement.warning_distance > braking_distance and game.enforcement.warning_distance > travel, "dynamic radar warning allows physical three hundred-plus braking")
	# Pressing brake upon the real warning can clear the camera at a legal speed.
	game.speed = 300.0 / 3.6
	game.enforcement.sector_at = game.distance - 1.0
	game.enforcement.next_limit = 30
	game.enforcement.configure_progression(game.speed, game.run_seconds)
	game.enforcement.radar_at = game.distance + game.enforcement.warning_distance
	game.enforcement.sector_end = game.enforcement.radar_at + 100.0
	game.enforcement.radar_pending = true
	_key(KEY_S, true)
	for tick in range(2400):
		game._physics_process(1.0 / 60.0)
		if not game.enforcement.radar_pending:
			break
	_check(game.enforcement.fine_points == 0 and not game.pursuit.active and not game.enforcement.radar_pending, "responsive braking from three hundred clears a properly warned radar")
	_key(KEY_S, false)
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	print("BRAKING DISTANCE PASS: %.2fs, %.1fm from 300 to 30 km/h" % [elapsed, travel] if failures == 0 else "BRAKING DISTANCE FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
