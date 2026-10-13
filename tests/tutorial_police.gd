extends SceneTree
## Exercise the real Secret practice drive through input and police simulation.
const DT := 1.0 / 60.0
const SEED := 771
var failures := 0
var max_capture := 0.0
var records_before := {}
var normal_random_state := {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.set_process(false)
	# The normal test runner disables coaching; this fixture explicitly opts in.
	game.tutorial_enabled = true
	game.run_seed = SEED
	var config := ConfigFile.new()
	config.set_value("secret_mode", "access_code", "TUTORIAL-POLICE-TEST")
	_check(config.save("user://tutorial_police_config.cfg") == OK, "isolated Secret configuration saves")
	game.access = load("res://scripts/secret_access.gd").new("user://tutorial_police_access.cfg", "user://tutorial_police_config.cfg")
	_check(game.access.unlock("TUTORIAL-POLICE-TEST"), "isolated Secret setup")
	game.selected_mode = game.GameMode.SECRET
	game.start_game(false)
	normal_random_state = _random_state(game)
	records_before = _records_snapshot(game)
	var original_best: int = game.best_score
	var caught_events := [0]
	var escaped_events := [0]
	var escaped_details := {"gap": 0.0, "separated": 0.0}
	game.pursuit.caught.connect(func(): caught_events[0] += 1)
	game.pursuit.escaped.connect(func():
		escaped_events[0] += 1
		escaped_details.gap = game.pursuit.gap_m
		escaped_details.separated = game.pursuit.disengagement_seconds)

	game.start_game()
	await _reach_escape(game)
	var initial_gap: float = game.pursuit.gap_m
	game.pause_game()
	game._physics_process(1.0)
	_check(game.pursuit.gap_m == initial_gap and game.pursuit.training_escape, "pause freezes and preserves the practice escape")
	game.resume_game()
	for tick in range(1200):
		if not game.tutorial.active:
			break
		await _tick(game, DT)
	_check(not game.tutorial.active, "natural physical separation completes the introduction")
	_check(caught_events[0] == 0 and escaped_events[0] == 1, "ordinary driving escapes the single practice unit without an arrest")
	_check(escaped_details.gap >= 100.0 and escaped_details.separated >= 5.0 - 0.000000001, "escape requires an actual 100 metre gap held for five seconds")
	_check_fresh_run(game)
	_check(game.best_score == original_best and _records_snapshot(game) == records_before, "natural practice completion never writes records")
	print("TUTORIAL POLICE natural: capture=%.3f escape_gap=%.3f separation=%.3f" % [max_capture, escaped_details.gap, escaped_details.separated])

	# Every round shows the intro again. Skip must clear a live training flag,
	# including when the round was paused in the escape exercise.
	game.start_game()
	await _reach_escape(game)
	game.pause_game()
	game.tutorial.skip_button.pressed.emit()
	_check(not paused and game.state == game.GameState.PLAYING, "Skip from paused practice starts an unpaused normal run")
	_check_fresh_run(game)
	_check(_records_snapshot(game) == records_before, "Skip never writes records")

	# Reproduce the failed-demo callback after police have become inactive.
	# A delayed frame must return to a fresh capture exercise, not a stalled
	# escape exercise with no unit left to separate from.
	game.start_game()
	await _reach_escape(game)
	game.pursuit.reset_pursuit()
	game._on_pursuit_caught()
	game._physics_process(35.0)
	_check(game.tutorial.active and game.tutorial.practice and game.tutorial.current_step() == "capture", "inactive police callback and long frame restart the capture exercise")
	_check(game.pursuit.active and game.pursuit.units.size() == 1 and not game.pursuit.training_escape, "retry restores one real unit and clears training escape")
	_check(game.pursuit.capture_fraction <= 0.6, "practice retry retains the capture safety cap")
	_check_practice_score(game)
	_check(game.best_score == original_best and _records_snapshot(game) == records_before, "failed practice and long frame never save a run")
	game.tutorial.skip_button.pressed.emit()
	_check_fresh_run(game)

	game.return_to_menu()
	game.audio.stop_all()
	var drain := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("TUTORIAL POLICE PASS: real input/capture/separation, clean points/records/RNG, pause/Skip/repeat/retry")
	quit(1 if failures else 0)

func _reach_escape(game) -> void:
	_check(game.tutorial.active and game.tutorial.practice and game.tutorial.secret_guide and game.tutorial.step == 0, "each Secret round automatically starts the practice introduction")
	_key(KEY_A, true)
	await _tick(game, 0.5)
	_key(KEY_A, false)
	_key(KEY_D, true)
	await _tick(game, 0.9)
	_key(KEY_D, false)
	_check(game.tutorial.current_step() == "boost", "real steering reaches Boost")
	_key(KEY_SHIFT, true)
	await _tick(game, 0.8)
	_key(KEY_SHIFT, false)
	_check(game.tutorial.current_step() == "capture" and game.pursuit.active, "real Boost starts the single police unit")
	await _tick(game, 1.3)
	_check(game.pursuit.capture_fraction > 0.08 and game.pursuit.capture_fraction <= 0.6, "police pressure visibly fills the real capture meter safely")
	_key(KEY_A, true)
	await _tick(game, 1.2)
	_key(KEY_A, false)
	_check(game.tutorial.current_step() == "escape" and game.pursuit.training_escape, "actual steering enters the tutorial-only physical escape")
	_check(game.pursuit.units.size() == 1 and game.pursuit.gap_m < 100.0, "escape starts before real separation with one visible unit")

func _tick(game, seconds: float) -> void:
	for tick in range(ceili(seconds * 60.0)):
		game.player._physics_process(DT)
		game._physics_process(DT)
		max_capture = maxf(max_capture, game.pursuit.capture_fraction)
		if game.tutorial.active and game.tutorial.practice:
			_check_practice_score(game)
		# Drain the generation-guarded escape callback without automatic driving.
		if tick % 30 == 0:
			await process_frame

func _check_practice_score(game) -> void:
	_check(game.progress.distance_points == 0.0 and game.progress.bonus_points == 0 and game.run_seconds == 0.0 and game.secret_escapes == 0, "practice keeps normal score/time/rewards untouched")

func _check_fresh_run(game) -> void:
	_check(not game.tutorial.active and not game.pursuit.active and not game.pursuit.training_escape, "normal run restores production police state")
	_check(game.distance == 0.0 and game.get_score() == 0 and game.run_seconds == 0.0 and game.progress.score_valid, "normal run starts with valid score and zero distance/time")
	_check(game.enforcement.fine_points == 0 and game.heat.level() == 0 and game.secret_escapes == 0, "practice leaves no fines, heat or escape rewards")
	_check(game.obstacles.spawning_enabled and game.obstacles.active_seed == SEED and _random_state(game) == normal_random_state, "normal traffic/radar/race random streams reset to the original seed state")

func _random_state(game) -> Dictionary:
	return {"traffic": game.obstacles.random.state, "radar": game.enforcement.random.state, "chase": game.enforcement._chase_random.state, "race": game.race_random.state}

func _records_snapshot(game) -> Dictionary:
	var result := {}
	for path in [game.records.save_path, "user://highscore.cfg"]:
		result[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
	return result

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
		push_error("TUTORIAL POLICE FAIL: " + label)
