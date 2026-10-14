extends SceneTree

const LIMITS: Array[int] = [30, 50, 70, 80, 90, 120, 130, 200, 0]
var failures: int = 0
var maximum_pool: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var spawner = load("res://scripts/obstacle_spawner.gd").new()
	root.add_child(spawner)
	if not spawner.has_method("set_speed_limit"):
		_check(false, "ordinary traffic supports sector speed limits")
		spawner.queue_free()
		await process_frame
		quit(1)
		return
	_test_sector_speeds(spawner)
	_test_smooth_change_and_rival(spawner)
	_test_wave_drain(spawner)
	_test_seeded_cycles(spawner)
	spawner.queue_free()
	await process_frame
	await process_frame
	print("SECTOR TRAFFIC PASS: nine sector speeds, smooth ordinary traffic, stationary hazards, independent rival, seeded wave safety and bounded pool %d" % maximum_pool if failures == 0 else "SECTOR TRAFFIC FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _test_sector_speeds(spawner) -> void:
	for limit in LIMITS:
		spawner.reset_spawner(42)
		_clear(spawner)
		var expected: float = float(limit) / 3.6 if limit > 0 else RoadObstacle.TRAFFIC_SPEED
		spawner.set_speed_limit(limit)
		for tick in range(360):
			spawner.advance(0.0, 0.0, 0.0, 1.0 / 60.0, 20.0)
		_check(is_equal_approx(spawner.traffic_speed, expected), "traffic reaches %d km/h sector speed" % limit)
		spawner._activate_encounter(1, -150.0, 20.0, -1)
		var traffic: RoadObstacle = spawner.obstacle_pool[0]
		_check(is_equal_approx(traffic.cruise_speed, expected), "fresh traffic inherits current sector speed")
		spawner._activate_encounter(0, -250.0, 20.0, RoadObstacle.Kind.POTHOLE)
		var hazard: RoadObstacle = spawner.obstacle_pool[1]
		spawner.advance(0.8, 0.8, 0.0, 0.1, 20.0)
		_check(is_equal_approx(traffic.position.z, -150.0 + (8.0 - expected) * 0.1), "sector traffic uses signed relative movement")
		_check(hazard.cruise_speed == 0.0 and is_equal_approx(hazard.position.z, -249.2), "static hazards remain fixed to the road")
	spawner.reset_spawner(42)
	_check(spawner.traffic_speed == RoadObstacle.TRAFFIC_SPEED, "restart restores unlimited-road traffic speed")
	for actor in spawner.obstacle_pool:
		if actor.active:
			_check(actor.cruise_speed == RoadObstacle.TRAFFIC_SPEED, "initial reset rows inherit default traffic speed")


func _test_smooth_change_and_rival(spawner) -> void:
	_clear(spawner)
	var traffic: RoadObstacle = spawner._take_obstacle()
	traffic.activate(Vector3(0, 0, -100), RoadObstacle.Kind.CAR, 20.0)
	spawner._next_row_z = -400.0
	spawner.set_speed_limit(200)
	spawner.advance(40.0, 40.0, 0.0, 0.5, 20.0)
	_check(spawner.traffic_speed > 14.0 and spawner.traffic_speed <= 18.00001, "sector change accelerates traffic smoothly")
	_check(is_equal_approx(traffic.cruise_speed, spawner.traffic_speed), "existing ordinary traffic adopts smooth sector speed")
	_check(is_equal_approx(spawner._next_row_z, -400.0 + 40.0 - spawner.traffic_speed * 0.5), "row schedule follows sector-relative travel")
	var rival: RoadObstacle = spawner._take_obstacle()
	rival.activate(Vector3(-5, 0, -120), RoadObstacle.Kind.WIDE, 20.0)
	rival.racing = true
	rival.cruise_speed = 47.0
	spawner.begin_race(rival)
	spawner.set_speed_limit(30)
	spawner.advance(2.0, 42.0, 0.0, 0.25, 20.0)
	_check(spawner.traffic_speed < 18.0 and spawner.traffic_speed >= 16.0, "lower sector limit decelerates traffic smoothly")
	_check(rival.cruise_speed == 47.0 and is_equal_approx(rival.position.z, -129.75), "racing Apex retains its own cruise speed and signed motion")
	spawner.motion_enabled = false
	var stopped_speed: float = spawner.traffic_speed
	spawner.set_speed_limit(200)
	spawner.advance(80.0, 122.0, 0.0, 1.0, 20.0)
	_check(spawner.traffic_speed == stopped_speed, "frozen motion cannot advance traffic acceleration")
	spawner.reset_spawner(42)


func _test_wave_drain(spawner) -> void:
	_clear(spawner)
	spawner.spawning_enabled = true
	var traffic: RoadObstacle = spawner._take_obstacle()
	traffic.activate(Vector3(0, 0, -40), RoadObstacle.Kind.CAR, 20.0)
	var serial: int = traffic._activation_serial
	spawner._wave = spawner.Wave.WAIT_FOR_STATIC
	spawner.set_speed_limit(200)
	for tick in range(1800):
		spawner.advance(8.0 / 60.0, float(tick) * 8.0 / 60.0, 1.0, 1.0 / 60.0, 20.0)
		if traffic.active and traffic._activation_serial == serial:
			_check(spawner._wave == spawner.Wave.WAIT_FOR_STATIC, "fast traffic must clear before static wave starts")
		else:
			break
	_check(spawner._wave == spawner.Wave.STATIC, "retreating high-speed traffic eventually releases the static wave")


func _test_seeded_cycles(spawner) -> void:
	var seen_static := false
	var seen_traffic := false
	for seed_value in [42, 312, 8675309]:
		spawner.spawning_enabled = true
		spawner.reset_spawner(seed_value)
		var distance: float = 0.0
		for tick in range(18000):
			spawner.set_speed_limit(LIMITS[(tick / 600) % LIMITS.size()])
			var player_speed: float = [8.0, 80.0, 22.222222, 55.555556, 100.0][(tick / 300) % 5]
			distance += player_speed / 60.0
			spawner.advance(player_speed / 60.0, distance, 1.0, 1.0 / 60.0, 20.0)
			maximum_pool = maxi(maximum_pool, spawner.obstacle_pool.size())
			if tick % 30 != 0:
				continue
			_check(spawner.obstacle_pool.size() <= spawner.MAX_POOL_SIZE, "sector speed cycles keep the traffic pool bounded")
			_check(spawner.get_child_count() == spawner.obstacle_pool.size(), "sector speed cycles leave no abandoned actors")
			var rows: Array[Dictionary] = spawner.upcoming_rows()
			var reachable: Array[int] = [0, 1, 2]
			for index in range(rows.size()):
				var row: Dictionary = rows[index]
				seen_static = seen_static or row.cruise_speed == 0.0
				seen_traffic = seen_traffic or row.cruise_speed > 0.0
				_check(row.lanes.size() <= 2, "sector encounters never close every lane")
				var next_reachable: Array[int] = []
				for lane in range(3):
					if row.lanes.has(lane):
						continue
					for previous_lane in reachable:
						if absi(lane - previous_lane) <= 1:
							next_reachable.append(lane)
							break
				_check(not next_reachable.is_empty(), "sector rows retain an adjacent escape route")
				reachable = next_reachable
				if index > 0:
					var front: Dictionary = rows[index - 1]
					_check(front.z - row.z >= 63.99, "mixed sector speeds preserve spatial encounter separation")
					for probe_speed in [8.0, 22.222222, 55.555556, 80.0, 100.0]:
						var front_closing: float = probe_speed - float(front.cruise_speed)
						var back_closing: float = probe_speed - float(row.cruise_speed)
						if front_closing <= 0.0 or back_closing <= 0.0:
							continue
						var front_clears: float = (-float(front.z) + float(front.half_length) + RoadObstacle.PLAYER_HALF_LENGTH) / front_closing
						var back_enters: float = (-float(row.z) - float(row.half_length) - RoadObstacle.PLAYER_HALF_LENGTH) / back_closing
						_check(back_enters - front_clears >= 0.7, "mixed sector catch times leave room to steer through actual footprints")
	_check(seen_static and seen_traffic, "mixed-speed seeded drives include traffic and stationary hazards")


func _clear(spawner) -> void:
	spawner.spawning_enabled = false
	for actor in spawner.obstacle_pool:
		actor.deactivate()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures <= 12:
			push_error(message)
