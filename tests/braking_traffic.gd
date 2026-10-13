extends SceneTree

const Models = preload("res://scripts/traffic_models.gd")

var failures: int = 0
var hits: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(42)
	spawner.spawning_enabled = false
	for actor in spawner.obstacle_pool:
		actor.deactivate()
	var traffic := spawner._take_obstacle()
	traffic.activate(Vector3(0, 0, -100), RoadObstacle.Kind.CAR, 20.0)
	spawner.advance(8.0, 8.0, 0.0, 1.0, 20.0)
	_check(is_equal_approx(traffic.position.z, -106.0), "cars move away when brake speed falls below traffic speed")
	for tick in range(60):
		spawner.advance(8.0, float(tick * 8), 0.0, 1.0, 20.0)
	_check(not traffic.active, "retreating traffic retires beyond visibility horizon")
	spawner.reset_spawner(42)
	spawner.spawning_enabled = true
	for actor in spawner.obstacle_pool:
		actor.deactivate()
	traffic = spawner._take_obstacle()
	traffic.activate(Vector3(0, 0, -40), RoadObstacle.Kind.CAR, 20.0)
	spawner._wave = spawner.Wave.WAIT_FOR_STATIC
	spawner.advance(16.0, 16.0, 0.0, 1.0, 20.0)
	_check(spawner._wave == spawner.Wave.WAIT_FOR_STATIC, "braking cannot introduce a static row before traffic clears")
	traffic.deactivate()
	spawner.advance(16.0, 32.0, 0.0, 1.0, 20.0)
	_check(spawner._wave == spawner.Wave.STATIC, "static wave resumes after traffic clears")
	var actor := RoadObstacle.new()
	root.add_child(actor)
	actor.player_hit.connect(func(): hits += 1)
	actor.activate(Vector3(0, 0, 5.5), RoadObstacle.Kind.CAR, 5.0)
	actor.advance_pass(1.0, 5.0)
	await process_frame
	actor.advance_pass(-12.0, 0.0)
	_check(hits == 1 and actor.pass_collided, "a passed car returning during braking still has swept collision")
	# Preserve the audited seed-2468 overlap intervals around the current edges.
	var width_delta := RoadObstacle.PLAYER_HALF_WIDTH + Models.dimensions(Models.Model.APEX).x * 0.5 - 2.95
	var length_delta := RoadObstacle.PLAYER_HALF_LENGTH + Models.dimensions(Models.Model.APEX).z * 0.5 - 5.4
	actor.activate(Vector3(-1.8, 0, 5.309787 + length_delta), RoadObstacle.Kind.WIDE, -4.939445 - width_delta, Models.Model.APEX)
	actor.racing = true
	actor.position.x = -2.0
	_check(not actor.advance_pass(0.613333, -4.922222 - width_delta) and hits == 1, "moving rival sweeps cannot collide when lateral and longitudinal overlap times are disjoint")
	var previous_hits: int = hits
	actor.activate(Vector3(-1.8, 0, 4.7 + length_delta), RoadObstacle.Kind.WIDE, -4.939445 - width_delta, Models.Model.APEX)
	actor.racing = true
	actor.position.x = -2.0
	_check(actor.advance_pass(0.613333, -4.922222 - width_delta) and hits == previous_hits + 1 and actor.pass_collided, "moving rival still collides when its two sweep intervals overlap")
	for tick in range(12000):
		var speed: float = [8.0, 16.0, 22.222222, 80.0][(tick / 600) % 4]
		spawner.advance(speed / 60.0, 1000.0 + tick, 0.6, 1.0 / 60.0, 20.0)
		_check(spawner.obstacle_pool.size() <= spawner.MAX_POOL_SIZE, "braking generation stays within pool size")
	actor.queue_free()
	spawner.queue_free()
	await process_frame
	await process_frame
	print("BRAKING TRAFFIC PASS" if failures == 0 else "BRAKING TRAFFIC FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
