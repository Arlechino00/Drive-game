extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await _high_speed_chases()
	var pursuit = load("res://scripts/police_pursuit.gd").new()
	root.add_child(pursuit)
	await process_frame
	var catches := [0]
	var escapes := [0]
	pursuit.caught.connect(func(): catches[0] += 1)
	pursuit.escaped.connect(func(): escapes[0] += 1)
	pursuit.begin(Vector3.ZERO, 8.0)
	pursuit.gap_m = 4.0
	pursuit.advance(0.05, Vector3.ZERO, 0.0, 45.0)
	_check(pursuit.active and catches[0] == 0, "brief police contact cannot arrest instantly")
	# A nominal radar chase duration alone cannot release a surrounded driver.
	if not pursuit.has_method("set_heat"):
		_check(false, "heat-based pursuit roles exist")
		pursuit.free()
		quit(1)
		return
	pursuit.reset_pursuit()
	pursuit.set_heat(0)
	pursuit.begin(Vector3.ZERO)
	pursuit.gap_m = 4.0
	pursuit.units[0].speed = 0.0
	pursuit.advance(2.0, Vector3.ZERO, 0.0, 45.0)
	_check(pursuit.capture_fraction > 0.2 and pursuit.capture_fraction < 0.7 and pursuit.active, "sustained strong position builds capture over seconds")
	var captured: float = pursuit.capture_fraction
	pursuit.units[0].x = 5.0
	pursuit.gap_m = 30.0
	pursuit.advance(0.5, Vector3.ZERO, 45.0, 45.0)
	_check(pursuit.capture_fraction > 0.0 and pursuit.capture_fraction < captured, "breaking strong positioning decays capture gradually")
	pursuit.reset_pursuit()
	pursuit.begin(Vector3.ZERO)
	pursuit.gap_m = 4.0
	pursuit.units[0].speed = 0.0
	pursuit.advance(4.0, Vector3.ZERO, 0.0, 45.0)
	_check(pursuit.active and catches[0] == 0, "four seconds of positioning still gives an escape opportunity")
	pursuit.advance(2.0, Vector3.ZERO, 0.0, 45.0)
	_check(not pursuit.active and catches[0] == 1, "five seconds of sustained positioning catches once")
	pursuit.advance(5.0, Vector3.ZERO, 0.0, 45.0)
	_check(catches[0] == 1, "finished arrest cannot repeat")
	pursuit.set_heat(1)
	pursuit.begin(Vector3.ZERO, 8.0)
	pursuit.advance(10.0, Vector3.ZERO, 45.0, 45.0)
	await process_frame
	_check(pursuit.active and escapes[0] == 0, "clean approach time cannot trigger timer escape")
	var original_gap: float = pursuit.gap_m
	var original_speed: float = pursuit.units[0].speed
	pursuit.register_mistake()
	pursuit.register_close_call()
	_check(pursuit.active and pursuit.gap_m == original_gap and pursuit.units[0].speed == original_speed, "contacts never teleport or arrest police")
	# Slow traffic forces a real braking lane change, rather than passing through it.
	pursuit.set_heat(0)
	pursuit.begin(Vector3.ZERO)
	var actor := RoadObstacle.new()
	root.add_child(actor)
	actor.activate(Vector3(0.0, 0.0, 35.0), RoadObstacle.Kind.CAR)
	var traffic: Array[RoadObstacle] = [actor]
	pursuit.advance(0.5, Vector3.ZERO, 45.0, 45.0, 1.0, traffic)
	_check(pursuit.units[0].state == "overtake" and absf(pursuit.units[0].x) > 0.5, "police selects unblocked overtaking lane")
	_check(pursuit.units[0].speed < 45.0, "traffic forces police below the driver's speed")
	actor.activate(Vector3(3.0, 0.0, 65.0), RoadObstacle.Kind.CAR)
	pursuit.begin(Vector3(5.0, 0.0, 0.0))
	pursuit.units[0].x = 0.0
	pursuit.units[0].speed = 45.0
	pursuit.advance(0.5, Vector3(5.0, 0.0, 0.0), 45.0, 45.0, 1.0, traffic)
	_check(pursuit.units[0].x < 0.7, "rear-adjacent traffic prevents lateral body overlap")
	for driver_speed in [90.0, 800.0 / 3.6]:
		pursuit.begin(Vector3.ZERO)
		pursuit.units[0].speed = driver_speed
		actor.activate(Vector3(0.0, 0.0, 15.0), RoadObstacle.Kind.CAR)
		actor.cruise_speed = 20.0
		var overlapped := false
		for frame in range(240):
			actor.position.z += (driver_speed - actor.cruise_speed) / 60.0
			pursuit.advance(1.0 / 60.0, Vector3.ZERO, driver_speed, driver_speed, 1.0, traffic)
			var unit: Dictionary = pursuit.units[0]
			if absf(unit.x - actor.position.x) < actor.half_width + 1.2 and absf(unit.z - actor.position.z) < actor.half_length + 2.65 - 0.01:
				overlapped = true
		_check(not overlapped, "overtaking at %.0f km/h never phases through traffic" % (driver_speed * 3.6))
	actor.free()
	# The configured three-unit formation must actually hold both sides and the rear.
	pursuit.set_heat(4)
	pursuit.begin(Vector3.ZERO)
	pursuit.units[0].x = 3.5
	pursuit.units[0].z = -6.0
	pursuit.units[1].x = -3.5
	pursuit.units[1].z = 0.0
	pursuit.units[2].x = 0.0
	pursuit.units[2].z = 7.0
	for unit in pursuit.units:
		unit.speed = 45.0
	pursuit.advance(2.0, Vector3.ZERO, 45.0, 45.0)
	_check(pursuit.active and pursuit.capture_fraction > 0.35 and pursuit.capture_fraction < 0.5, "coordinated sides and rear build sustained boxing capture")
	pursuit.advance(4.0, Vector3.ZERO, 45.0, 45.0)
	_check(not pursuit.active and catches[0] == 2, "holding the actual three-unit box captures after five seconds")
	var escape_target := 0
	for driver_speed in [45.0, 300.0 / 3.6, 800.0 / 3.6]:
		for heat_level in [0, 1, 2, 4]:
			pursuit.set_heat(heat_level)
			pursuit.begin(Vector3.ZERO)
			var roles: Array = []
			for unit in pursuit.units:
				roles.append(unit.role)
			_check(pursuit.units.size() <= 3 and pursuit.units.size() >= 1, "heat never creates more than three units")
			_check(roles.has({0: "patrol", 1: "pursuit", 2: "interceptor", 4: "heavy"}[heat_level]), "heat activates its specialized role")
			for frame in range(65 * 60):
				var player_at := Vector3(sin(float(frame) / 60.0 * 1.8) * 5.0, 0.0, 0.0)
				pursuit.advance(1.0 / 60.0, player_at, driver_speed, driver_speed)
				if not pursuit.active:
					break
				if frame % 60 == 0:
					await process_frame
			escape_target += 1
			_check(not pursuit.active and escapes[0] == escape_target, "sustained steering physically escapes without boost at %.0f km/h and heat %d" % [driver_speed * 3.6, heat_level])
	# Radar or a deferred contact invalidates the same frame's provisional escape.
	pursuit.set_heat(0)
	pursuit.begin(Vector3.ZERO)
	pursuit.gap_m = 110.0
	pursuit.disengagement_seconds = 4.99
	pursuit.report_radar.call_deferred()
	pursuit.advance(0.02, Vector3.ZERO, 45.0, 45.0)
	await process_frame
	_check(pursuit.active and pursuit.disengagement_seconds == 0.0, "radar resets deferred disengagement")
	pursuit.disengagement_seconds = 4.99
	pursuit.advance(0.02, Vector3.ZERO, 45.0, 45.0)
	pursuit.reset_pursuit()
	pursuit.begin(Vector3.ZERO)
	await process_frame
	_check(pursuit.active and pursuit.disengagement_seconds == 0.0, "stale callback cannot finish restarted pursuit")
	pursuit.set_heat(6)
	var original_z: float = pursuit.units[0].z
	pursuit.report_radar()
	_check(pursuit.units.size() == 3 and pursuit.units[0].z == original_z, "radar adds bounded rear reinforcements without warping active units")
	var count := _count(pursuit)
	for cycle in range(100):
		pursuit.set_heat(cycle % 4)
		pursuit.begin(Vector3.ZERO)
		pursuit.advance(0.1, Vector3.ZERO, 45.0, 45.0)
		pursuit.reset_pursuit()
	_check(_count(pursuit) == count and count < 500, "heat changes and restarts reuse bounded visuals")
	pursuit.free()
	print("STAGE TWO POLICE PASS" if failures == 0 else "STAGE TWO POLICE FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _high_speed_chases() -> void:
	var pursuit = load("res://scripts/police_pursuit.gd").new()
	root.add_child(pursuit)
	await process_frame
	for kmh in [130.0, 300.0, 400.0, 800.0]:
		var speed: float = kmh / 3.6
		for heat_level in [0, 1, 2, 4, 6]:
			pursuit.set_heat(heat_level)
			pursuit.begin(Vector3.ZERO)
			var start_gap: float = pursuit.units[0].z
			var physical_motion := true
			var finite_acceleration := true
			for frame in range(8 * 60):
				var previous_z: float = pursuit.units[0].z
				var previous_speed: float = pursuit.units[0].speed
				pursuit.advance(1.0 / 60.0, Vector3.ZERO, speed, 30.0 / 3.6)
				physical_motion = physical_motion and absf(pursuit.units[0].z - previous_z - (speed - pursuit.units[0].speed) / 60.0) < 0.0001
				if previous_speed >= 0.0:
					finite_acceleration = finite_acceleration and absf(pursuit.units[0].speed - previous_speed) <= pursuit.braking / 60.0 + 0.0001
			_check(physical_motion and finite_acceleration, "high-speed police has finite acceleration and physical relative motion")
			_check(pursuit.active and pursuit.units[0].speed > speed and pursuit.units[0].z < start_gap - 8.0, "heat %d police catches up to %.0f km/h actual speed despite a 30 km/h reference" % [heat_level, kmh])
	# Boost and the growing cruise curve are actual world speeds, not a ceiling.
	pursuit.set_heat(0)
	pursuit.begin(Vector3.ZERO)
	var base := 300.0 / 3.6
	var boosted := base + 38.0
	pursuit.advance(4.0, Vector3.ZERO, boosted, base)
	_check(pursuit.units[0].speed > boosted and pursuit.units[0].z < pursuit.initial_gap - 8.0, "police catches a boosted driver using actual speed")
	var previous_speed: float = pursuit.units[0].speed
	pursuit.advance(1.0 / 60.0, Vector3.ZERO, boosted + 38.0, base)
	_check(pursuit.units[0].speed > previous_speed and pursuit.units[0].speed - previous_speed <= pursuit.acceleration / 60.0 + 0.0001, "a sudden extra boost changes police acceleration without instant velocity matching")
	pursuit.begin(Vector3.ZERO)
	pursuit.advance(4.0, Vector3.ZERO, base, base)
	var boost_speed := base
	var faster_through_boost := true
	for frame in range(3 * 60):
		boost_speed = move_toward(boost_speed, boosted, 16.0 / 60.0)
		pursuit.advance(1.0 / 60.0, Vector3.ZERO, boost_speed, base)
		faster_through_boost = faster_through_boost and pursuit.units[0].speed > boost_speed
	_check(faster_through_boost, "clear-road police remains faster through the real 16 m/s squared boost acceleration")
	pursuit.set_heat(6)
	pursuit.begin(Vector3.ZERO)
	for frame in range(12 * 60):
		var rising := 800.0 / 3.6 + float(frame) / 60.0
		pursuit.advance(1.0 / 60.0, Vector3.ZERO, rising, 300.0 / 3.6)
	_check(pursuit.units.size() == 3 and pursuit.units[0].z < pursuit.initial_gap - 20.0, "bounded high-heat police keeps closing as actual speed grows above 800 km/h")
	var catches := [0]
	var escapes := [0]
	pursuit.caught.connect(func(): catches[0] += 1)
	pursuit.escaped.connect(func(): escapes[0] += 1)
	var expected_catches := 0
	for kmh in [130.0, 300.0, 400.0, 800.0]:
		for heat_level in [0, 1, 2, 4, 6]:
			pursuit.set_heat(heat_level)
			pursuit.begin(Vector3.ZERO)
			for frame in range(50 * 60):
				pursuit.advance(1.0 / 60.0, Vector3.ZERO, kmh / 3.6, 30.0 / 3.6)
				if not pursuit.active:
					break
				if frame % 60 == 0:
					await process_frame
			expected_catches += 1
			_check(catches[0] == expected_catches and escapes[0] == 0, "doing nothing at %.0f km/h allows heat %d police to approach and sustain an arrest" % [kmh, heat_level])
	# Slow cars behind the driver can physically obstruct the pursuing formation.
	var traffic: Array[RoadObstacle] = []
	for lane in [-5.0, 0.0, 5.0]:
		var actor := RoadObstacle.new()
		root.add_child(actor)
		actor.activate(Vector3(lane, 0.0, 35.0), RoadObstacle.Kind.CAR)
		actor.cruise_speed = 20.0
		traffic.append(actor)
	pursuit.set_heat(6)
	pursuit.begin(Vector3.ZERO)
	for frame in range(15 * 60):
		for actor in traffic:
			actor.position.z += (300.0 / 3.6 - actor.cruise_speed) / 60.0
		pursuit.advance(1.0 / 60.0, Vector3.ZERO, 300.0 / 3.6, 30.0 / 3.6, 1.0, traffic)
		if frame % 30 == 0:
			await process_frame
		if not pursuit.active:
			break
	_check(escapes[0] == 1 and pursuit.gap_m >= pursuit.escape_gap, "traffic behind the driver permits a real high-heat escape at 300 km/h")
	for actor in traffic:
		actor.free()
	pursuit.free()

func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
