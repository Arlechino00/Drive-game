extends SceneTree

const Progress = preload("res://scripts/run_progress.gd")
const Director = preload("res://scripts/difficulty_director.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var progress := Progress.new()
	progress.reset(true)
	_check(progress.update_boost(true, 120.0) and progress.boost_charge == 1.0, "unlimited boost survives a long hold")
	_check(not progress.update_boost(false, 0.1) and progress.boost_charge == 1.0, "unlimited boost still follows input")
	progress.reset(false)
	_check(progress.boost_charge == 0.4 and not progress.infinite_boost, "fair mode restores earned-fuel rules")
	progress.update_boost(true, 2.0)
	_check(not progress.boosting and progress.boost_charge == 0.0, "fair boost runs out")
	var director := Director.new()
	var distance := 0.0
	var speed := director.INITIAL_SPEED
	for frame in range(900):
		speed = move_toward(speed, director.get_base_speed(distance), 12.0 / 60.0)
		distance += speed / 60.0
	_check(director.INITIAL_SPEED * 3.6 >= 130.0, "accessible opening speed")
	_check(speed > director.INITIAL_SPEED and speed * 3.6 < 150.0, "speed builds smoothly during the first fifteen seconds")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var records := ConfigFile.new()
	records.load("user://highscore.cfg")
	records.set_value("scores", "best", 123456)
	records.set_value("scores_infinite", "best", 0)
	records.save("user://highscore.cfg")
	game.select_mode(1)
	game.start_game()
	for obstacle in game.obstacles.obstacle_pool:
		obstacle.deactivate()
	_check(game.run_mode == 1 and game.progress.infinite_boost, "title mode selection reaches gameplay")
	_key(KEY_SHIFT, true)
	for frame in range(130):
		await physics_frame
	_check(game.progress.boosting and game.progress.boost_charge == 1.0, "real held input does not drain unlimited mode")
	game.pause_game()
	game.select_mode(0)
	_check(game.run_mode == 1 and game.selected_mode == 1, "mode cannot change during an existing run")
	var paused_speed: float = game.speed
	for frame in range(5):
		await physics_frame
	_check(game.speed == paused_speed, "unlimited mode still pauses")
	_key(KEY_SHIFT, false)
	game.start_game()
	_check(game.run_mode == 1 and game.progress.infinite_boost and not game.progress.boosting, "restart retains mode and clears active boost")
	game.progress.distance_points = 999999.0
	game._on_player_hit()
	records.load("user://highscore.cfg")
	_check(int(records.get_value("scores", "best", 0)) == 123456, "infinite score does not overwrite fair record")
	_check(int(records.get_value("scores_infinite", "best", 0)) == 999999, "infinite mode saves its own record")
	game.return_to_menu()
	game.select_mode(0)
	_check(game.best_score == 123456, "fair record loads again when selected")
	game.start_game()
	_check(not game.progress.infinite_boost and game.progress.boost_charge == 0.4, "switching back restores fair boost")
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("MODES PASS: fast pace, title selection, unlimited input, fair fuel, pause/restart, separate records")
	quit(1 if failures else 0)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("MODES FAIL: " + label)
