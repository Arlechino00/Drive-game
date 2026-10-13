extends SceneTree

const Race = preload("res://scripts/apex_race.gd")
const Models = preload("res://scripts/traffic_models.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_requirement_range()
	_test_outer_lane_detour()
	_test_jammed_overtake()
	_test_aggressive_bursts()
	_test_safe_player_lane()
	_test_committed_turn()
	_test_braked_turn()
	_test_following_traffic()
	_test_seeded_routes()
	if failures == 0:
		print("APEX SAFETY PASS: drawn 4-7s boost requirements, bounded jam escape, all-lane swept detours, deterministic finite bursts, fast safe overtakes, 7s boost victory, safe-lane driver, committed-turn protection, blocked-lane braking, eight seeded live-race routes, no traffic clipping, boost requirement after braking")
	quit(1 if failures else 0)


func _test_requirement_range() -> void:
	var actor := RoadObstacle.new()
	root.add_child(actor)
	var race := Race.new()
	for requirement in [4.0, 5.0, 6.0, 7.0]:
		actor.activate(Vector3(5, 0, -14), 3, -5.0, 8)
		race.begin(actor, 62.0, requirement)
		_check(race.required_boost_seconds == requirement, "race accepts its drawn 4-7 second requirement")
		actor.position.z = 20.0
		race.boost_seconds = requirement - 0.01
		_check(race.advance(33.0, false) == -1, "race fails just below its drawn boost requirement")
		actor.activate(Vector3(5, 0, -14), 3, -5.0, 8)
		race.begin(actor, 62.0, requirement)
		actor.position.z = 20.0
		race.boost_seconds = requirement
		_check(race.advance(33.0, false) == 1, "race accepts exact drawn boost requirement")
	race.begin(actor, 62.0, 0.0)
	_check(race.required_boost_seconds == 4.0, "boost requirement clamps to minimum four seconds")
	race.begin(actor, 62.0, 100.0)
	_check(race.required_boost_seconds == 7.0, "boost requirement clamps to maximum seven seconds")
	race.reset()
	_check(race.required_boost_seconds == 4.0, "reset clears previous boost requirement")
	actor.free()


func _test_outer_lane_detour() -> void:
	var actor := RoadObstacle.new()
	var blocker := RoadObstacle.new()
	var center := RoadObstacle.new()
	root.add_child(actor)
	root.add_child(blocker)
	root.add_child(center)
	actor.activate(Vector3(-5, 0, -40), 3, -5.0, 8)
	blocker.activate(Vector3(-5, 0, -60), 3, -5.0, 2)
	center.activate(Vector3(0, 0, -42), 3, -5.0, 2)
	var race := Race.new()
	race.begin(actor, 62.0)
	actor.cruise_speed = 63.0
	race.countdown_remaining = 0.0
	var traffic: Array[RoadObstacle] = [actor, blocker, center]
	race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, traffic, 62.0)
	_check(race.lane_target == 5.0, "rival finds clear far lane through a physically safe center transit")
	for frame in range(90):
		race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, traffic, 62.0)
		actor.advance_pass((62.0 - actor.cruise_speed) / 60.0, -5.0)
		blocker.position.z += 48.0 / 60.0
		center.position.z += 48.0 / 60.0
		for obstacle in [blocker, center]:
			var lateral_overlap: bool = absf(actor.position.x - obstacle.position.x) < actor.half_width + obstacle.half_width
			var longitudinal_overlap: bool = absf(actor.position.z - obstacle.position.z) < actor.half_length + obstacle.half_length
			_check(not (lateral_overlap and longitudinal_overlap), "outer lane detour never clips center or original blocker")
	_check(actor.position.x >= 0.0 and actor.position.z < blocker.position.z, "all-lane detour clears blocker within 1.5 seconds: actor=%s blocker=%s target=%s" % [actor.position, blocker.position, race.lane_target])
	race.reset()
	actor.free()
	blocker.free()
	center.free()

func _test_jammed_overtake() -> void:
	for player_speed in [27.0, 62.0]:
		var actor := RoadObstacle.new()
		var blocker := RoadObstacle.new()
		var right := RoadObstacle.new()
		root.add_child(actor)
		root.add_child(blocker)
		root.add_child(right)
		actor.activate(Vector3(0, 0, -14), 3, -5.0, 8)
		blocker.activate(Vector3(0, 0, -26), 3, -5.0, 2)
		right.activate(Vector3(5, 0, -26), 3, -5.0, 2)
		var race := Race.new()
		race.begin(actor, 62.0)
		actor.cruise_speed = 63.0
		race.countdown_remaining = 0.0
		var traffic: Array[RoadObstacle] = [actor, blocker, right]
		var cleared := false
		# A blocked rival now accelerates physically after braking; allow that
		# recovery while still requiring a bounded, contact-free escape.
		for frame in range(240):
			race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, traffic, player_speed)
			actor.advance_pass((player_speed - actor.cruise_speed) / 60.0, -5.0)
			blocker.position.z += (player_speed - 14.0) / 60.0
			right.position.z += (player_speed - 14.0) / 60.0
			for obstacle in [blocker, right]:
				_check(not (absf(actor.position.x - obstacle.position.x) < actor.half_width + obstacle.half_width and absf(actor.position.z - obstacle.position.z) < actor.half_length + obstacle.half_length), "jam escape preserves traffic footprints")
			if actor.position.z < blocker.position.z - actor.half_length - blocker.half_length:
				cleared = true
				break
		_check(cleared and actor.active, "jammed rival clears accessible left detour within four seconds with finite acceleration at player speed %.0f" % player_speed)
		if not cleared:
			print("JAM REPRO player=", player_speed, " rival=", actor.position, " cruise=", actor.cruise_speed, " target=", race.lane_target, " blocker=", blocker.position)
		race.reset()
		actor.free()
		blocker.free()
		right.free()

func _test_aggressive_bursts() -> void:
	var actor := RoadObstacle.new()
	root.add_child(actor)
	actor.activate(Vector3(5, 0, -14), 3, -5.0, 8)
	var race := Race.new()
	race.begin(actor, 62.0)
	race.countdown_remaining = 0.0
	var traffic: Array[RoadObstacle] = [actor]
	actor.cruise_speed = 62.0 + Race.SPEED_ADVANTAGE
	_check(actor.cruise_speed == 65.0, "burst fixture begins at new rival cruise speed")
	race.elapsed = 6.0
	race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, traffic)
	_check(actor.cruise_speed > 65.0 and actor.cruise_speed <= 65.0 + race.get_acceleration(62.0) / 60.0 + 0.00001, "deterministic burst accelerates actual cruise speed finitely")
	actor.advance_pass((62.0 - actor.cruise_speed) / 60.0, -5.0)
	_check(actor.position.z < -14.0, "burst advances rival relative to unboosted player")
	race.elapsed = 7.0
	for frame in range(3):
		race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, traffic)
	_check(actor.cruise_speed == 65.0, "one-second burst returns to cruise with finite deceleration")
	race.elapsed = 16.0
	for frame in range(180):
		var before := actor.cruise_speed
		race.prepare_opponent(1.0 / 60.0, 100.0, -5.0, traffic, 100.0)
		_check(actor.cruise_speed - before <= race.get_acceleration(100.0) / 60.0 + 0.00001, "high-speed burst cannot jump speed")
	_check(is_equal_approx(actor.cruise_speed, 104.0), "rival scales to actual run speed without the old fixed ceiling")
	race.reset()
	actor.activate(Vector3(5, 0, -100), 3, -5.0, 8)
	race.begin(actor, 62.0)
	actor.cruise_speed = 63.0
	race.countdown_remaining = 0.0
	var blocker := RoadObstacle.new()
	root.add_child(blocker)
	blocker.activate(Vector3(5, 0, -170), 3, -5.0, 2)
	traffic.append(blocker)
	race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, traffic)
	_check(race.lane_target == 0.0 and is_equal_approx(actor.position.x, 4.8), "70m traffic gap triggers a quick 12m/s adjacent overtake")
	traffic.erase(blocker)
	blocker.free()
	race.reset()
	actor.activate(Vector3(5, 0, -14), 3, -5.0, 8)
	race.begin(actor, 62.0, 7.0)
	race.advance(3.0, false)
	var speed := 62.0
	var result := 0
	for frame in range(1800):
		var boosted := frame < 420
		speed = move_toward(speed, 62.0 + DifficultyDirector.BOOST_SPEED_GAIN if boosted else 62.0, (16.0 if boosted else 12.0) / 60.0)
		race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, traffic, speed)
		actor.advance_pass((speed - actor.cruise_speed) / 60.0, -5.0)
		result = race.advance(1.0 / 60.0, boosted)
	_check(result == 1 and race.lead_m > 0.0, "seven seconds of boost beats aggressive bursts with real acceleration")
	_check(race.boost_seconds >= 6.99, "actual boosting time meets victory requirement")
	race.reset()
	actor.free()

func _test_safe_player_lane() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(0)
	var actor := spawner._take_obstacle()
	actor.activate(Vector3(0, 0, -14), Models.kind_for_model(8), -5.0, 8)
	var race := Race.new()
	race.begin(actor, 62.0)
	actor.cruise_speed = 63.0
	race.countdown_remaining = 0.0
	spawner.begin_race(actor)
	for frame in range(100):
		race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, spawner.obstacle_pool)
		spawner.advance(80.0 / 60.0, 2000.0 + frame * 80.0 / 60.0, 1.0, 1.0 / 60.0, -5.0)
		_check(actor.active and not actor.pass_collided, "seed-zero rival does not cut into safe left-lane driver")
		if not actor.active:
			break
		race.advance(1.0 / 60.0, true)
	race.reset()
	spawner.free()


func _test_committed_turn() -> void:
	var actor := RoadObstacle.new()
	root.add_child(actor)
	actor.activate(Vector3(0, 0, -8), 3, -5.0, 8)
	var race := Race.new()
	race.begin(actor, 62.0)
	actor.cruise_speed = 63.0
	race.countdown_remaining = 0.0
	race.lane_target = -5.0
	var traffic: Array[RoadObstacle] = [actor]
	for frame in range(90):
		race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, traffic)
		_check(absf(actor.position.x + 5.0) > actor.half_width + actor.PLAYER_HALF_WIDTH, "committed target is checked while driver becomes alongside")
	race.reset()
	actor.free()


func _test_braked_turn() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	spawner.spawning_enabled = false
	var actor := spawner._take_obstacle()
	actor.activate(Vector3(0, 0, -30), 3, -5.0, 8)
	var barrier := spawner._take_obstacle()
	barrier.activate(Vector3(0, 0, -38), RoadObstacle.Kind.ROADWORKS, -5.0)
	var right := spawner._take_obstacle()
	right.activate(Vector3(5, 0, -38), RoadObstacle.Kind.ROADWORKS, -5.0)
	var race := Race.new()
	race.begin(actor, 62.0)
	actor.cruise_speed = 63.0
	race.countdown_remaining = 0.0
	actor.cruise_speed = 0.0
	race.lane_target = -5.0
	spawner.race_actor = actor
	for frame in range(30):
		race.prepare_opponent(1.0 / 60.0, 62.0, -5.0, spawner.obstacle_pool)
		spawner.advance(80.0 / 60.0, 2000.0 + frame * 80.0 / 60.0, 1.0, 1.0 / 60.0, -5.0)
		_check(actor.active and not actor.pass_collided, "braked opponent protects faster player catching a committed turn")
		if not actor.active:
			break
	race.reset()
	spawner.free()

func _test_following_traffic() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	spawner.spawning_enabled = false
	var actor := spawner._take_obstacle()
	actor.activate(Vector3(0, 0, -14), 3, -5.0, 8)
	var blocker := spawner._take_obstacle()
	blocker.activate(Vector3(0, 0, -26), 3, -5.0, 2)
	var right_blocker := spawner._take_obstacle()
	right_blocker.activate(Vector3(5, 0, -26), 3, -5.0, 2)
	var race := Race.new()
	race.begin(actor, 62.0)
	actor.cruise_speed = 63.0
	race.countdown_remaining = 0.0
	spawner.race_actor = actor
	race.prepare_opponent(0.5, 62.0, -5.0, spawner.obstacle_pool)
	_check(actor.cruise_speed < 63.0, "rival brakes when player and paired traffic block lane changes")
	spawner.advance(40.0, 2040.0, 1.0, 0.5, -5.0)
	_check(actor.position.z - blocker.position.z >= actor.half_length + blocker.half_length, "long tick preserves following collision gap")
	actor.position.z = 20.0
	_check(race.advance(33.0, false) == -1, "braked rival cannot grant an unboosted race win")
	race.reset()
	spawner.free()


func _test_seeded_routes() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	var race := Race.new()
	for seed_id in [0, 1, 4, 8, 12, 15, 24, 37]:
		spawner.reset_spawner(seed_id)
		var actor := spawner._take_obstacle()
		actor.activate(Vector3(0, 0, -14), 3, 100.0, 8)
		race.begin(actor, 62.0)
		actor.cruise_speed = 63.0
		race.countdown_remaining = 0.0
		spawner.begin_race(actor)
		for frame in range(1800):
			var elapsed := frame / 60.0
			var boost_start := float(seed_id % 20)
			var boosted := elapsed >= boost_start and elapsed < boost_start + 7.0
			var speed := 80.0 if boosted else 62.0
			race.prepare_opponent(1.0 / 60.0, 62.0, 100.0, spawner.obstacle_pool, speed)
			spawner.advance(speed / 60.0, 2000.0 + elapsed * 62.0, 1.0, 1.0 / 60.0, 100.0)
			var blocked: Array[Vector2] = []
			for obstacle in spawner.obstacle_pool:
				if not obstacle.active:
					continue
				if absf(obstacle.position.z) <= obstacle.half_length + obstacle.PLAYER_HALF_LENGTH:
					var side := obstacle.half_width + obstacle.PLAYER_HALF_WIDTH
					blocked.append(Vector2(obstacle.position.x - side, obstacle.position.x + side))
				if obstacle != actor:
					var lateral_overlap: bool = absf(obstacle.position.x - actor.position.x) < obstacle.half_width + actor.half_width - 0.001
					var longitudinal_overlap: bool = absf(obstacle.position.z - actor.position.z) < obstacle.half_length + actor.half_length - 0.001
					_check(not (lateral_overlap and longitudinal_overlap), "seed %d live rival does not clip another encounter" % seed_id)
			blocked.sort_custom(func(first: Vector2, second: Vector2): return first.x < second.x)
			var coverage := -6.2
			for interval in blocked:
				if interval.x <= coverage:
					coverage = maxf(coverage, interval.y)
			_check(coverage < 6.2, "seed %d frame %d preserves a clear driver path" % [seed_id, frame])
			race.advance(1.0 / 60.0, boosted)
		race.reset()
	spawner.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		if failures <= 12:
			push_error("APEX SAFETY FAIL: " + message)
