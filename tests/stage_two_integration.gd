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
	game.set_process(false)
	game.start_game()
	game.obstacles.spawning_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.enforcement.sector_at = INF
	game.enforcement.radar_at = INF
	game.enforcement.sector_end = INF
	for tick in range(7200):
		game._physics_process(0.5)
		if tick + 1 in [600, 1200, 2400, 3600, 7200]:
			print("ACTUAL %.0fmin %.1fkm/h %.1fkm" % [game.run_seconds / 60.0, game.speed * 3.6, game.distance / 1000.0])
		_check(is_finite(game.speed) and is_finite(game.distance), "continuous integrated progression remains finite")
	_check(game.speed * 3.6 > 400.0, "actual unboosted run surpasses400km/h")
	game.pause_game()
	var elapsed: float = game.run_seconds
	game._physics_process(60.0)
	_check(game.run_seconds == elapsed, "pause cannot advance survival difficulty")
	game.resume_game()
	game.run_mode = game.GameMode.SECRET
	# Reproduce stale-heat dispatch through the real impact/race-loss paths.
	game.pursuit.set_heat(4)
	game.pursuit.reset_pursuit()
	game.heat.value = 0.0
	game._secret_impact("TEST", 0, 0.0)
	_check(game.pursuit.heat == 0 and game.pursuit.units.size() == 1, "Secret impact synchronizes decayed heat before dispatch")
	game.pursuit.set_heat(4)
	game.pursuit.reset_pursuit()
	game._resolve_apex_race(false)
	_check(game.pursuit.heat == 0 and game.pursuit.units.size() == 1, "Apex loss synchronizes decayed heat before dispatch")
	game.pursuit.reset_pursuit()
	game.progress.bonus_points = 0
	game.progress.score_penalty = 0
	var previous: int = game.get_score()
	game._handle_radar({"checked": true, "fine": 300, "measured_kmh": 330.0, "limit": 80})
	_check(game.get_score() == previous - 300 and game.heat.level() >= 3, "radar penalizes score and raises real Heat")
	game.pursuit.disengagement_seconds = 3.0
	var unit_at: float = game.pursuit.units[0].z
	game._handle_radar({"checked": true, "fine": 300, "measured_kmh": 330.0, "limit": 80})
	_check(game.pursuit.disengagement_seconds == 0.0 and game.pursuit.units[0].z == unit_at and game.pursuit.units.size() == 3, "radar reinforces without teleporting existing units")
	game.return_to_menu()
	game.audio.stop_all()
	game.free()
	await process_frame
	print("STAGE TWO INTEGRATION PASS" if failures == 0 else "STAGE TWO INTEGRATION FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 5:
			push_error(label)
