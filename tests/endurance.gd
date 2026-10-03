extends SceneTree

var failures: int = 0
var maximum_pool: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var road := RoadManager.new()
	root.add_child(road)
	var road_nodes := road.get_child_count()
	# Eight repeatable runs at maximum speed/density, totaling 128 km.
	for run_seed in range(8):
		var spawner := ObstacleSpawner.new()
		root.add_child(spawner)
		spawner.reset_spawner(run_seed)
		var total_distance := 0.0
		for step in range(12000):
			var distance_delta := 80.0 / 60.0
			total_distance += distance_delta
			road.advance(distance_delta)
			spawner.advance(distance_delta, total_distance, 1.0, 1.0 / 60.0)
			maximum_pool = maxi(maximum_pool, spawner.obstacle_pool.size())
			if step % 120 == 0:
				_check_road(road)
				_check_routes(spawner)
				_check(spawner.obstacle_pool.size() <= 12, "bounded pool, seed %d" % run_seed)
				# A pool can grow as denser random rows arrive, but every child
				# must be accounted for and remain under the fixed spatial bound.
				_check(spawner.get_child_count() == spawner.obstacle_pool.size(), "no untracked obstacle nodes")
		_check(road.get_child_count() == road_nodes, "no road node growth")
		# Restart repeatedly reuses the existing pool and road segments.
		for restart in range(25):
			spawner.reset_spawner()
			road.reset_road()
			_check_road(road)
			_check_routes(spawner)
			_check(spawner.obstacle_pool.size() <= 12, "bounded pool after restart")
		spawner.free()
	road.free()
	if failures == 0:
		print("ENDURANCE PASS: 8 seeds, 128 km at 80 m/s, 200 restarts, seamless road, reachable lanes; maximum pool %d" % maximum_pool)
	quit(1 if failures > 0 else 0)


func _check_road(road: RoadManager) -> void:
	var positions: Array[float] = []
	for segment in road.segments:
		positions.append(segment.position.z)
	positions.sort()
	for index in range(1, positions.size()):
		_check(absf(positions[index] - positions[index - 1] - 40.0) < 0.001, "seamless road recycling")
	_check(positions[0] < -200.0 and positions[-1] >= 0.0, "road covers player and horizon")


func _check_routes(spawner: ObstacleSpawner) -> void:
	var rows: Dictionary = {}
	for obstacle in spawner.obstacle_pool:
		if not obstacle.active or obstacle.position.z > 0.0:
			continue
		var row_z := snappedf(obstacle.position.z, 0.001)
		if not rows.has(row_z):
			rows[row_z] = []
		var lane: int = spawner.LANE_CENTERS.find(obstacle.position.x)
		_check(lane >= 0, "hazards stay in lanes")
		_check(not rows[row_z].has(lane), "no overlapping barriers")
		rows[row_z].append(lane)
	var row_positions: Array = rows.keys()
	row_positions.sort()
	row_positions.reverse()
	var reachable: Array[int] = [0, 1, 2]
	var previous_z: float = 0.0
	for row_z in row_positions:
		if previous_z != 0.0:
			_check(previous_z - float(row_z) >= 63.99, "64 m minimum reaction distance")
		var next_reachable: Array[int] = []
		for lane in range(3):
			if rows[row_z].has(lane):
				continue
			for previous_lane in reachable:
				if absi(lane - previous_lane) <= 1:
					next_reachable.append(lane)
					break
		_check(not next_reachable.is_empty(), "reachable lane through successive rows")
		reachable = next_reachable
		previous_z = row_z


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 10:
			push_error("ENDURANCE FAIL: " + label)
