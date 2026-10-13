extends SceneTree
## A clean swept pass must resolve before its pool slot retires on a long step.

var failures: int = 0
var rewards: int = 0
var hits: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	spawner.spawning_enabled = false
	spawner.near_miss.connect(func(_points: int, _clearance: float): rewards += 1)
	spawner.player_hit.connect(func(): hits += 1)
	var actor := spawner._take_obstacle()
	actor.activate(Vector3(0, 0, 5.1), RoadObstacle.Kind.CAR, 2.9)
	spawner.advance(10.0, 10.0, 0.0, 0.1, 2.9)
	_check(not actor.pass_collided and actor.minimum_clearance > 0.0, "long step remains a clean swept pass")
	_check(spawner._take_obstacle() != actor, "queued pass cannot be reused before resolution")
	await process_frame
	_check(rewards == 1 and actor.pass_awarded, "long-step pass awards once")
	spawner.advance(ObstacleSpawner.REAR_RETIRE_DISTANCE, 10.0, 0.0, 0.1, 2.9)
	await process_frame
	_check(rewards == 1 and not actor.active, "passed actor retires beyond police range without a second award")
	await process_frame
	_check(rewards == 1, "retired pass cannot award twice")

	actor.activate(Vector3(0, 0, -1), RoadObstacle.Kind.CAR, 0.0)
	spawner.advance(20.0, 30.0, 0.0, 0.2, 0.0)
	await process_frame
	_check(hits == 1 and rewards == 1 and actor.pass_collided, "long swept collision grants no close-pass reward")

	actor.activate(Vector3(0, 0, 5.1), RoadObstacle.Kind.CAR, 2.9)
	spawner.advance(10.0, 40.0, 0.0, 0.1, 2.9)
	# A queued Area3D result can still cancel an apparent clean swept pass.
	actor._resolve_player_contact()
	await process_frame
	_check(hits == 2 and rewards == 1, "contact before queued resolution cancels the reward")

	actor.activate(Vector3(0, 0, 5.1), RoadObstacle.Kind.CAR, 2.9)
	spawner.advance(10.0, 50.0, 0.0, 0.1, 2.9)
	# Menu/game-end cleanup deactivates encounters before deferred work runs.
	actor.deactivate()
	await process_frame
	_check(rewards == 1 and not actor.active, "deactivation cancels a pending pass")

	actor.activate(Vector3(0, 0, 5.1), RoadObstacle.Kind.CAR, 2.9)
	spawner.advance(10.0, 60.0, 0.0, 0.1, 2.9)
	spawner.reset_spawner(42)
	actor.activate(Vector3(5, 0, -100), RoadObstacle.Kind.CAR, 0.0)
	var serial := actor._activation_serial
	await process_frame
	_check(rewards == 1 and actor.active and actor._activation_serial == serial and actor.position == Vector3(5, 0, -100), "reset/reuse rejects old reward and retirement callbacks")
	actor.activate(Vector3(0, 0, 5.1), RoadObstacle.Kind.CAR, 2.9)
	spawner.near_miss.connect(func(_points: int, _clearance: float): actor.activate(Vector3(5, 0, -80), RoadObstacle.Kind.CAR, 2.9), CONNECT_ONE_SHOT)
	spawner.advance(10.0, 70.0, 0.0, 0.1, 2.9)
	await process_frame
	_check(rewards == 2 and actor.active and actor.position == Vector3(5, 0, -80) and not actor.pass_awarded, "reward callback reuse survives the old deferred retirement")
	spawner.free()
	await process_frame
	await _test_game_cleanup()
	print("LARGE STEPS PASS: clean pass, deferred retirement, collision cancellation, cleanup and reset/reuse" if failures == 0 else "LARGE STEPS FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _test_game_cleanup() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.start_game()
	_queue_game_pass(game)
	game.return_to_menu()
	await process_frame
	_check(game.progress.near_misses == 0 and game.get_score() == 0, "returning to menu cancels the old pass")
	game.start_game()
	_queue_game_pass(game)
	game.start_game()
	await process_frame
	_check(game.progress.near_misses == 0 and game.get_score() == 0 and game.obstacles.get_active_count() > 0, "restart preserves new rows and rejects the old pass")
	_queue_game_pass(game)
	game._finish_run("Long-step cleanup fixture")
	var finished_score: int = game.get_score()
	await process_frame
	_check(game.progress.near_misses == 0 and game.get_score() == finished_score, "finished run cannot receive a pending pass reward")
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame


func _queue_game_pass(game) -> void:
	game.obstacles.spawning_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.player.position.x = 2.9
	var actor: RoadObstacle = game.obstacles._take_obstacle()
	actor.activate(Vector3(0, 0, 5.1), RoadObstacle.Kind.CAR, 2.9)
	game.obstacles.advance(10.0, 10.0, 0.0, 0.1, 2.9)
	# Restart must be allowed to generate its ordinary starting rows.
	game.obstacles.spawning_enabled = true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
