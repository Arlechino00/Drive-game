extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if not game.has_method("_on_pothole_hit") or not game.has_method("_on_roadworks_entered"):
		_check(false, "distinct road hazards are integrated into the game")
		game.audio.stop_all()
		game.free()
		quit(1)
		return
	for mode in [0, 1]:
		game.return_to_menu()
		game.select_mode(mode)
		game.obstacles.spawning_enabled = false
		game.start_game()
		for obstacle in game.obstacles.obstacle_pool:
			obstacle.deactivate()
		game.progress.distance_points = 2000.0
		var before: int = game.get_score()
		var initial_speed: float = game.speed
		var hole = game.obstacles._take_obstacle()
		hole.activate(Vector3.ZERO, 4)
		await _physics_frames(4)
		_check(game.state == game.GameState.PLAYING and not hole.active, "real first pothole contact penalizes once")
		_check(game.get_score() < before - 400 and game.get_score() >= before - 500, "real contact deducts points")
		var damaged_speed := maxf(27.0, initial_speed - game.progress.POTHOLE_SPEED_LOSS)
		_check(game.speed <= damaged_speed + 1.0 and game.speed < initial_speed - 8.0, "first pothole reduces speed to the physical recovery floor at the new opening speed")
		_check(game.progress.pothole_remaining > 9.8 and game.ui.hazard_warning.visible, "HUD shows the repeat-hit window")
		_check("Recovering" in game.ui.boost_hint.text, "boost hint explains the temporary recovery lock")
		game.pause_game()
		var timer: float = game.progress.pothole_remaining
		var speed: float = game.speed
		await _physics_frames(30)
		_check(game.progress.pothole_remaining == timer and game.speed == speed, "pause freezes damage timer and speed")
		game.resume_game()
		_boost_key(true)
		var charge_after_hit: float = game.progress.boost_charge
		await _physics_frames(60)
		_check(not game.progress.boosting and game.progress.boost_charge == charge_after_hit, "holding boost during damage consumes no fuel and adds no speed")
		_boost_key(false)
		await _physics_frames(210)
		_check(game.progress.damage_remaining == 0.0 and game.speed > initial_speed - 1.0, "cruise speed recovers after four seconds")
		_check("Hold Shift" in game.ui.boost_hint.text, "boost hint returns after recovery")
		_check(game.progress.pothole_remaining > 5.0 and game.ui.hazard_warning.visible, "repeat-hit warning outlasts speed recovery")
		var another = game.obstacles._take_obstacle()
		another.activate(Vector3(game.player.position.x, 0, 0), 4)
		await _physics_frames(4)
		_check(game.state == game.GameState.GAME_OVER and game.progress.score_valid, "second actual hole contact ends a valid run")
		_check(not game.aftermath.active, "pothole failure has no unrelated wreck")
		game.start_game()
		_check(game.progress.pothole_remaining == 0.0 and not game.ui.hazard_warning.visible, "restart resets the hole window and warning")
		for obstacle in game.obstacles.obstacle_pool:
			obstacle.deactivate()
		game.progress.distance_points = 99999999.0
		var saved_before := FileAccess.get_file_as_bytes("user://highscore.cfg")
		var prior_best: int = game.best_score
		var works = game.obstacles._take_obstacle()
		works.activate(Vector3.ZERO, 5)
		await _physics_frames(4)
		_check(game.state == game.GameState.GAME_OVER and game.get_score() == 0 and not game.progress.score_valid, "construction contact invalidates the score")
		_check(game.best_score == prior_best and FileAccess.get_file_as_bytes("user://highscore.cfg") == saved_before, "disqualified run changes no saved records")
		_check("INVALID" in game.ui.final_score_label.text and not game.ui.record_label.visible, "result clearly marks invalidation")
		_check(game.aftermath.active, "police respond to construction entry")
		game.aftermath.advance(4.0)
		_check(game.aftermath.arrived, "police pull up alongside")
		game.start_game()
		_check(not game.aftermath.active and game.progress.score_valid, "restart after police arrival cleans up")
		for leave in ["restart", "menu"]:
			for obstacle in game.obstacles.obstacle_pool:
				obstacle.deactivate()
			await _physics_frames(4)
			game.obstacles._take_obstacle().activate(Vector3.ZERO, 5)
			await _physics_frames(4)
			_check(game.aftermath.active and not game.aftermath.arrived and game.audio.police_loop.playing, "police approach is active before leaving")
			if leave == "restart":
				game.start_game()
			else:
				game.return_to_menu()
			_check(not game.aftermath.active and not game.aftermath.visible and not game.aftermath.police.visible and not game.aftermath.wreck.visible, "leaving during approach hides police and wreck actors")
			_check(not game.audio.police_loop.playing and game.progress.score_valid, "leaving during approach stops siren and clears invalidation")
			if leave == "menu":
				_check(game.state == game.GameState.MENU and not game.player.active, "mid-approach menu returns to the title")
				game.start_game()
		for obstacle in game.obstacles.obstacle_pool:
			obstacle.deactivate()
		var struck = game.obstacles._take_obstacle()
		struck.activate(Vector3(0, 0, -4), 2)
		await _physics_frames(4)
		_check(game.state == game.GameState.GAME_OVER and game.aftermath.active and game.aftermath.wreck_kind == 2, "actual van crash preserves struck model in police scene")
		var stopped_player: Vector3 = game.player.position
		var stopped_wreck: Vector3 = game.aftermath.wreck.position
		var stopped_road: Vector3 = game.road.segments[0].position
		var score_after_crash: int = game.get_score()
		await _physics_frames(40)
		_check(game.player.position == stopped_player and game.aftermath.wreck.position == stopped_wreck, "both crashed cars stay stopped")
		_check(game.road.segments[0].position == stopped_road and game.get_score() == score_after_crash, "police animation never resumes driving or scoring")
	game.return_to_menu()
	game.audio.stop_all()
	# The mixer uses wall time; fixed-FPS simulation can exhaust timers instantly.
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("HAZARDS PASS: real contacts, first-hit penalties, speed/boost recovery, paused timer, repeat-hole game over, disqualification preserves saves, stopped wrecks, mid-approach restart/menu cleanup in both modes")
	quit(1 if failures else 0)


func _physics_frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
	await process_frame


func _boost_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("HAZARDS FAIL: " + label)
