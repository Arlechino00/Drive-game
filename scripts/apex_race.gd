extends RefCounted
## Race rules use driving time and the opponent's actual world-relative position.

const Tuning = preload("res://scripts/stage_two_tuning.gd")

const DURATION: float = 30.0
const COUNTDOWN_SECONDS: float = 3.0
const INITIAL_ACCELERATION: float = 48.0
const ENCOUNTER_SPEED: float = 14.0
const LAUNCH_DEFICIT_METERS: float = 80.0
const MIN_BOOST_SECONDS: float = 4.0
const MAX_BOOST_SECONDS: float = 7.0
const POINTS: int = 20000
const REWARD_SECONDS: float = 10.0
const SPEED_ADVANTAGE: float = 3.0
const BURST_ADVANTAGE: float = 4.0
const BRAKING_DECELERATION: float = 32.0
const BLOCK_DISTANCE: float = 28.0
const BLOCK_RELATIVE_SPEED: float = 3.5
const BLOCK_SECONDS: float = 0.7
const PASS_ADVANTAGE: float = 6.0
const RECOVERY_SECONDS: float = 1.2
const BURST_PERIOD: float = 10.0
const BURST_START: float = 6.0
const BURST_DURATION: float = 1.0
const LANE_CHANGE_SPEED: float = 12.0
const OVERTAKE_LOOKAHEAD: float = 80.0
const FOLLOWING_MARGIN: float = 0.8
const PLAN_STEP: float = 1.0 / 60.0
const CUT_MARGIN: float = 0.08
const POST_TURN_CHECK: float = 0.5
const ENCOUNTER_DISTANCE: float = 14.0

var active: bool = false
var elapsed: float = 0.0
var countdown_remaining: float = 0.0
var lead_m: float = 0.0
var boost_seconds: float = 0.0
var required_boost_seconds: float = MIN_BOOST_SECONDS
var clean: bool = true
var actor: RoadObstacle
var lane_target: float = 0.0
var ai_state: String = "CHASE"
var blocked_seconds: float = 0.0
var aggression: float = 0.0
var traffic_density: float = 0.0
var outcome_reason: String = ""
var _motion_start_z: float = NAN
var _motion_delta: float = 0.0
var _passing: bool = false
var _recovery_remaining: float = 0.0
var _last_speed: float = -1.0
var _blocked_side: float = 0.0
var _side_memory_remaining: float = 0.0


func set_difficulty(run_seconds: float, density: float = 1.0) -> void:
	# A modest advantage preserves a skilled driver's boost/traffic escape.
	aggression = clampf(maxf(0.0, run_seconds) / 1800.0, 0.0, 1.5)
	traffic_density = clampf(density, 0.0, 1.0)


func begin(opponent: RoadObstacle, _base_speed: float, boost_requirement: float = MIN_BOOST_SECONDS) -> void:
	reset()
	required_boost_seconds = clampf(boost_requirement, MIN_BOOST_SECONDS, MAX_BOOST_SECONDS)
	actor = opponent
	actor.racing = true
	# Keep its real encounter speed; prepare_opponent accelerates it smoothly.
	countdown_remaining = COUNTDOWN_SECONDS
	lead_m = actor.position.z
	lane_target = actor.position.x
	active = true


func prepare_opponent(delta: float, base_speed: float, player_x: float, traffic: Array[RoadObstacle], player_speed: float = -1.0) -> void:
	if not active or not is_instance_valid(actor) or not actor.active:
		return
	delta = maxf(0.0, delta)
	_motion_start_z = actor.position.z if delta > 0.0 else NAN
	_motion_delta = delta
	var burst_phase := fmod(elapsed, BURST_PERIOD)
	var bursting := burst_phase >= BURST_START and burst_phase < BURST_START + BURST_DURATION
	# Actual run speed permits close, physically clear front/rear cuts. The
	# compatibility default remains conservative for callers without telemetry.
	var observed_speed := player_speed if player_speed >= 0.0 else (DifficultyDirector.MAX_BOOST_SPEED if actor.position.z < 0.0 else 27.0)
	_recovery_remaining = maxf(0.0, _recovery_remaining - delta)
	_side_memory_remaining = maxf(0.0, _side_memory_remaining - delta)
	if _last_speed >= 0.0 and actor.cruise_speed < _last_speed - BRAKING_DECELERATION * delta - 1.0:
		_recovery_remaining = RECOVERY_SECONDS
	var side_extent := actor.half_width + actor.PLAYER_HALF_WIDTH + CUT_MARGIN
	var player_blocking := actor.position.z > 0.0 and actor.position.z < BLOCK_DISTANCE and absf(actor.position.x - player_x) < side_extent and absf(observed_speed - actor.cruise_speed) <= BLOCK_RELATIVE_SPEED
	blocked_seconds = blocked_seconds + delta if player_blocking else maxf(0.0, blocked_seconds - delta * 0.5)
	if blocked_seconds >= BLOCK_SECONDS / (1.0 + aggression * 0.4):
		_passing = true
	if actor.position.z < -actor.half_length - actor.PLAYER_HALF_LENGTH - FOLLOWING_MARGIN:
		_passing = false
		blocked_seconds = 0.0
	var chasing := actor.position.z > 0.0
	# A faster launch and independent chase headroom recover the real encounter
	# acceleration deficit within a race, even on the new rising cruise curve.
	var desired_speed := maxf(0.0, base_speed) + (PASS_ADVANTAGE if chasing else SPEED_ADVANTAGE) + aggression
	if bursting:
		# Brief attacks can exceed even the player's observed boosted speed.
		# Their finite duty cycle still leaves sustained boost a genuine escape.
		var burst_reference := maxf(base_speed, observed_speed) if chasing else base_speed
		desired_speed = maxf(desired_speed, burst_reference + BURST_ADVANTAGE + aggression)
	if _passing:
		# Passing power belongs to the rival, not the player's boost telemetry.
		# A clean boost escape must still create real separation.
		desired_speed = maxf(desired_speed, base_speed + PASS_ADVANTAGE + aggression)
	# Limit throttle during every race tick, including burst entry and recovery.
	var throttle_speed := move_toward(actor.cruise_speed, desired_speed, (get_acceleration(base_speed) if desired_speed > actor.cruise_speed else BRAKING_DECELERATION) * delta)
	var lookahead := OVERTAKE_LOOKAHEAD * (1.0 + traffic_density * 0.5) + base_speed * aggression * 0.3
	var gaps: Array[float] = [INF, INF, INF]
	for obstacle in traffic:
		if not obstacle.active or obstacle == actor:
			continue
		var ahead := actor.position.z - obstacle.position.z
		if ahead >= -actor.half_length - obstacle.half_length:
			var lane := ObstacleSpawner.LANE_CENTERS.find(obstacle.position.x)
			if lane >= 0:
				gaps[lane] = minf(gaps[lane], ahead)
	var current := clampi(roundi((actor.position.x + 5.0) / 5.0), 0, 2)
	var unsafe_target := not _lane_is_safe(lane_target, observed_speed, player_x, throttle_speed, traffic)
	if _passing and lane_target != actor.position.x and absf(lane_target - player_x) < side_extent and unsafe_target:
		# Remember a player who followed the previous passing side; try the
		# other opening next. Only observed positions influence this memory.
		_blocked_side = signf(lane_target)
		_side_memory_remaining = 2.0
	if gaps[current] < lookahead or not is_equal_approx(actor.position.x, lane_target) or unsafe_target or _passing:
		var best_score := -INF
		var best_target := actor.position.x
		for candidate in range(3):
			var candidate_x := ObstacleSpawner.LANE_CENTERS[candidate]
			if not _lane_is_safe(candidate_x, observed_speed, player_x, throttle_speed, traffic):
				continue
			# Both outer lanes are reachable through the center when that transit
			# is clear. Prefer a short detour and keep a safe committed turn.
			var score := minf(1000.0, gaps[candidate]) - absf(candidate_x - actor.position.x) * 0.01
			if candidate_x == lane_target:
				score += 0.05
			if _passing and absf(candidate_x - player_x) < side_extent:
				score -= 100.0
			if _passing and _side_memory_remaining > 0.0 and signf(candidate_x) == _blocked_side:
				score -= 1.0
			if score > best_score:
				best_score = score
				best_target = candidate_x
		lane_target = best_target
	var proposed_x := move_toward(actor.position.x, lane_target, LANE_CHANGE_SPEED * maxf(0.0, delta))
	var cruise := _traffic_speed(actor.position.x, proposed_x, actor.position.z, throttle_speed, delta, traffic, 0.0)
	# Validate this actual tick too: player steering or a long frame can change
	# the plan after commitment. Holding the turn is preferable to ramming.
	var next_z := actor.position.z + (observed_speed - cruise) * delta
	var player_extent := actor.half_width + actor.PLAYER_HALF_WIDTH + CUT_MARGIN
	if _swept_overlap(actor.position.x - player_x, proposed_x - player_x, player_extent, actor.position.z, next_z, actor.half_length + actor.PLAYER_HALF_LENGTH + CUT_MARGIN):
		if absf(proposed_x - player_x) < absf(actor.position.x - player_x):
			proposed_x = actor.position.x
			cruise = _traffic_speed(actor.position.x, proposed_x, actor.position.z, throttle_speed, delta, traffic, 0.0)
	# The player is also a physical leader. Emergency safety caps may brake
	# harder than normal throttle; acceleration never bypasses its bound.
	if actor.position.z > 0.0 and maxf(actor.position.x, proposed_x) > player_x - side_extent and minf(actor.position.x, proposed_x) < player_x + side_extent:
		var following_gap := actor.half_length + actor.PLAYER_HALF_LENGTH + FOLLOWING_MARGIN
		cruise = minf(cruise, observed_speed + maxf(0.0, actor.position.z - following_gap) / maxf(delta, 0.000001))
	ai_state = "CHASE"
	if _recovery_remaining > 0.0:
		ai_state = "RECOVER"
	elif not is_equal_approx(proposed_x, lane_target) or not is_equal_approx(actor.position.x, lane_target):
		ai_state = ("OVERTAKE_LEFT" if lane_target < actor.position.x else "OVERTAKE_RIGHT") if _passing else "AVOID_TRAFFIC"
	elif _passing:
		ai_state = "ATTACK" if absf(actor.position.x - player_x) >= side_extent else "PRESSURE"
	elif player_blocking:
		ai_state = "DRAFT"
	elif cruise < throttle_speed - 0.01:
		ai_state = "AVOID_TRAFFIC"
	actor.position.x = proposed_x
	actor.cruise_speed = cruise
	_last_speed = cruise


func get_acceleration(base_speed: float) -> float:
	# Bound the encounter's launch deficit rather than capping endless speed.
	# v_delta^2 / (2a) is the distance lost accelerating from encounter pace.
	var speed_gain := maxf(0.0, base_speed + PASS_ADVANTAGE - ENCOUNTER_SPEED)
	return maxf(INITIAL_ACCELERATION, speed_gain * speed_gain / (2.0 * LAUNCH_DEFICIT_METERS))


func _lane_is_safe(target_x: float, player_speed: float, player_x: float, desired_speed: float, traffic: Array[RoadObstacle]) -> bool:
	var duration := absf(target_x - actor.position.x) / LANE_CHANGE_SPEED + POST_TURN_CHECK
	var time := 0.0
	var x := actor.position.x
	# Simulate in the frame at the start of this tick. Forward motion decreases z;
	# only relative coordinates enter the swept-footprint collision checks.
	var z := actor.position.z
	while time < duration - 0.000000001:
		var step := minf(PLAN_STEP, duration - time)
		var next_x := move_toward(x, target_x, LANE_CHANGE_SPEED * step)
		var cruise := _traffic_speed(x, next_x, z, desired_speed, step, traffic, time)
		var next_z := z - cruise * step
		var side_extent := actor.half_width + actor.PLAYER_HALF_WIDTH + CUT_MARGIN
		var long_extent := actor.half_length + actor.PLAYER_HALF_LENGTH + CUT_MARGIN
		if _swept_overlap(x - player_x, next_x - player_x, side_extent, z + player_speed * time, next_z + player_speed * (time + step), long_extent):
			return false
		for obstacle in traffic:
			if not obstacle.active or obstacle == actor:
				continue
			var obstacle_z := obstacle.position.z - obstacle.cruise_speed * time
			var obstacle_next_z := obstacle.position.z - obstacle.cruise_speed * (time + step)
			var obstacle_x := _traffic_x_at(obstacle, time)
			var obstacle_next_x := _traffic_x_at(obstacle, time + step)
			if _swept_overlap(x - obstacle_x, next_x - obstacle_next_x, actor.half_width + obstacle.half_width + CUT_MARGIN, z - obstacle_z, next_z - obstacle_next_z, actor.half_length + obstacle.half_length + CUT_MARGIN):
				return false
		x = next_x
		z = next_z
		time += step
	return true


func _traffic_speed(from_x: float, to_x: float, at_z: float, desired_speed: float, delta: float, traffic: Array[RoadObstacle], future_time: float) -> float:
	var cruise := desired_speed
	for obstacle in traffic:
		if not obstacle.active or obstacle == actor:
			continue
		var side_extent := actor.half_width + obstacle.half_width + CUT_MARGIN
		var obstacle_x := _traffic_x_at(obstacle, future_time)
		var obstacle_next_x := _traffic_x_at(obstacle, future_time + delta)
		if maxf(from_x, to_x) <= minf(obstacle_x, obstacle_next_x) - side_extent or minf(from_x, to_x) >= maxf(obstacle_x, obstacle_next_x) + side_extent:
			continue
		var ahead := at_z - (obstacle.position.z - obstacle.cruise_speed * future_time)
		if ahead < 0.0:
			continue
		var following_gap := actor.half_length + obstacle.half_length + FOLLOWING_MARGIN
		cruise = minf(cruise, obstacle.cruise_speed + maxf(0.0, ahead - following_gap) / maxf(delta, 0.000001))
	return cruise


func _traffic_x_at(obstacle: RoadObstacle, time: float) -> float:
	# Extrapolate the current visible merge only; do not anticipate future
	# random traffic decisions or invent a lane change that has not begun.
	return move_toward(obstacle.position.x, obstacle.lane_target, Tuning.TRAFFIC_LANE_SPEED * time) if obstacle.changing_lane else obstacle.position.x


func _swept_overlap(side_start: float, side_end: float, side_extent: float, z_start: float, z_end: float, z_extent: float) -> bool:
	var side_times := _overlap_times(side_start, side_end, side_extent)
	var z_times := _overlap_times(z_start, z_end, z_extent)
	return maxf(side_times.x, z_times.x) <= minf(side_times.y, z_times.y)


func _overlap_times(start: float, end: float, extent: float) -> Vector2:
	if is_equal_approx(start, end):
		return Vector2(0.0, 1.0) if absf(start) <= extent else Vector2(INF, -INF)
	var first := (-extent - start) / (end - start)
	var last := (extent - start) / (end - start)
	return Vector2(maxf(0.0, minf(first, last)), minf(1.0, maxf(first, last)))

func advance(delta: float, boosting: bool) -> int:
	var motion_start := _motion_start_z
	var motion_delta := _motion_delta
	_motion_start_z = NAN
	_motion_delta = 0.0
	if not active:
		return 0
	var driving_delta := maxf(0.0, delta)
	var countdown_delta := minf(driving_delta, countdown_remaining)
	countdown_remaining = maxf(0.0, countdown_remaining - countdown_delta)
	if countdown_remaining < 0.000000001:
		countdown_remaining = 0.0
	var race_delta := minf(driving_delta - countdown_delta, remaining())
	elapsed = minf(DURATION, elapsed + race_delta)
	if boosting:
		boost_seconds += race_delta
	lead_m = actor.position.z
	if elapsed < DURATION - 0.000000001:
		return 0
	# World motion is applied for the complete frame before this clock updates.
	# Resolve at the exact finish instant, so a subsequent overtake in a long
	# frame cannot rewrite the winner. Direct rule callers have no motion sample.
	var finish_delta := countdown_delta + race_delta
	if finish_delta < driving_delta and not is_nan(motion_start) and is_equal_approx(motion_delta, driving_delta):
		lead_m = lerpf(motion_start, actor.position.z, finish_delta / driving_delta)
	active = false
	if is_zero_approx(lead_m):
		outcome_reason = "tied"
	elif lead_m < 0.0:
		outcome_reason = "ahead"
	elif not clean:
		outcome_reason = "pothole"
	elif boost_seconds < required_boost_seconds - 0.000000001:
		outcome_reason = "boost"
	else:
		outcome_reason = "won"
	return 1 if outcome_reason == "won" else -1


func hit_pothole() -> void:
	if active:
		clean = false


func remaining() -> float:
	return maxf(0.0, DURATION - elapsed)


func reset() -> void:
	if is_instance_valid(actor):
		actor.racing = false
	actor = null
	active = false
	elapsed = 0.0
	countdown_remaining = 0.0
	lead_m = 0.0
	boost_seconds = 0.0
	required_boost_seconds = MIN_BOOST_SECONDS
	clean = true
	lane_target = 0.0
	ai_state = "CHASE"
	blocked_seconds = 0.0
	aggression = 0.0
	traffic_density = 0.0
	outcome_reason = ""
	_motion_start_z = NAN
	_motion_delta = 0.0
	_passing = false
	_recovery_remaining = 0.0
	_last_speed = -1.0
	_blocked_side = 0.0
	_side_memory_remaining = 0.0
