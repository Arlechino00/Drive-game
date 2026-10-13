class_name ObstacleSpawner
extends Node3D

signal player_hit
signal pothole_hit
signal roadworks_entered
signal near_miss(points: int, clearance: float)

const Obstacle = preload("res://scripts/obstacle.gd")
const Models = preload("res://scripts/traffic_models.gd")
const Tuning = preload("res://scripts/stage_two_tuning.gd")
const LANE_CENTERS: Array[float] = [-5.0, 0.0, 5.0]
const SPAWN_AHEAD: float = 285.0
# Police units chase from up to escape_gap (100 m) behind; keep traffic alive
# until they pass it so traffic-based escapes remain possible.
const REAR_RETIRE_DISTANCE: float = 112.0
# At 100m/s, these leave at least 0.7s between actual vehicle footprints
# even for 30km/h traffic or two twelve-meter work sites.
const MIN_ROW_SPACING: float = 80.0
const STATIC_ROW_SPACING: float = 96.0
const TRAFFIC_DRAIN_Z: float = -96.0
const MAX_POOL_SIZE: int = 20
const TRAFFIC_ACCELERATION: float = 8.0
const APEX_WEIGHT: float = 0.06
const APEX_FIRST_DISTANCE: float = 1800.0
const APEX_SPACING: float = 2500.0
const MOTO_CHANCE: float = 0.06
# A motorcycle cuts into the player's lane this many seconds ahead of them.
const MOTO_CUT_SECONDS: float = 2.4

enum Wave { TRAFFIC, WAIT_FOR_STATIC, STATIC, WAIT_FOR_TRAFFIC }

var obstacle_pool: Array[RoadObstacle] = []
var next_row_at: float = 70.0
var last_safe_lane: int = 1
var random: RandomNumberGenerator = RandomNumberGenerator.new()
# Separate stream so motorcycles never shift seeded traffic layouts.
var _moto_random := RandomNumberGenerator.new()
var active_seed: int = 0
var relative_distance: float = 0.0
var traffic_speed: float = Obstacle.TRAFFIC_SPEED
var _target_traffic_speed: float = Obstacle.TRAFFIC_SPEED
var last_hit_obstacle: RoadObstacle
var spawning_enabled: bool = true
var motion_enabled: bool = true
var _generation_epoch: int = 0
var _wave: int = Wave.TRAFFIC
var _rows_left: int = 0
var _next_row_z: float = -70.0
var race_actor: RoadObstacle
var pursuit: PolicePursuit
var _total_run_distance: float = 0.0
var _next_apex_distance: float = APEX_FIRST_DISTANCE
var spawn_ahead: float = SPAWN_AHEAD
var player_speed: float = 0.0
var run_seconds: float = 0.0
var _mixed_wave: bool = false
var _reserved_lane: int = 0
var _stage_two_enabled: bool = false
var _traffic_plan_remaining: float = 0.0


func reset_spawner(run_seed: int = -1) -> void:
	_generation_epoch += 1
	race_actor = null
	_total_run_distance = 0.0
	_next_apex_distance = APEX_FIRST_DISTANCE
	spawn_ahead = SPAWN_AHEAD
	player_speed = 0.0
	run_seconds = 0.0
	_mixed_wave = false
	_stage_two_enabled = false
	_traffic_plan_remaining = 0.0
	motion_enabled = true
	for obstacle in obstacle_pool:
		obstacle.deactivate()
	next_row_at = 70.0
	last_safe_lane = 1
	relative_distance = 0.0
	traffic_speed = Obstacle.TRAFFIC_SPEED
	_target_traffic_speed = Obstacle.TRAFFIC_SPEED
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
	_moto_random.seed = active_seed ^ 0x4d4f544f
	_rows_left = random.randi_range(6, 9)
	advance(0.0, 0.0, 0.0)


func set_speed_limit(limit_kmh: int) -> void:
	_target_traffic_speed = float(limit_kmh) / 3.6 if limit_kmh > 0 else Obstacle.TRAFFIC_SPEED
	if limit_kmh == 0 and _stage_two_enabled:
		_target_traffic_speed += 18.0 * (1.0 - exp(-run_seconds / 1800.0))


func configure_progression(speed: float, seconds: float) -> void:
	_stage_two_enabled = true
	player_speed = maxf(0.0, speed)
	run_seconds = maxf(0.0, seconds)
	spawn_ahead = clampf(maxf(SPAWN_AHEAD, player_speed * Tuning.LOOK_AHEAD_SECONDS), SPAWN_AHEAD, Tuning.LOOK_AHEAD_MAX)


func _row_spacing(stationary: bool, intensity: float) -> float:
	var original := STATIC_ROW_SPACING if stationary else lerpf(86.0, MIN_ROW_SPACING, intensity)
	var closing := player_speed if stationary else maxf(0.0, player_speed - traffic_speed)
	# Includes the combined lengths of two work sites and the player. The adjacent
	# route is reachable even at 400+ km/h without raising density blindly.
	var footprint := 20.0 if stationary else 12.0
	return maxf(original, closing * Tuning.REACTION_SECONDS + footprint)


func advance(distance_delta: float, _total_distance: float, difficulty: float, delta: float = 0.0, player_x: float = 0.0) -> void:
	if not motion_enabled:
		return
	var generation_epoch := _generation_epoch
	_total_run_distance = _total_distance
	var contacted := false
	traffic_speed = move_toward(traffic_speed, _target_traffic_speed, TRAFFIC_ACCELERATION * maxf(0.0, delta))
	if _mixed_wave and race_actor == null:
		_update_traffic_ai(delta, player_x)
		_prepare_mixed_motion(delta)
	var relative_delta := distance_delta - traffic_speed * delta
	relative_distance += relative_delta
	if _wave not in [Wave.WAIT_FOR_STATIC, Wave.WAIT_FOR_TRAFFIC]:
		_next_row_z += distance_delta if _wave == Wave.STATIC else relative_delta
	for obstacle in obstacle_pool:
		# A common eased speed preserves row spacing while the sector changes.
		# The race controller owns Apex speed; road hazards remain stationary.
		if obstacle.active and obstacle != race_actor and not obstacle.racing and obstacle.kind >= Obstacle.Kind.CAR and obstacle.kind <= Obstacle.Kind.WIDE:
			if _mixed_wave:
				obstacle.cruise_speed = _safe_following_speed(obstacle, maxf(0.0, delta))
				obstacle.position.x = obstacle.motion_x
				obstacle.changing_lane = not is_equal_approx(obstacle.position.x, obstacle.lane_target)
			else:
				obstacle.cruise_speed = traffic_speed
	_update_motorcycles(maxf(0.0, delta), player_x)
	# Apex planned against last tick's traffic speeds; a leader that braked this
	# tick would otherwise be overlapped during long steps.
	_cap_race_actor_speed(maxf(0.0, delta))
	for obstacle in obstacle_pool:
		if obstacle.active:
			var activation_serial := obstacle._activation_serial
			var movement := distance_delta - obstacle.cruise_speed * delta
			if obstacle.advance_pass(movement, player_x):
				contacted = true
				# An ended/reset run or a newly reused actor belongs to the callback.
				if not motion_enabled or generation_epoch != _generation_epoch or not is_instance_valid(obstacle) or activation_serial != obstacle._activation_serial:
					return
				# A surviving impact still advances the other actors in the row.
				continue
			if (obstacle.position.z > REAR_RETIRE_DISTANCE or obstacle.position.z < -spawn_ahead - STATIC_ROW_SPACING) and obstacle != race_actor:
				obstacle.retire()
	# Keep the just-hit actor retired until queued Area notifications flush.
	if contacted or not spawning_enabled:
		return
	var intensity := clampf(difficulty, 0.0, 1.0)
	if _wave == Wave.WAIT_FOR_TRAFFIC:
		# Begin a reserved-corridor wave only after static actors have cleared;
		# otherwise an old worksite could still occupy that corridor.
		if _wave_has_actors():
			return
		_wave = Wave.TRAFFIC
		# Racing uses ordinary single-car rows; mixed snapshots are disabled
		# while the race controller owns the opponent's movement.
		_mixed_wave = race_actor == null
		_reserved_lane = 0 if last_safe_lane <= 1 else 2
		_rows_left = random.randi_range(6, 9)
		_next_row_z = -spawn_ahead
	# Brakes can drop below traffic speed. Wait for the old wave to clear
	# completely: catch-time spacing based on a minimum 27 m/s is no longer safe.
	if _wave == Wave.WAIT_FOR_STATIC:
		if _wave_has_actors(true):
			return
		_wave = Wave.STATIC
		_mixed_wave = false
		_rows_left = random.randi_range(3, 5)
		_next_row_z = -spawn_ahead
	if _wave == Wave.TRAFFIC and not _wave_has_actors() and _next_row_z < -spawn_ahead:
		# Rebase after a prolonged slow interval instead of repaying its distance.
		_next_row_z = -spawn_ahead
	while _next_row_z >= -spawn_ahead:
		# A long frame or disabled generation can exhaust the old schedule.
		# New encounters must still appear ahead instead of at the player.
		# The actual game speed is constrained by the finite reaction budget.
		# Defensive direct callers above that budget still receive real traffic
		# at the preview edge instead of silently losing every future row.
		var minimum_spawn_distance := minf(spawn_ahead, maxf(70.0, player_speed * Tuning.MIN_SPAWN_SECONDS))
		_next_row_z = minf(_next_row_z, -minimum_spawn_distance)
		var spacing := _row_spacing(_wave == Wave.STATIC, intensity)
		# Schedule behind the actual farthest encounter, including the prior
		# wave. Static→traffic gaps subsequently widen instead of compressing.
		var farthest_z := _farthest_ahead_z()
		if farthest_z != INF:
			_next_row_z = minf(_next_row_z, farthest_z - spacing)
		if _next_row_z < -spawn_ahead or MAX_POOL_SIZE - get_active_count() < 2:
			break
		_spawn_row(_next_row_z, intensity, player_x, _wave == Wave.STATIC)
		_next_row_z -= spacing
		_rows_left -= 1
		if _rows_left == 0:
			if _wave == Wave.TRAFFIC:
				_wave = Wave.WAIT_FOR_STATIC
				break
			if _stage_two_enabled and run_seconds >= Tuning.MIXED_ROWS_AFTER_SECONDS:
				_wave = Wave.WAIT_FOR_TRAFFIC
				break
			_wave = Wave.TRAFFIC
			_mixed_wave = false
			_rows_left = random.randi_range(6, 9)
	next_row_at = relative_distance - _next_row_z


func get_active_count() -> int:
	var count := 0
	for obstacle in obstacle_pool:
		if obstacle.active:
			count += 1
	return count


func _wave_has_actors(moving_only: bool = false) -> bool:
	# Apex persists across ordinary waves. It still occupies its pool slot, but
	# must not prevent drained traffic/static waves from generating new rows.
	for obstacle in obstacle_pool:
		if obstacle.active and obstacle != race_actor and (not moving_only or obstacle.cruise_speed > 0.0):
			return true
	return false


func _spawn_row(row_z: float, difficulty: float, player_x: float, stationary: bool = false) -> void:
	if _mixed_wave and not stationary and race_actor == null:
		# Mixed speed rows reserve one continuous outside corridor. Only one car
		# per row may overtake; paired rows keep the proven common-speed schedule.
		last_safe_lane = _reserved_lane
		var lane := random.randi_range(1, 2) if _reserved_lane == 0 else random.randi_range(0, 1)
		_activate_encounter(lane, row_z, player_x, -1)
		return
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
		elif race_actor == null and _moto_random.randf() < MOTO_CHANCE:
			model = Models.Model.MOTO
		chosen_kind = Models.kind_for_model(model)
	var obstacle := _take_obstacle()
	obstacle.activate(Vector3(LANE_CENTERS[lane_index], 0.0, row_z), chosen_kind, player_x, model)
	if chosen_kind >= Obstacle.Kind.CAR and chosen_kind <= Obstacle.Kind.WIDE:
		obstacle.cruise_speed = traffic_speed
		if _mixed_wave and model != Models.Model.APEX:
			obstacle.speed_factor = random.randf_range(0.85, 1.3)


func _update_motorcycles(delta: float, player_x: float) -> void:
	for bike in obstacle_pool:
		if not bike.active or bike.model_id != Models.Model.MOTO or bike.racing:
			continue
		if not _mixed_wave:
			# Mixed waves move lanes through motion_x; ordinary waves do it here.
			bike.position.x = move_toward(bike.position.x, bike.lane_target, Tuning.TRAFFIC_LANE_SPEED * delta)
			bike.changing_lane = not is_equal_approx(bike.position.x, bike.lane_target)
		var ahead := -bike.position.z
		var closing := player_speed - bike.cruise_speed
		# Never cut in when the player isn't catching up or is already too close.
		if bike.cut_in_done or closing <= 1.0 or ahead < 20.0 or ahead > closing * MOTO_CUT_SECONDS:
			continue
		bike.cut_in_done = true
		var target_lane := clampi(roundi((player_x + 5.0) / 5.0), 0, 2)
		var target: float = LANE_CENTERS[target_lane]
		# Mixed waves keep one corridor permanently open; never cut into it.
		if is_equal_approx(target, bike.position.x) or (_mixed_wave and target_lane == _reserved_lane):
			continue
		var clear := true
		for other in obstacle_pool:
			if other.active and other != bike and absf(other.position.z - bike.position.z) < bike.half_length + other.half_length + 12.0 and absf(other.position.x - target) < bike.half_width + other.half_width + 0.5:
				clear = false
				break
		if clear:
			bike.lane_target = target


func _update_traffic_ai(delta: float, player_x: float) -> void:
	_traffic_plan_remaining -= maxf(0.0, delta)
	if _traffic_plan_remaining > 0.0:
		return
	_traffic_plan_remaining = 0.25
	for actor in obstacle_pool:
		if not actor.active or actor.racing or actor.cruise_speed <= 0.0 or actor.changing_lane:
			continue
		if actor.position.z > -maxf(65.0, player_speed * 1.0):
			continue
		for front in obstacle_pool:
			if not front.active or front == actor or front.cruise_speed <= 0.0:
				continue
			var ahead := actor.position.z - front.position.z
			if ahead < 0.0 or ahead > maxf(70.0, actor.cruise_speed * 3.0) or absf(actor.position.x - front.position.x) > actor.half_width + front.half_width:
				continue
			if actor.speed_factor <= front.speed_factor:
				continue
			var lane := clampi(roundi((actor.position.x + 5.0) / 5.0), 0, 2)
			var other := 3 - _reserved_lane - lane
			var candidate := LANE_CENTERS[other]
			var duration := absf(candidate - actor.position.x) / Tuning.TRAFFIC_LANE_SPEED + 1.0
			var clear := true
			for obstacle in obstacle_pool:
				if not obstacle.active or obstacle == actor:
					continue
				# Conservative envelope covers the full lateral turn, rear traffic,
				# and relative movement through the planning horizon.
				var side := obstacle.position.x >= minf(candidate, actor.position.x) - actor.half_width - obstacle.half_width and obstacle.position.x <= maxf(candidate, actor.position.x) + actor.half_width + obstacle.half_width
				var gap := absf(obstacle.position.z - actor.position.z)
				if side and gap < actor.half_length + obstacle.half_length + absf(actor.cruise_speed - obstacle.cruise_speed) * duration + 12.0:
					clear = false
					break
			if clear and absf(player_x - candidate) > actor.half_width + actor.PLAYER_HALF_WIDTH:
				actor.lane_target = candidate
			else:
				actor.cruise_speed = minf(actor.cruise_speed, front.cruise_speed + maxf(0.0, ahead - actor.half_length - front.half_length - 10.0) / 2.0)
			break


func _prepare_mixed_motion(delta: float) -> void:
	# Snapshot before any actor moves. Safety must also run near the player where
	# planning new overtakes is disabled. No per-frame containers are allocated.
	for actor in obstacle_pool:
		actor.motion_position = actor.position
		actor.motion_x = move_toward(actor.position.x, actor.lane_target, Tuning.TRAFFIC_LANE_SPEED * maxf(0.0, delta))
		actor.motion_speed = move_toward(actor.cruise_speed, traffic_speed * actor.speed_factor, TRAFFIC_ACCELERATION * maxf(0.0, delta))
	for actor in obstacle_pool:
		if not actor.active or actor.racing:
			continue
		if not _police_merge_clear(actor, maxf(0.0, delta)):
			# Hold the turn before traffic moves; keep its target for a later retry.
			actor.motion_x = actor.motion_position.x
		for other in obstacle_pool:
			if not other.active or other == actor:
				continue
			var side_extent := actor.half_width + other.half_width + 0.05
			var longitudinal := actor.half_length + other.half_length + absf(actor.motion_speed - other.motion_speed) * delta + 0.5
			if absf(actor.motion_position.z - other.motion_position.z) >= longitudinal:
				continue
			var other_min := minf(other.motion_position.x, other.motion_x)
			var other_max := maxf(other.motion_position.x, other.motion_x)
			if minf(actor.motion_position.x, actor.motion_x) < other_max + side_extent and maxf(actor.motion_position.x, actor.motion_x) > other_min - side_extent:
				actor.motion_x = actor.motion_position.x


func _police_merge_clear(actor: RoadObstacle, delta: float) -> bool:
	if not is_instance_valid(pursuit) or not pursuit.active or is_equal_approx(actor.motion_x, actor.motion_position.x):
		return true
	# Both systems use the same moving road frame. Current velocity plus bounded
	# throttle/braking and steering encloses police motion during this tick.
	# Read the existing three-unit dictionaries rather than allocate snapshots.
	var lateral_motion := pursuit.lateral_response * delta
	var speed_motion := 0.5 * maxf(pursuit.acceleration, pursuit.braking) * delta * delta
	for unit in pursuit.units:
		var gap := actor.motion_position.z - float(unit.z)
		var next_gap := gap + (maxf(0.0, float(unit.speed)) - actor.motion_speed) * delta
		var longitudinal := actor.half_length + PolicePursuit.HALF_LENGTH + speed_motion + 0.1
		if minf(gap, next_gap) > longitudinal or maxf(gap, next_gap) < -longitudinal:
			continue
		var side := actor.half_width + PolicePursuit.HALF_WIDTH + lateral_motion + 0.05
		if minf(actor.motion_position.x, actor.motion_x) < float(unit.x) + side and maxf(actor.motion_position.x, actor.motion_x) > float(unit.x) - side:
			return false
	return true


func _safe_following_speed(actor: RoadObstacle, delta: float, depth: int = 0) -> float:
	if delta <= 0.0 or depth >= MAX_POOL_SIZE:
		return actor.motion_speed
	var leader: RoadObstacle
	var gap := INF
	for other in obstacle_pool:
		if not other.active or other == actor:
			continue
		var ahead := actor.motion_position.z - other.motion_position.z
		if ahead <= 0.0 or ahead >= gap:
			continue
		var extent := actor.half_width + other.half_width + 0.05
		if maxf(actor.motion_position.x, actor.motion_x) <= minf(other.motion_position.x, other.motion_x) - extent or minf(actor.motion_position.x, actor.motion_x) >= maxf(other.motion_position.x, other.motion_x) + extent:
			continue
		leader = other
		gap = ahead
	if leader == null:
		return actor.motion_speed
	# The forward-only dependency cannot cycle. Predict the leader's own braking,
	# so pool iteration order cannot let followers pass through a braking queue.
	var leader_speed := _safe_following_speed(leader, delta, depth + 1)
	var bumper_gap := actor.half_length + leader.half_length + 0.1
	return minf(actor.motion_speed, leader_speed + maxf(0.0, gap - bumper_gap) / delta)


func _cap_race_actor_speed(delta: float) -> void:
	if delta <= 0.0 or not is_instance_valid(race_actor) or not race_actor.active:
		return
	for other in obstacle_pool:
		if not other.active or other == race_actor:
			continue
		var ahead := race_actor.position.z - other.position.z
		if ahead <= 0.0:
			continue
		var extent := race_actor.half_width + other.half_width
		if absf(race_actor.position.x - other.position.x) >= extent:
			continue
		var bumper_gap := race_actor.half_length + other.half_length + 0.1
		race_actor.cruise_speed = minf(race_actor.cruise_speed, other.cruise_speed + maxf(0.0, ahead - bumper_gap) / delta)


func finish_race() -> void:
	if is_instance_valid(race_actor):
		race_actor.deactivate()
	race_actor = null


func begin_race(actor: RoadObstacle) -> void:
	race_actor = actor
	_mixed_wave = false
	for obstacle in obstacle_pool:
		obstacle.speed_factor = 1.0
		obstacle.lane_target = obstacle.position.x
		obstacle.changing_lane = false
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
		grouped[row_z].lanes.append(clampi(roundi((obstacle.position.x + 5.0) / 5.0), 0, 2))
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
