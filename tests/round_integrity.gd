extends SceneTree

class RecordProbe:
	extends "res://scripts/player_records.gd"
	var writes := 0
	var scores: Array[int] = []
	func record_run(_name: String, _mode: int, score: int, _distance: float, _resumed: bool = false, _escapes: int = 0) -> Error:
		writes += 1
		scores.append(score)
		return OK

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.tutorial_enabled = false
	var probe := RecordProbe.new()
	game.records = probe
	game.player_name = "Audit driver"
	game.start_game(false)
	game.progress.bonus_points = 123
	game.return_to_menu()
	_check(probe.writes == 1 and probe.scores == [123], "Menu settles the actual round")
	game.return_to_menu()
	_check(probe.writes == 1, "Menu is idempotent")
	game.start_game(false)
	game.progress.bonus_points = 456
	game.start_game(false)
	_check(probe.writes == 2 and probe.scores.back() == 456, "Restart settles before clearing score")
	game.progress.bonus_points = 789
	game._finish_run("Test")
	game.return_to_menu()
	_check(probe.writes == 3 and probe.scores.back() == 789, "Crash then Menu saves exactly once")
	game.start_game(false)
	game.progress.bonus_points = 999
	game.progress.invalidate_score()
	game.return_to_menu()
	_check(probe.writes == 3, "Disqualification cannot write ranked records")
	game.tutorial_enabled = true
	game.start_game()
	game.progress.bonus_points = 500
	game.return_to_menu()
	_check(probe.writes == 3, "Practice cannot write records")
	game.start_game(false)
	game.speed = 8.0
	game.enforcement.radar_pending = false
	game.enforcement.current_limit = 0
	for tick in range(19):
		game._update_ranked_pace(1.0)
	_check(game.progress.ranked_eligible, "Nineteen seconds of crawling retains grace")
	game.speed = 40.0
	game._update_ranked_pace(0.5)
	game.speed = 8.0
	game._update_ranked_pace(1.0)
	_check(not game.progress.ranked_eligible, "Brief release cannot erase crawling time")
	game.progress.update_boost(true, 0.1)
	_check(game.progress.boosting and game.progress.score_valid, "Unranked driving still allows finite Boost")
	game.progress.bonus_points = 500
	game.return_to_menu()
	_check(probe.writes == 3, "Unranked rounds cannot write personal or named records")
	game.start_game(false)
	game.speed = 8.0
	game.enforcement.radar_pending = true
	game.enforcement.radar_at = game.distance + 100.0
	game.enforcement.warning_distance = 320.0
	game._update_ranked_pace(60.0)
	_check(game.progress.ranked_eligible and game.progress.slow_seconds == 0.0, "Radar approach braking remains ranked")
	game.enforcement.radar_pending = false
	game.enforcement.current_limit = 30
	game.enforcement.sector_end = game.distance + 100.0
	game._update_ranked_pace(60.0)
	_check(game.progress.ranked_eligible, "Legal low-limit sector remains ranked")
	game.enforcement.current_limit = 0
	game._update_ranked_pace(10.0)
	game.speed = 40.0
	game._update_ranked_pace(5.0)
	_check(game.progress.slow_seconds == 0.0, "Five seconds of normal pace restores grace")
	game.player.lateral_velocity = 4.0
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(game.state == game.GameState.PAUSED and game.player.lateral_velocity == 0.0, "Desktop focus loss pauses and clears steering momentum")
	var clock: float = game.run_seconds
	game._physics_process(60.0)
	_check(game.run_seconds == clock, "Focus pause freezes gameplay")
	game.resume_game()
	game.enforcement.sector_at = INF
	game.enforcement.sector_end = INF
	game.enforcement.radar_at = INF
	game.obstacles.spawning_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.speed = 10000.0
	game._physics_process(0.01)
	_check(game.speed <= game.Tuning.MAX_PHYSICAL_SPEED, "Actual movement clamps to supported preview budget")
	game.progress.bonus_points = 1000
	game._settle_round()
	game._settle_round()
	_check(probe.writes == 4, "Quit settlement path saves once")
	game.return_to_menu()
	game.audio.stop_all()
	await create_timer(0.2).timeout
	game.free()
	await process_frame
	print("ROUND INTEGRITY PASS" if failures == 0 else "ROUND INTEGRITY FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
