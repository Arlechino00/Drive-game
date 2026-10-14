extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(3)
	for actor in spawner.obstacle_pool:
		actor.deactivate()
	spawner.spawning_enabled = false
	spawner._mixed_wave = true
	spawner._reserved_lane = 0
	spawner.configure_progression(400.0 / 3.6, 1800.0)
	var front := spawner._take_obstacle()
	front.activate(Vector3(0, 0, -180), RoadObstacle.Kind.CAR, 20.0)
	front.cruise_speed = 10.0
	front.speed_factor = 0.5
	var beside := spawner._take_obstacle()
	beside.activate(Vector3(5, 0, -168), RoadObstacle.Kind.VAN, 20.0)
	beside.cruise_speed = 10.0
	beside.speed_factor = 0.5
	var following := spawner._take_obstacle()
	following.activate(Vector3(0, 0, -160), RoadObstacle.Kind.CAR, 20.0)
	following.cruise_speed = 30.0
	following.speed_factor = 2.0
	for tick in range(180):
		spawner.advance(400.0 / 3.6 * 0.1, float(tick) * 400.0 / 3.6 * 0.1, 1.0, 0.1, 20.0)
		for a in spawner.obstacle_pool:
			for b in spawner.obstacle_pool:
				if not a.active or not b.active or a == b:
					continue
				_check(absf(a.position.x - b.position.x) >= a.half_width + b.half_width or absf(a.position.z - b.position.z) >= a.half_length + b.half_length, "mixed-speed traffic never phases through occupied front/adjacent car")
	spawner.free()
	# Natural mixed-wave catch with a high posted speed, including the player's
	# reaction zone where lane-change planning is deliberately disabled.
	spawner = ObstacleSpawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(11)
	var distance := 0.0
	for tick in range(2400):
		var step := 0.05
		var speed := 400.0 / 3.6
		distance += speed * step
		spawner.configure_progression(speed, 1200.0 + tick * step)
		spawner.set_speed_limit(200)
		spawner.advance(speed * step, distance, 1.0, step, 20.0)
		for a in spawner.obstacle_pool:
			for b in spawner.obstacle_pool:
				if not a.active or not b.active or a == b:
					continue
				_check(absf(a.position.x - b.position.x) >= a.half_width + b.half_width or absf(a.position.z - b.position.z) >= a.half_length + b.half_length - 0.00001, "natural mixed-speed traffic preserves physical footprints near player")
	spawner.free()
	print("STAGE TWO TRAFFIC PASS" if failures == 0 else "STAGE TWO TRAFFIC FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 3:
			push_error(label)
