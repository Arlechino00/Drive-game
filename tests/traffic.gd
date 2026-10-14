extends SceneTree

const Spawner = preload("res://scripts/obstacle_spawner.gd")
const Obstacle = preload("res://scripts/obstacle.gd")
const Player = preload("res://scripts/player_car.gd")
const Models = preload("res://scripts/traffic_models.gd")
var failures: int = 0
var rewards: Array[int] = []
var clearances: Array[float] = []
var hits: int = 0
var maximum_pool: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_relative_motion_and_seed()
	_test_boost_routes_and_pool()
	await _test_near_misses()
	await _test_real_collision()
	if failures == 0:
		print("TRAFFIC PASS: relative speed/density, reproducible seed, 8 boost runs/52.8 km, 200 resets, reachable 64 m rows, near-miss tiers/reuse/collision exclusion; maximum pool %d" % maximum_pool)
	quit(1 if failures else 0)


func _test_relative_motion_and_seed() -> void:
	var moving = Spawner.new()
	var legacy = Spawner.new()
	root.add_child(moving)
	root.add_child(legacy)
	moving.reset_spawner(312)
	legacy.reset_spawner(312)
	_check(moving.active_seed == 312, "debug seed retained")
	var initial: Array[String] = _snapshot(moving)
	var first = moving.obstacle_pool[0]
	var start_z: float = first.position.z
	# These advance-only fixtures measure generation without driver contacts.
	moving.advance(80.0, 80.0, 1.0, 1.0, 10.0)
	legacy.advance(66.0, 66.0, 1.0, 0.0, 10.0)
	_check(is_equal_approx(first.position.z - start_z, 66.0), "80 m/s boost approaches 14 m/s traffic at 66 m/s")
	_check(_snapshot(moving) == _snapshot(legacy), "row density uses relative travel rather than scenery travel")
	var replay: Array[String] = _snapshot(moving)
	moving.reset_spawner(312)
	_check(_snapshot(moving) == initial, "seed reproduces initial vehicles")
	moving.advance(80.0, 80.0, 1.0, 1.0, 10.0)
	_check(_snapshot(moving) == replay, "seed reproduces subsequent rows after pool reuse")
	for attempt in range(10):
		moving.reset_spawner()
		var generated_seed: int = moving.active_seed
		var generated_layout: Array[String] = _snapshot(moving)
		moving.reset_spawner(generated_seed)
		_check(_snapshot(moving) == generated_layout, "displayed random seed can reproduce its run")
	moving.free()
	legacy.free()


func _test_boost_routes_and_pool() -> void:
	for run_seed in range(8):
		var spawner = Spawner.new()
		root.add_child(spawner)
		spawner.reset_spawner(run_seed)
		for step in range(6000):
			spawner.advance(80.0 / 60.0, (step + 1) * 80.0 / 60.0, 1.0, 1.0 / 60.0, 10.0)
			maximum_pool = maxi(maximum_pool, spawner.obstacle_pool.size())
			if step % 120 == 0:
				_check_routes(spawner)
				_check(spawner.obstacle_pool.size() <= 12, "bounded traffic pool at maximum boost/density")
				_check(spawner.get_child_count() == spawner.obstacle_pool.size(), "no abandoned traffic nodes")
				for obstacle in spawner.obstacle_pool:
					_check(obstacle.player_hit.get_connections().size() == 1 and obstacle.near_miss.get_connections().size() == 1, "pool callbacks connected once")
		for restart in range(25):
			spawner.reset_spawner(run_seed)
			_check_routes(spawner)
			_check(spawner.obstacle_pool.size() <= 12, "restart retains bounded pool")
		spawner.free()


func _test_near_misses() -> void:
	var obstacle = Obstacle.new()
	root.add_child(obstacle)
	obstacle.near_miss.connect(_on_near_miss)
	# Use edge clearances; rewards must agree with the real player's footprint.
	var half_width := Models.dimensions(Models.Model.PULSE).x * 0.5
	var close_x := Obstacle.PLAYER_HALF_WIDTH + half_width + 0.225
	var very_close_x := Obstacle.PLAYER_HALF_WIDTH + half_width + 0.125
	var near_x := Obstacle.PLAYER_HALF_WIDTH + half_width + 0.825
	obstacle.activate(Vector3(0, 0, -7), Obstacle.Kind.CAR, close_x)
	obstacle.advance_pass(7.0, close_x)
	await process_frame
	_check(rewards.is_empty(), "no award while alongside")
	var rear_clearance := Obstacle.PLAYER_HALF_LENGTH + Models.dimensions(Models.Model.PULSE).z * 0.5
	obstacle.advance_pass(rear_clearance - 0.1, close_x)
	await process_frame
	_check(rewards.is_empty(), "no award until actual rear clears actual player length")
	obstacle.advance_pass(0.5, close_x)
	await process_frame
	_check(rewards == [250], "close pass awards tier after rear clears")
	_check(clearances.size() == 1 and is_equal_approx(clearances[0], 0.225), "clearance measured edge to edge")
	obstacle.advance_pass(1.0, close_x)
	await process_frame
	_check(rewards.size() == 1, "one award per pass")
	# Reuse must clear prior reward and minimum clearance.
	obstacle.deactivate()
	obstacle.activate(Vector3(0, 0, -7), Obstacle.Kind.CAR, very_close_x)
	obstacle.advance_pass(13.0, very_close_x)
	await process_frame
	_check(rewards == [250, 500], "reused traffic earns fresh extremely-close pass")
	obstacle.deactivate()
	obstacle.activate(Vector3(0, 0, -7), Obstacle.Kind.CAR, near_x)
	obstacle.advance_pass(13.0, near_x)
	await process_frame
	_check(rewards == [250, 500, 100], "near pass awards lower tier")
	var before: int = rewards.size()
	# Sweep from one side to the other across a vehicle must never earn a pass.
	obstacle.activate(Vector3(0, 0, -1), Obstacle.Kind.CAR, -close_x)
	obstacle.advance_pass(8.0, close_x)
	await process_frame
	_check(rewards.size() == before and obstacle.pass_collided, "swept lateral overlap excludes near-miss")
	obstacle.activate(Vector3(0, 0, -7), Obstacle.Kind.CAR, 0.0)
	obstacle.advance_pass(7.0, 0.0)
	obstacle.advance_pass(6.0, close_x)
	await process_frame
	_check(rewards.size() == before, "collision then steering clear does not earn near-miss")
	# Proximity before longitudinal overlap is not a pass.
	obstacle.activate(Vector3(0, 0, -12), Obstacle.Kind.CAR, close_x)
	obstacle.advance_pass(1.0, close_x)
	obstacle.advance_pass(1.0, 6.2)
	obstacle.advance_pass(17.0, 6.2)
	await process_frame
	_check(rewards.size() == before, "outside-footprint proximity is ignored")
	# A queued prior activation cannot reward a newly recycled object.
	obstacle.activate(Vector3(0, 0, -7), Obstacle.Kind.CAR, close_x)
	obstacle.advance_pass(13.0, close_x)
	obstacle.deactivate()
	obstacle.activate(Vector3(0, 0, -50), Obstacle.Kind.CAR, close_x)
	await process_frame
	_check(rewards.size() == before, "queued reward canceled on reset/reuse")
	# Collision callback ordered after the sweep, before deferred award.
	var player := Area3D.new()
	player.add_to_group("player")
	root.add_child(player)
	obstacle.activate(Vector3(0, 0, -7), Obstacle.Kind.CAR, close_x)
	obstacle.advance_pass(13.0, close_x)
	obstacle.area_entered.emit(player)
	await process_frame
	_check(rewards.size() == before, "collision callback cancels queued reward")
	player.free()
	obstacle.free()


func _test_real_collision() -> void:
	var player := Player.new()
	root.add_child(player)
	var obstacle = Obstacle.new()
	root.add_child(obstacle)
	obstacle.player_hit.connect(_on_hit)
	obstacle.near_miss.connect(_on_near_miss)
	var before: int = rewards.size()
	obstacle.activate(Vector3.ZERO, Obstacle.Kind.VAN, 0.0)
	for frame in range(4):
		await physics_frame
	_check(hits == 1 and not obstacle.active, "Godot physical contact crashes/deactivates traffic once")
	_check(rewards.size() == before and obstacle.pass_collided, "actual contact excludes reward")
	player.free()
	obstacle.free()


func _snapshot(spawner) -> Array[String]:
	var result: Array[String] = []
	for obstacle in spawner.obstacle_pool:
		if obstacle.active:
			result.append("%.3f/%.3f/%d" % [obstacle.position.x, obstacle.position.z, obstacle.kind])
	result.sort()
	return result


func _on_near_miss(points: int, clearance: float) -> void:
	rewards.append(points)
	clearances.append(clearance)


func _on_hit() -> void:
	hits += 1


func _check_routes(spawner) -> void:
	var rows: Dictionary = {}
	for obstacle in spawner.obstacle_pool:
		if not obstacle.active or obstacle.position.z > 0.0:
			continue
		var row_z := snappedf(obstacle.position.z, 0.001)
		if not rows.has(row_z):
			rows[row_z] = []
		var lane: int = [-5.0, 0.0, 5.0].find(obstacle.position.x)
		_check(lane >= 0, "traffic stays in readable lanes")
		_check(not rows[row_z].has(lane), "no overlapping traffic")
		rows[row_z].append(lane)
	var positions: Array = rows.keys()
	positions.sort()
	positions.reverse()
	var reachable: Array[int] = [0, 1, 2]
	var previous_z: float = 0.0
	for row_z in positions:
		if previous_z != 0.0:
			_check(previous_z - float(row_z) >= 63.99, "64 m reaction distance at boost speed")
		var next_reachable: Array[int] = []
		for lane in range(3):
			if rows[row_z].has(lane):
				continue
			for previous_lane in reachable:
				if absi(lane - previous_lane) <= 1:
					next_reachable.append(lane)
					break
		_check(not next_reachable.is_empty(), "adjacent escape lane through successive rows")
		reachable = next_reachable
		previous_z = row_z


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 12:
			push_error("TRAFFIC FAIL: " + label)
