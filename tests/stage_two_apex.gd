extends SceneTree

const Race = preload("res://scripts/apex_race.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_blocking()
	_test_blocked_paths()
	_test_high_speed()
	_test_high_speed_traffic()
	_test_difficulty_and_memory()
	_test_boost_escape()
	_test_merging_traffic()
	_test_density_horizon()
	_test_new_progression_races()
	_test_boosted_chase_capacity()
	_test_race_wave_drain()
	_test_finish_frame_cutoff()
	if failures == 0:
		print("STAGE TWO APEX PASS: safe anti-block passing, blocked-path release, 250/300/350/400 km/h, bounded acceleration and recovery, rising 0-120min no-input overtakes, actual boosted 300km/h chase burst and sustained boost escape")
	quit(1 if failures else 0)


func _test_new_progression_races() -> void:
	var director := DifficultyDirector.new()
	for run_start in [0.0, 300.0, 600.0, 1200.0, 3600.0, 7200.0]:
		var distance: float = run_start * 80.0
		var speed := director.get_base_speed(distance, run_start)
		var actor := _actor(Vector3(-5, 0, -13), 14.0)
		var traffic: Array[RoadObstacle] = [actor]
		var race := Race.new()
		race.begin(actor, speed)
		var result := 0
		var overtook := false
		var fell_behind := false
		for frame in range(1980):
			var elapsed := (frame + 1) / 60.0
			var base := director.get_base_speed(distance, run_start + elapsed)
			speed = move_toward(speed, base, 12.0 / 60.0)
			var before := actor.cruise_speed
			race.prepare_opponent(1.0 / 60.0, base, 0.0, traffic, speed)
			_check(actor.cruise_speed - before <= race.get_acceleration(base) / 60.0 + 0.00001, "new-speed catch-up has finite throttle")
			_check(not actor.advance_pass((speed - actor.cruise_speed) / 60.0, 0.0), "idle-player overtake preserves clearance")
			distance += speed / 60.0
			fell_behind = fell_behind or actor.position.z > 0.0
			overtook = overtook or (actor.position.z < -actor.half_length - actor.PLAYER_HALF_LENGTH and (fell_behind or run_start == 0.0))
			result = race.advance(1.0 / 60.0, false)
		_check(overtook and result == -1 and actor.position.z < 0.0, "no-input player is physically overtaken on rising curve at %.0fs (gap %.1fm)" % [run_start, actor.position.z])
		print("APEX NO-INPUT %.0fmin: player %.0fkm/h, actual rival lead %.1fm" % [run_start / 60.0, speed * 3.6, -actor.position.z])
		race.reset()
		actor.free()


func _test_boosted_chase_capacity() -> void:
	# A 30-zone does not cap the rival: actual 300 km/h exceeds this base pace.
	var actual := 300.0 / 3.6
	var actor := _actor(Vector3(5, 0, 120), actual - 10.0)
	var traffic: Array[RoadObstacle] = [actor]
	var race := Race.new()
	var base := actual - DifficultyDirector.BOOST_SPEED_GAIN
	race.begin(actor, base)
	race.countdown_remaining = 0.0
	race.elapsed = race.BURST_START
	var faster := false
	for frame in range(60):
		race.prepare_opponent(1.0 / 60.0, base, -5.0, traffic, actual)
		actor.advance_pass((actual - actor.cruise_speed) / 60.0, -5.0)
		faster = faster or actor.cruise_speed > actual
		race.advance(1.0 / 60.0, true)
	_check(faster, "Apex chase burst can exceed actual boosted 300 km/h with a lower base speed")
	# Its duty cycle permits a sustained genuine boost escape.
	for frame in range(600):
		race.prepare_opponent(1.0 / 60.0, base, -5.0, traffic, actual)
		actor.advance_pass((actual - actor.cruise_speed) / 60.0, -5.0)
		race.advance(1.0 / 60.0, true)
	_check(actor.position.z > 200.0, "sustained boost earns real separation after finite rival bursts")
	race.reset()
	actor.free()


func _test_race_wave_drain() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	for waiting_wave in [ObstacleSpawner.Wave.WAIT_FOR_STATIC, ObstacleSpawner.Wave.WAIT_FOR_TRAFFIC]:
		spawner.reset_spawner(4)
		for obstacle in spawner.obstacle_pool:
			obstacle.deactivate()
		var actor := spawner._take_obstacle()
		actor.activate(Vector3(5, 0, 50), RoadObstacle.Kind.WIDE, 0.0, 8)
		actor.cruise_speed = 110.0
		actor.racing = true
		spawner.begin_race(actor)
		spawner.configure_progression(100.0, 630.0)
		spawner._wave = waiting_wave
		spawner.advance(0.0, 10000.0, 1.0, 0.0, 0.0)
		_check(spawner._wave != waiting_wave and spawner.get_active_count() > 1 and actor.active, "persistent racing Apex must not freeze drained traffic/static generation")
	spawner.free()


func _test_finish_frame_cutoff() -> void:
	for countdown in [0.0, 0.2]:
		var speed := 300.0 / 3.6
		var actor := _actor(Vector3(-5, 0, 1), speed + Race.PASS_ADVANTAGE)
		var traffic: Array[RoadObstacle] = [actor]
		var race := Race.new()
		race.begin(actor, speed)
		race.elapsed = Race.DURATION - 0.1
		race.countdown_remaining = countdown
		race.boost_seconds = Race.MIN_BOOST_SECONDS
		race.prepare_opponent(0.5, speed, 0.0, traffic, speed)
		actor.advance_pass((speed - actor.cruise_speed) * 0.5, 0.0)
		var expected_lead: float = 1.0 - Race.PASS_ADVANTAGE * (countdown + 0.1)
		var result := race.advance(0.5, false)
		_check(is_equal_approx(race.lead_m, expected_lead), "finish lead is sampled at actual thirty-second cutoff including countdown")
		_check(result == (1 if expected_lead > 0.0 else -1), "an overtake after the finish cannot change the race winner")
		race.reset()
		actor.free()


# Removing player-block detection leaves this same-speed fixture permanently behind.
func _test_blocking() -> void:
	var actor := _actor(Vector3(0, 0, 12), 63.0)
	var race := Race.new()
	race.begin(actor, 62.0)
	race.countdown_remaining = 0.0
	var traffic: Array[RoadObstacle] = [actor]
	var passed := false
	var overtaking := false
	for frame in range(900):
		var before := actor.cruise_speed
		race.prepare_opponent(1.0 / 60.0, 62.0, 0.0, traffic, 63.0)
		overtaking = overtaking or race.ai_state in ["OVERTAKE_LEFT", "OVERTAKE_RIGHT", "AVOID_TRAFFIC"]
		_check(actor.cruise_speed - before <= Race.INITIAL_ACCELERATION / 60.0 + 0.00001, "anti-block throttle has finite acceleration")
		_check(not actor.advance_pass((63.0 - actor.cruise_speed) / 60.0, 0.0), "passing does not ram player")
		if actor.position.z < -6.0:
			passed = true
			break
		if not actor.active:
			break
	_check(passed and absf(actor.position.x) > 3.0, "same-speed blocker is overtaken in a clear adjacent lane")
	_check(overtaking, "state telemetry exposes a committed safe overtake")
	race.reset()
	actor.free()


# A full adjacent-lane traffic squeeze must not cause a blind passing move.
func _test_blocked_paths() -> void:
	var actor := _actor(Vector3(0, 0, 10), 63.0)
	var left := _actor(Vector3(-5, 0, 10), 63.0)
	var right := _actor(Vector3(5, 0, 10), 63.0)
	var traffic: Array[RoadObstacle] = [actor, left, right]
	var race := Race.new()
	race.begin(actor, 62.0)
	race.countdown_remaining = 0.0
	for frame in range(240):
		race.prepare_opponent(1.0 / 60.0, 62.0, 0.0, traffic, 63.0)
		_check(not actor.advance_pass((63.0 - actor.cruise_speed) / 60.0, 0.0), "squeezed rival keeps player clearance")
		_check(absf(actor.position.x) < 1.0, "rival holds when adjacent paths contain traffic")
	_check(actor.position.z > 5.0, "rival follows safely while all passing paths are blocked")
	left.deactivate()
	for frame in range(900):
		race.prepare_opponent(1.0 / 60.0, 62.0, 0.0, traffic, 63.0)
		_check(not actor.advance_pass((63.0 - actor.cruise_speed) / 60.0, 0.0), "released passing path stays player-safe")
		_check(not (absf(actor.position.x - right.position.x) < actor.half_width + right.half_width and absf(actor.position.z - right.position.z) < actor.half_length + right.half_length), "rival does not clip blocked right lane")
		if actor.position.z < -6.0:
			break
	_check(actor.position.z < -6.0 and actor.position.x < -3.0, "rival resumes passing when a lane opens")
	race.reset()
	actor.free()
	left.free()
	right.free()


# Restoring the old 66 m/s cap fails 250+ km/h; instant throttle fails the bound.
func _test_high_speed() -> void:
	for kmh in [250.0, 300.0, 350.0, 400.0]:
		var speed: float = kmh / 3.6
		var actor := _actor(Vector3(5, 0, -18), 14.0)
		var traffic: Array[RoadObstacle] = [actor]
		var race := Race.new()
		race.begin(actor, speed)
		race.countdown_remaining = 0.0
		for frame in range(600):
			var before := actor.cruise_speed
			race.prepare_opponent(1.0 / 60.0, speed, -5.0, traffic, speed)
			_check(is_finite(actor.cruise_speed) and actor.cruise_speed >= 0.0 and actor.cruise_speed - before <= race.get_acceleration(speed) / 60.0 + 0.00001, "%.0f km/h acceleration stays finite" % kmh)
			_check(not actor.advance_pass((speed - actor.cruise_speed) / 60.0, -5.0), "%.0f km/h rival stays collision-safe" % kmh)
		_check(actor.cruise_speed > speed and actor.active, "%.0f km/h rival reaches competitive uncapped speed" % kmh)
		# A speed loss is physical; no position correction or instant restoration.
		actor.cruise_speed *= 0.5
		var at := actor.position
		var before := actor.cruise_speed
		race.prepare_opponent(1.0 / 60.0, speed, -5.0, traffic, speed)
		_check(actor.cruise_speed > before and actor.cruise_speed - before <= race.get_acceleration(speed) / 60.0 + 0.00001, "collision slowdown recovers with bounded throttle")
		_check(race.ai_state == "RECOVER", "collision slowdown exposes recovery state")
		_check(actor.position.z == at.z, "recovery never teleports rival forward")
		race.reset()
		actor.free()


func _test_high_speed_traffic() -> void:
	for kmh in [250.0, 300.0, 350.0, 400.0]:
		for step in [1.0 / 60.0, 0.1, 0.35]:
			var speed: float = kmh / 3.6
			var actor := _actor(Vector3(0, 0, -40), speed + 1.0)
			var blocker := _actor(Vector3(0, 0, -90), speed * 0.7)
			var right := _actor(Vector3(5, 0, -92), speed * 0.7)
			var traffic: Array[RoadObstacle] = [actor, blocker, right]
			var race := Race.new()
			race.begin(actor, speed)
			race.countdown_remaining = 0.0
			race.set_difficulty(1800.0, 1.6)
			for frame in range(ceili(6.0 / step)):
				var from := actor.position
				race.prepare_opponent(step, speed, -5.0, traffic, speed)
				_check(not actor.advance_pass((speed - actor.cruise_speed) * step, -5.0), "high-speed traffic avoidance does not hit player")
				for obstacle in [blocker, right]:
					var obstacle_from: Vector3 = obstacle.position
					obstacle.position.z += (speed - obstacle.cruise_speed) * step
					_check(not _traffic_contact(from, actor.position, obstacle_from, obstacle.position, actor, obstacle), "%.0f km/h %.3fs tick never sweeps through traffic" % [kmh, step])
			_check(actor.position.z < blocker.position.z - actor.half_length - blocker.half_length and actor.active, "high-speed rival overtakes traffic within six seconds")
			race.reset()
			actor.free()
			blocker.free()
			right.free()


func _test_difficulty_and_memory() -> void:
	var early_speed := 0.0
	for seconds in [0.0, 1800.0]:
		var actor := _actor(Vector3(0, 0, 12), 63.0)
		var traffic: Array[RoadObstacle] = [actor]
		var race := Race.new()
		race.begin(actor, 62.0)
		race.countdown_remaining = 0.0
		race.set_difficulty(seconds, 1.6)
		for frame in range(120):
			race.prepare_opponent(1.0 / 60.0, 62.0, 0.0, traffic, 63.0)
			actor.advance_pass((63.0 - actor.cruise_speed) / 60.0, 0.0)
		if seconds == 0.0:
			early_speed = actor.cruise_speed
		else:
			_check(actor.cruise_speed > early_speed and actor.cruise_speed < 72.0, "late rival adds pressure while retaining a beatable finite advantage")
		race.reset()
		_check(race.blocked_seconds == 0.0 and race.ai_state == "CHASE", "new encounter clears blocking and state memory")
		actor.free()


func _test_boost_escape() -> void:
	var actor := _actor(Vector3(0, 0, 12), 63.0)
	var traffic: Array[RoadObstacle] = [actor]
	var race := Race.new()
	race.begin(actor, 62.0)
	race.countdown_remaining = 0.0
	for frame in range(60):
		race.prepare_opponent(1.0 / 60.0, 62.0, 0.0, traffic, 63.0)
		actor.advance_pass((63.0 - actor.cruise_speed) / 60.0, 0.0)
	for frame in range(480):
		race.prepare_opponent(1.0 / 60.0, 62.0, 0.0, traffic, 80.0)
		_check(not actor.advance_pass((80.0 - actor.cruise_speed) / 60.0, 0.0), "boost escape retains physical clearance")
	_check(actor.position.z > 80.0 and actor.cruise_speed <= 62.0 + Race.PASS_ADVANTAGE, "anti-block passing cannot rubber-band its target speed to player boost")
	race.reset()
	actor.free()


func _test_merging_traffic() -> void:
	var speed := 400.0 / 3.6
	var actor := _actor(Vector3(0, 0, -40), speed + 1.0)
	var merging := _actor(Vector3(5, 0, -42), speed)
	merging.lane_target = 0.0
	merging.changing_lane = true
	var traffic: Array[RoadObstacle] = [actor, merging]
	var race := Race.new()
	race.begin(actor, speed)
	race.countdown_remaining = 0.0
	for frame in range(180):
		var from := actor.position
		var obstacle_from := merging.position
		race.prepare_opponent(1.0 / 60.0, speed, -5.0, traffic, speed)
		_check(not actor.advance_pass((speed - actor.cruise_speed) / 60.0, -5.0), "avoid merging traffic without cutting player")
		merging.position.x = move_toward(merging.position.x, 0.0, 5.0 / 60.0)
		merging.changing_lane = not is_equal_approx(merging.position.x, 0.0)
		_check(not _traffic_contact(from, actor.position, obstacle_from, merging.position, actor, merging), "400 km/h rival anticipates an already signalled traffic merge")
	race.reset()
	actor.free()
	merging.free()


func _traffic_contact(from: Vector3, to: Vector3, other_from: Vector3, other_to: Vector3, first: RoadObstacle, second: RoadObstacle) -> bool:
	# Independent physical samples avoid asserting against the AI's own sweep
	# implementation. At the tested 0.35s maximum tick spacing is <0.6m.
	for index in range(65):
		var difference := from.lerp(to, index / 64.0) - other_from.lerp(other_to, index / 64.0)
		if absf(difference.x) <= first.half_width + second.half_width and absf(difference.z) <= first.half_length + second.half_length:
			return true
	return false


func _test_density_horizon() -> void:
	for density in [0.0, 1.0]:
		var actor := _actor(Vector3(0, 0, -14), 63.0)
		var blocker := _actor(Vector3(0, 0, -109), 14.0)
		var traffic: Array[RoadObstacle] = [actor, blocker]
		var race := Race.new()
		race.begin(actor, 62.0)
		race.countdown_remaining = 0.0
		race.set_difficulty(0.0, density)
		race.prepare_opponent(1.0 / 60.0, 62.0, 5.0, traffic, 62.0)
		_check(actor.position.x == 0.0 if density == 0.0 else actor.position.x < 0.0, "director density in 0..1 increases anticipation of a 95m blocker")
		race.reset()
		actor.free()
		blocker.free()


func _actor(at: Vector3, speed: float) -> RoadObstacle:
	var actor := RoadObstacle.new()
	root.add_child(actor)
	actor.activate(at, RoadObstacle.Kind.WIDE, 0.0, 8)
	actor.cruise_speed = speed
	return actor


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures <= 10:
			push_error("STAGE TWO APEX FAIL: " + message)
