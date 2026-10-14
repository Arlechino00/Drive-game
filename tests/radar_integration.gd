extends SceneTree

const L = preload("res://scripts/localization.gd")

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if not game.has_method("_brake_requested"):
		_check(false, "game implements brake input")
		await _close(game)
		quit(1)
		return
	game.set_physics_process(false)
	game.run_seed = 42
	game.start_game()
	_clear(game)
	game.speed = 80.0
	var before_fuel: float = game.progress.boost_charge
	_key(KEY_SHIFT, true)
	_key(KEY_S, true)
	for tick in range(720):
		game._physics_process(1.0 / 60.0)
	_check(game.speed <= 30.0 / 3.6 and game.speed > 0.0, "actual brake reaches a legal thirty km/h speed")
	_check(not game.progress.boosting and is_equal_approx(game.progress.boost_charge, before_fuel), "brake overrides held boost without using fuel")
	_key(KEY_SHIFT, false)
	_key(KEY_S, false)
	var slow_speed: float = game.speed
	game._physics_process(1.0)
	_check(game.speed > slow_speed, "release brake accelerates back toward cruise")
	_key(KEY_DOWN, true)
	_check(game._brake_requested(), "down arrow also brakes")
	_key(KEY_DOWN, false)

	for mode in [0, 1, 2]:
		# Keep the established secret-access check by configuring a test-only code.
		if mode == 2:
			var config := ConfigFile.new()
			config.set_value("secret_mode", "access_code", "RADAR-TEST")
			config.save("user://radar_access_config.cfg")
			game.access = load("res://scripts/secret_access.gd").new("user://radar_access_save.cfg", "user://radar_access_config.cfg")
			game.access.unlock("RADAR-TEST")
		game.selected_mode = mode
		game.start_game()
		_clear(game)
		game.enforcement.sector_at = 1.0
		game.enforcement.radar_at = 2.0
		game.enforcement.radar_pending = true
		game.enforcement.sector_end = 5000.0
		game.enforcement.next_limit = 30
		game.speed = 62.0
		var before_score: int = game.get_score()
		game._physics_process(0.1)
		_check(game.pursuit.active and not game.pursuit.timed_chase, "speeding radar triggers capture-based police in mode %d" % mode)
		_check(game.heat.level() > 0 and game.pursuit.capture_seconds == 5.0, "radar raises heat without shortening sustained arrest")
		_check(game.enforcement.fine_points > 0 and game.progress.score_penalty == game.enforcement.fine_points and game.get_score() <= before_score + floori(game.progress.distance_points), "fines deduct points in mode %d" % mode)
		var duration: float = game.pursuit.chase_duration
		var gap: float = game.pursuit.gap_m
		game.pause_game()
		var paused_distance: float = game.distance
		game._physics_process(5.0)
		_check(game.distance == paused_distance and game.pursuit.gap_m == gap and game.pursuit.chase_duration == duration, "pause freezes radar and police")
		game.resume_game()
		for unit in game.pursuit.units:
			unit.z = 150.0
		game.pursuit.advance(duration + 0.1, Vector3.ZERO, 62.0, 62.0)
		await process_frame
		_check(not game.pursuit.active and game.state == game.GameState.PLAYING, "real separation and disengagement end pursuit")
		game.start_game()
		_clear(game)
		_check(game.enforcement.fine_points == 0 and not game.pursuit.active, "restart clears fines and police")

	game.selected_mode = 0
	game.start_game()
	_clear(game)
	game.enforcement.sector_at = 1.0
	game.enforcement.radar_at = 2.0
	game.enforcement.radar_pending = true
	game.enforcement.sector_end = 100.0
	game.enforcement.next_limit = 30
	game.speed = 8.0
	_key(KEY_S, true)
	game._physics_process(0.5)
	_key(KEY_S, false)
	_check(not game.pursuit.active and game.enforcement.fine_points == 0, "slowing below limit avoids police")
	game.speed = 8.0
	game._on_pothole_hit()
	_check(game.speed <= 8.0, "low-speed pothole damage never accelerates the car")
	game.run_mode = game.GameMode.SECRET
	game._secret_impact("TEST LOW-SPEED DAMAGE", 0, 30.0)
	_check(game.speed <= 8.0, "low-speed Secret impact never accelerates the car")
	game.pursuit.reset_pursuit()
	game.start_game()
	_clear(game)
	var actor: RoadObstacle = game.obstacles._take_obstacle()
	actor.activate(Vector3(-5, 0, -13), RoadObstacle.Kind.WIDE, 0.0, game.TrafficModels.Model.APEX)
	game._update_apex_race(0.0)
	_check(game.apex_race.active, "Apex fixture begins a real race")
	game._handle_radar({"checked": true, "fine": 200, "chase_seconds": 9.0})
	_check(game.apex_race.active and game.pursuit.active and not game.pursuit.timed_chase, "radar adds police pressure during active Apex")
	_check(game.progress.bonus_points == 0 and game.progress.score_penalty == 200, "radar is a consequence rather than a farmable reward")
	game.pursuit.disengagement_seconds = 2.0
	var heat_before: int = game.heat.level()
	game._handle_radar({"checked": true, "fine": 200, "chase_seconds": 16.0})
	_check(game.pursuit.get_escape_progress() == 0.0 and game.heat.level() > heat_before, "second radar escalates heat and updates escaping driver's location")
	game.pursuit.set_heat(0)
	game.pursuit.begin(Vector3.ZERO, 8.0)
	game.pursuit.gap_m = 4.0
	game.pursuit.units[0].speed = 0.0
	game.pursuit.advance(6.0, Vector3.ZERO, 0.0, 62.0)
	await process_frame
	_check(game.state == game.GameState.GAME_OVER and not game.pursuit.active, "sustained capture reaches arrested game over")
	game.start_game()
	_clear(game)
	game.speed = 80.0
	game.enforcement.sector_at = 1.0
	game.enforcement.radar_at = 67.0
	game.enforcement.radar_pending = true
	game.enforcement.sector_end = 400.0
	game.enforcement.next_limit = 80
	game._physics_process(1.0)
	_check(game.pursuit.active and game.pursuit.get_escape_progress() < 0.02, "delayed frame starts chase at swept radar crossing, not tick start")
	game.pursuit.gap_m = 500.0
	game.pursuit.advance(0.1, Vector3.ZERO, 80.0, 62.0)
	var rear_camera: Camera3D = game.pursuit.get_node("RearView").get_camera_3d()
	_check(rear_camera.far > game.pursuit.gap_m, "distant pursuit police stay within rear-camera range")
	game.start_game()
	_clear(game)
	game.distance = 700.0
	game.speed = 200.0 / 3.6
	game.enforcement.sector_at = 650.0
	game.enforcement.sector_end = 2000.0
	game.enforcement.next_limit = 50
	game.enforcement.radar_at = INF
	game.enforcement.radar_pending = false
	game._physics_process(0.1)
	_check(game.speed * 3.6 > 190.0 and game.enforcement.current_limit == 50 and not game.pursuit.active and game.enforcement.fine_points == 0, "two hundred in a fifty sector has no speed cap or penalty without radar")
	game.enforcement.radar_at = game.distance + 1.0
	game.enforcement.radar_pending = true
	game._physics_process(0.1)
	_check(game.pursuit.active and game.enforcement.fine_points >= 1500, "a radar alone turns two hundred in fifty into fine points and police")
	game.enforcement.next_limit = 30
	game.enforcement.configure_progression(400.0 / 3.6, 1800.0)
	game.radar_display.warning_distance = game.enforcement.warning_distance
	_check(game.enforcement.warning_distance > 950.0, "400 km/h warning includes a physical braking budget")
	var warning: float = game.enforcement.warning_distance
	game.radar_display.update_display(900.0 - warning - 1.0, 0, 30, 800.0, 900.0, true, 400.0, false, 0)
	_check(game.radar_display.radar_label.text == L.text("ui.no_radar_reported") and not game.radar_display.radar_camera.visible, "radar hidden outside dynamic warning radius")
	game.radar_display.update_display(900.0 - warning, 0, 30, 800.0, 900.0, true, 400.0, false, 0)
	_check(not game.radar_display.radar_camera.visible and game.radar_display.radar_label.text.begins_with(L.text("ui.radar_in")), "radar warning starts at dynamic boundary; camera stays hidden on unlimited road")
	game.radar_display.update_display(820.0, 30, 30, 800.0, 900.0, true, 30.0, false, 0)
	_check(game.radar_display.radar_camera.visible, "radar camera appears inside the limited sector")
	var nodes := _node_count(game.radar_display)
	for cycle in range(200):
		game.radar_display.update_display(float(cycle * 500), 0, 30, float(cycle * 500 + 100), float(cycle * 500 + 200), true, 200.0, false, cycle * 100)
	_check(nodes == _node_count(game.radar_display), "radar signs and camera are reused without node growth")
	game.return_to_menu()
	_check(not game.radar_display.sector_sign.visible and not game.radar_display.radar_camera.visible, "menu clears roadside props")
	await _close(game)
	print("RADAR INTEGRATION PASS" if failures == 0 else "RADAR INTEGRATION FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _clear(game) -> void:
	game.obstacles.spawning_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()


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


func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func _close(game) -> void:
	paused = false
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.queue_free()
	await process_frame
	await process_frame
