extends SceneTree

const Heat = preload("res://scripts/heat_controller.gd")
var failures := 0
var maximum_pool := 0
var saw_mixed := false
var saw_overtake := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var director := DifficultyDirector.new()
	var road := RoadManager.new()
	root.add_child(road)
	var initial_nodes := road.get_child_count()
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	var heat := Heat.new()
	for i in range(4):
		heat.radar_violation(330.0, 80)
	_check(heat.level() >= 4, "radar chain reaches strong unit heat")
	_check(heat.risk_multiplier(310.0 / 3.6, true, 0.6, true) > heat.risk_multiplier(170.0 / 3.6, false, 0.0, false) + 1.0, "high speed and pressure reward skill")
	for minutes in [5.0, 10.0, 20.0, 30.0, 60.0]:
		var seconds: float = minutes * 60.0
		var speed: float = director.get_base_speed(seconds * 50.0, seconds)
		var braking_speed: float = director.get_base_speed(0.0, seconds)
		_check(braking_speed >= speed * 0.96, "braking cannot stop survival progression")
		print("BALANCE %.0fmin %.1fkm/h density %.2f tier %d" % [minutes, speed * 3.6, director.get_density(seconds * 50.0, seconds), director.get_tier(seconds)])
	for kmh in [250.0, 300.0, 350.0, 400.0]:
		var speed: float = kmh / 3.6
		spawner.reset_spawner(roundi(kmh))
		var distance := 0.0
		for tick in range(18000):
			var seconds: float = float(tick) * 0.1
			distance += speed * 0.1
			spawner.configure_progression(speed, seconds)
			spawner.set_speed_limit(0)
			spawner.advance(speed * 0.1, distance, director.get_density(distance, seconds), 0.1, 20.0)
			road.advance(speed * 0.1)
			maximum_pool = maxi(maximum_pool, spawner.obstacle_pool.size())
			if tick % 100 == 0:
				_check(spawner.obstacle_pool.size() <= spawner.MAX_POOL_SIZE, "bounded 30-minute traffic pool")
				_check(road.get_child_count() == initial_nodes, "bounded 30-minute road nodes")
				_check(spawner.spawn_ahead >= speed * 3.5, "dynamic look-ahead at %.0fkm/h" % kmh)
				var positions: Array[float] = []
				for segment in road.segments:
					positions.append(segment.position.z)
				positions.sort()
				_check(positions[0] < -spawner.spawn_ahead - 40.0, "road exists under visible distant actors")
				for index in range(1, positions.size()):
					_check(absf(positions[index] - positions[index - 1] - road.SEGMENT_LENGTH) < 0.001, "no high-speed road gaps")
			if spawner._mixed_wave:
				saw_mixed = true
				for actor in spawner.obstacle_pool:
					if actor.active:
						_check(absf(actor.position.x - spawner.LANE_CENTERS[spawner._reserved_lane]) >= actor.half_width + actor.PLAYER_HALF_WIDTH, "mixed traffic leaves physically open corridor")
						saw_overtake = saw_overtake or actor.changing_lane
	spawner.reset_spawner(7)
	for actor in spawner.obstacle_pool:
		actor.deactivate()
	spawner.spawning_enabled = false
	spawner._mixed_wave = true
	spawner._reserved_lane = 0
	spawner.configure_progression(100.0, 1200.0)
	var front := spawner._take_obstacle()
	front.activate(Vector3(0, 0, -160), RoadObstacle.Kind.CAR, 20.0)
	front.speed_factor = 0.85
	front.cruise_speed = 14.0
	var following := spawner._take_obstacle()
	following.activate(Vector3(0, 0, -110), RoadObstacle.Kind.CAR, 20.0)
	following.speed_factor = 1.3
	following.cruise_speed = 20.0
	spawner._update_traffic_ai(0.25, 20.0)
	_check(following.lane_target == 5.0, "faster traffic actively plans an overtake")
	_check(saw_mixed, "late-run traffic complexity exists")
	print("STAGE TWO WORLD PASS: four 30-minute simulations, 250/300/350/400 km/h, pool %d, mixed %s, natural overtake %s" % [maximum_pool, saw_mixed, saw_overtake] if failures == 0 else "STAGE TWO WORLD FAIL: %d" % failures)
	spawner.free()
	road.free()
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 12:
			push_error(label)
