class_name ObstacleSpawner
extends Node3D

signal player_hit
signal pothole_hit
signal roadworks_entered
signal near_miss(points: int, clearance: float)

const Obstacle = preload("res://scripts/obstacle.gd")
const Models = preload("res://scripts/traffic_models.gd")
const LANE_CENTERS: Array[float] = [-5.0, 0.0, 5.0]
const SPAWN_AHEAD: float = 285.0
const MIN_ROW_SPACING: float = 64.0
const STATIC_ROW_SPACING: float = 80.0
const TRAFFIC_DRAIN_Z: float = -96.0
const MAX_POOL_SIZE: int = 12
const APEX_WEIGHT: float = 0.06
const APEX_FIRST_DISTANCE: float = 1800.0
const APEX_SPACING: float = 2500.0

enum Wave { TRAFFIC, WAIT_FOR_STATIC, STATIC }

var obstacle_pool: Array[RoadObstacle] = []
var next_row_at: float = 70.0
var last_safe_lane: int = 1
var random: RandomNumberGenerator = RandomNumberGenerator.new()
var active_seed: int = 0
var relative_distance: float = 0.0
var last_hit_obstacle: RoadObstacle
var spawning_enabled: bool = true
var motion_enabled: bool = true
var _generation_epoch: int = 0
var _wave: int = Wave.TRAFFIC
var _rows_left: int = 0
var _next_row_z: float = -70.0
var race_actor: RoadObstacle
var _total_run_distance: float = 0.0
var _next_apex_distance: float = APEX_FIRST_DISTANCE


func reset_spawner(run_seed: int = -1) -> void:
	_generation_epoch += 1
	race_actor = null
	_total_run_distance = 0.0
	_next_apex_distance = APEX_FIRST_DISTANCE
	motion_enabled = true
	for obstacle in obstacle_pool:
		obstacle.deactivate()
	next_row_at = 70.0
	last_safe_lane = 1
	relative_distance = 0.0
	last_hit_obstacle = null
	_wave = Wave.TRAFFIC
	_next_row_z = -70.0
	if run_seed < 0:
		random.randomize()
		# Keep generated debug seeds non-negative so they can be passed back to
		# reset_spawner without being mistaken for the randomize sentinel.
		active_seed = random.randi()
	else:
		active_seed = run_seed
	random.seed = active_seed
	_rows_left = random.randi_range(6, 9)
	advance(0.0, 0.0, 0.0)


func advance(distance_delta: float, _total_distance: float, difficulty: float, delta: float = 0.0, player_x: float = 0.0) -> void:
	if not motion_enabled:
		return
	var generation_epoch := _generation_epoch
	_total_run_distance = _total_distance
	var contacted := false
	var relative_delta := maxf(0.0, distance_delta - Obstacle.TRAFFIC_SPEED * delta)
	relative_distance += relative_delta
	if _wave != Wave.WAIT_FOR_STATIC:
		_next_row_z += distance_delta if _wave == Wave.STATIC else relative_delta
	for obstacle in obstacle_pool:
		if obstacle.active:
			var activation_serial := obstacle._activation_serial
			var movement := maxf(0.0, distance_delta - obstacle.cruise_speed * delta)
			if obstacle == race_actor:
				movement = distance_delta - obstacle.cruise_speed * delta
			if obstacle.advance_pass(movement, player_x):
				contacted = true
				# An ended/reset run or a newly reused actor belongs to the callback.
				if not motion_enabled or generation_epoch != _generation_epoch or not is_instance_valid(obstacle) or activation_serial != obstacle._activation_serial:
					return
				# A surviving impact still advances the other actors in the row.
				continue
			if obstacle.position.z > 12.0 and obstacle != race_actor:
				obstacle.deactivate()
	# Keep the just-hit actor retired until queued Area notifications flush.
	if contacted or not spawning_enabled:
		return
	var intensity := clampf(difficulty, 0.0, 1.0)
	# Static rows approach faster than traffic. Drain the old traffic wave
	# before placing the first static row at the visibility horizon. Even at
	# 27 m/s after a pothole, this leaves >85 m between encounter times:
	# (285/27 - 96/(27-14))*27. Higher player speeds only enlarge this gap.
	if _wave == Wave.WAIT_FOR_STATIC:
		if _farthest_traffic_z() < TRAFFIC_DRAIN_Z:
			return
		_wave = Wave.STATIC
		_rows_left = random.randi_range(3, 5)
		_next_row_z = -SPAWN_AHEAD
	while _next_row_z >= -SPAWN_AHEAD:
		# A long frame or disabled generation can exhaust the old schedule.
		# New encounters must still appear ahead instead of at the player.
		_next_row_z = minf(_next_row_z, -70.0)
		var spacing := STATIC_ROW_SPACING if _wave == Wave.STATIC else lerpf(86.0, MIN_ROW_SPACING, intensity)
		# Schedule behind the actual farthest encounter, including the prior
		# wave. Static→traffic gaps subsequently widen instead of compressing.
		var farthest_z := _farthest_ahead_z()
		if farthest_z != INF:
			_next_row_z = minf(_next_row_z, farthest_z - spacing)
		if _next_row_z < -SPAWN_AHEAD or MAX_POOL_SIZE - get_active_count() < 2:
			break
		_spawn_row(_next_row_z, intensity, player_x, _wave == Wave.STATIC)
		_next_row_z -= spacing
		_rows_left -= 1
		if _rows_left == 0:
			if _wave == Wave.TRAFFIC:
				_wave = Wave.WAIT_FOR_STATIC
				break
			_wave = Wave.TRAFFIC
			_rows_left = random.randi_range(6, 9)
	next_row_at = relative_distance - _next_row_z


func get_active_count() -> int:
	var count := 0
	for obstacle in obstacle_pool:
		if obstacle.active:
			count += 1
	return count


func _spawn_row(row_z: float, difficulty: float, player_x: float, stationary: bool = false) -> void:
	last_safe_lane = clampi(last_safe_lane + random.randi_range(-1, 1), 0, 2)
	var double_row := difficulty > 0.35 and random.randf() < difficulty * 0.55
	var row_kind := Obstacle.Kind.POTHOLE if random.randf() < 0.5 else Obstacle.Kind.ROADWORKS
	var spawned_in_row := 0
	for lane_index in range(LANE_CENTERS.size()):
		if race_actor != null and spawned_in_row >= 1:
			break
		if lane_index == last_safe_lane:
			continue
		if not double_row and random.randi_range(0, 1) == 0:
			continue
		_activate_encounter(lane_index, row_z, player_x, row_kind if stationary else -1)
		spawned_in_row += 1
	if spawned_in_row == 0:
		_activate_encounter((last_safe_lane + 1) % LANE_CENTERS.size(), row_z, player_x, row_kind if stationary else -1)


func _activate_encounter(lane_index: int, row_z: float, player_x: float, encounter_kind: int) -> void:
	var model := -1
	var chosen_kind := encounter_kind
	if encounter_kind < 0:
		# Ordinary models have equal weight; Apex has an independent rare draw.
		var ordinary: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 9]
		model = ordinary[random.randi_range(0, ordinary.size() - 1)]
		if _total_run_distance >= _next_apex_distance and race_actor == null and random.randf() < APEX_WEIGHT:
			model = Models.Model.APEX
			_next_apex_distance = _total_run_distance + APEX_SPACING
		chosen_kind = Models.kind_for_model(model)
	_take_obstacle().activate(Vector3(LANE_CENTERS[lane_index], 0.0, row_z), chosen_kind, player_x, model)


func finish_race() -> void:
	if is_instance_valid(race_actor):
		race_actor.deactivate()
	race_actor = null


func begin_race(actor: RoadObstacle) -> void:
	race_actor = actor
	# The rival adds a moving hazard. Keep just one ordinary encounter per
	# existing/future row so it cannot turn a paired row into a full road block.
	var rows: Dictionary = {}
	for obstacle in obstacle_pool:
		if not obstacle.active or obstacle == actor or obstacle.position.z > 12.0:
			continue
		var key := snappedf(obstacle.position.z, 0.001)
		if rows.has(key):
			obstacle.deactivate()
		else:
			rows[key] = true


func _farthest_ahead_z() -> float:
	var farthest_z := INF
	for obstacle in obstacle_pool:
		if obstacle.active and obstacle.position.z <= 0.0:
			farthest_z = minf(farthest_z, obstacle.position.z)
	return farthest_z


func _farthest_traffic_z() -> float:
	var farthest_z := INF
	for obstacle in obstacle_pool:
		if obstacle.active and obstacle.cruise_speed > 0.0 and obstacle.position.z <= 0.0:
			farthest_z = minf(farthest_z, obstacle.position.z)
	return farthest_z


func upcoming_rows() -> Array[Dictionary]:
	var grouped: Dictionary = {}
	for obstacle in obstacle_pool:
		if not obstacle.active or obstacle.position.z > obstacle.half_length + obstacle.PLAYER_HALF_LENGTH:
			continue
		var row_z := snappedf(obstacle.position.z, 0.001)
		if not grouped.has(row_z):
			grouped[row_z] = {"z": row_z, "lanes": [], "cruise_speed": obstacle.cruise_speed, "half_length": obstacle.half_length}
		grouped[row_z].lanes.append(LANE_CENTERS.find(obstacle.position.x))
		grouped[row_z].half_length = maxf(grouped[row_z].half_length, obstacle.half_length)
	var rows: Array[Dictionary] = []
	for row in grouped.values():
		row.lanes.sort()
		rows.append(row)
	rows.sort_custom(func(first: Dictionary, second: Dictionary): return first.z > second.z)
	return rows


func _take_obstacle() -> RoadObstacle:
	for obstacle in obstacle_pool:
		if not obstacle.active:
			return obstacle
	var obstacle := Obstacle.new()
	add_child(obstacle)
	obstacle.player_hit.connect(_on_player_hit.bind(obstacle))
	obstacle.pothole_hit.connect(_on_pothole_hit.bind(obstacle))
	obstacle.roadworks_entered.connect(_on_roadworks_entered.bind(obstacle))
	obstacle.near_miss.connect(_on_near_miss)
	obstacle_pool.append(obstacle)
	return obstacle


func _on_player_hit(obstacle: RoadObstacle) -> void:
	last_hit_obstacle = obstacle
	player_hit.emit()


func _on_pothole_hit(obstacle: RoadObstacle) -> void:
	last_hit_obstacle = obstacle
	pothole_hit.emit()


func _on_roadworks_entered(obstacle: RoadObstacle) -> void:
	last_hit_obstacle = obstacle
	roadworks_entered.emit()


func _on_near_miss(points: int, clearance: float) -> void:
	near_miss.emit(points, clearance)
