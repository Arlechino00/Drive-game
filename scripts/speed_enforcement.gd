class_name SpeedEnforcement
extends RefCounted
## Distance-based traps use a separate RNG so traffic seeds retain their layouts.

const WARNING_DISTANCE: float = 320.0
const MIN_CHASE_SECONDS: float = 8.0
const MAX_CHASE_SECONDS: float = 16.0
const SECTOR_LIMITS: Array[int] = [30, 50, 70, 80, 90, 120, 130, 200]
const RADAR_CHANCE: float = 0.65

var current_limit: int = 0
var next_limit: int = 80
var sector_at: float = 0.0
var sector_end: float = 0.0
var radar_at: float = 0.0
var radar_pending: bool = true
var fine_points: int = 0
var random := RandomNumberGenerator.new()
var _chase_random := RandomNumberGenerator.new()
var _previous_distance: float = 0.0
var _warning_announced: bool = false
var warning_distance := WARNING_DISTANCE
var run_seconds := 0.0
var approach_speed := 0.0


func configure_progression(speed: float, seconds: float, brake_deceleration: float = 7.0) -> void:
	approach_speed = maxf(0.0, speed)
	run_seconds = maxf(0.0, seconds)
	var legal_speed := float(next_limit) / 3.6
	# Warning gives a full theoretical braking distance plus one second to react.
	warning_distance = maxf(WARNING_DISTANCE, maxf(0.0, approach_speed * approach_speed - legal_speed * legal_speed) / (2.0 * maxf(0.1, brake_deceleration)) + approach_speed)


func reset(run_seed: int, at_distance: float = 0.0) -> void:
	random.seed = run_seed ^ 0x52414441
	_chase_random.seed = run_seed ^ 0x43484153
	current_limit = 0
	fine_points = 0
	_previous_distance = at_distance
	warning_distance = WARNING_DISTANCE
	run_seconds = 0.0
	approach_speed = 0.0
	_schedule(at_distance, true)


func advance(distance: float, previous_speed: float, speed: float) -> Dictionary:
	var event := {"checked": false, "fine": 0, "chase_seconds": 0.0}
	if distance < _previous_distance:
		return event
	# Process boundaries in order, including delayed ticks crossing a whole trap.
	while true:
		if radar_pending and not _warning_announced and distance >= radar_at - warning_distance:
			_warning_announced = true
			event.warning = true
			event.warning_limit = next_limit
		if distance >= sector_at:
			current_limit = next_limit
		if radar_pending and distance >= radar_at:
			radar_pending = false
			event.checked = true
			var fraction := clampf((radar_at - _previous_distance) / maxf(0.000001, distance - _previous_distance), 0.0, 1.0)
			var measured := maxf(0.0, lerpf(previous_speed, speed, fraction)) * 3.6
			# Floating point equality at the posted limit is a legal pass.
			if measured > float(next_limit) + 0.00001:
				var points := 100 + ceili((measured - next_limit) * 10.0)
				fine_points += points
				event.fine += points
				var duration := _chase_random.randf_range(MIN_CHASE_SECONDS, MAX_CHASE_SECONDS)
				if event.chase_seconds == 0.0:
					event.chase_seconds = duration
					event.crossing_fraction = fraction
				event.limit = next_limit
				event.measured_kmh = measured
		if distance < sector_end:
			break
		current_limit = 0
		_schedule(sector_end, false)
	_previous_distance = distance
	return event


func _schedule(after_distance: float, first: bool) -> void:
	next_limit = SECTOR_LIMITS[random.randi_range(0, SECTOR_LIMITS.size() - 1)]
	var spacing := random.randf_range(1200.0, 1800.0 if first else 2200.0)
	# Later traps appear more often in time as real speed rises. Maintain braking
	# distance for even the lowest possible new limit; don't move existing traps.
	var braking_budget := approach_speed * approach_speed / 14.0 + approach_speed
	sector_at = after_distance + maxf(spacing, braking_budget + 120.0)
	var camera_at := sector_at + random.randf_range(80.0, 120.0)
	sector_end = camera_at + random.randf_range(60.0, 100.0)
	radar_pending = random.randf() < minf(0.92, RADAR_CHANCE + run_seconds / 9000.0)
	radar_at = camera_at if radar_pending else INF
	_warning_announced = false
