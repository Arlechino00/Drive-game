extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.tutorial_enabled = true
	game.start_game()
	_check(game.tutorial.active and game.tutorial.practice and not game.community.is_modal_open(), "every round starts a live introduction")
	_key(KEY_A, true)
	_tick(game, 0.5)
	_key(KEY_A, false)
	_key(KEY_D, true)
	_tick(game, 0.9)
	_key(KEY_D, false)
	_check(game.tutorial.current_step() == "brake", "actual steering completes the first action")
	_key(KEY_S, true)
	_tick(game, 1.3)
	_key(KEY_S, false)
	_check(game.tutorial.current_step() == "boost", "actual brake input advances coaching")
	_key(KEY_SHIFT, true)
	_tick(game, 0.8)
	_key(KEY_SHIFT, false)
	_check(game.tutorial.current_step() == "traffic", "actual Boost input advances coaching")
	var original_best: int = game.best_score
	game._finish_run("Practice contact")
	_check(game.state == game.GameState.PLAYING and game.best_score == original_best, "practice contact cannot save a run or end driving")
	_tick(game, 0.02)
	_key(KEY_A, true)
	_tick(game, 0.9)
	_key(KEY_A, false)
	for tick in range(600):
		if game.tutorial.current_step() != "traffic":
			break
		_tick(game, 1.0 / 60.0)
	_check(game.tutorial.current_step() == "radar", "avoiding the real practice car advances to radar")
	_key(KEY_S, true)
	for tick in range(1800):
		if game.tutorial.current_step() != "radar":
			break
		_tick(game, 1.0 / 60.0)
	_key(KEY_S, false)
	_check(game.tutorial.current_step() == "finish" and game.enforcement.fine_points == 0, "actual radar crossing responds to braking")
	for tick in range(180):
		if not game.tutorial.active:
			break
		_tick(game, 1.0 / 60.0)
	_check(not game.tutorial.active and game.distance == 0.0 and game.get_score() == 0, "natural completion starts a fresh normal run")
	game.start_game()
	game.tutorial.skip_button.pressed.emit()
	_check(not game.tutorial.active and game.progress.score_valid and game.distance == 0.0 and game.obstacles.spawning_enabled, "Skip starts a clean normal run")
	game.start_game()
	_check(game.tutorial.active and game.tutorial.step == 0, "repeat rounds also get the introduction")
	game.pause_game()
	var at: float = game.distance
	game._physics_process(1.0)
	_check(game.distance == at and game.tutorial.step == 0, "pause freezes the live introduction")
	game.request_live_tutorial()
	_check(game.tutorial.practice and game.tutorial.step == 0 and not game.obstacles.spawning_enabled, "paused Tutorial resumes existing practice without losing its isolation")
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	_check(not game.tutorial.active and game.distance == 0.0, "Enter easily skips")
	_tick(game, 0.5)
	var normal_distance: float = game.distance
	var normal_score: int = game.get_score()
	game.pause_game()
	game.request_live_tutorial()
	_check(game.tutorial.active and not game.tutorial.practice and game.state == game.GameState.PLAYING, "paused normal round gets live controls coaching")
	game.tutorial.skip_button.pressed.emit()
	_check(game.distance == normal_distance and game.get_score() == normal_score and game.obstacles.spawning_enabled, "dismissing normal-round coaching preserves earned progress")
	game.return_to_menu()
	game.audio.stop_all()
	var drain := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("LIVE TUTORIAL PASS: automatic every round, real steer/brake/Boost, clean Skip/Enter and pause")
	quit(1 if failures else 0)
func _tick(game, seconds: float) -> void:
	for tick in range(ceili(seconds * 60.0)):
		game.player._physics_process(1.0 / 60.0)
		game._physics_process(1.0 / 60.0)
func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("LIVE TUTORIAL FAIL: " + label)
