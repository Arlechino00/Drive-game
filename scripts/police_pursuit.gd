class_name PolicePursuit
extends Node3D
## Explicitly advanced, bounded police actors. Positions use the moving road frame.

signal caught
signal escaped

const PoliceVisual = preload("res://scripts/police_aftermath.gd")
const Player = preload("res://scripts/player_car.gd")
const MAX_UNITS := 3
const HALF_WIDTH := 1.2
const HALF_LENGTH := 2.65
const LANES: Array[float] = [-5.0, 0.0, 5.0]
# Metres/second above the driver's actual speed while closing on a clear road.
const ROLE_SPEED: Dictionary = {"patrol": 5.0, "pursuit": 6.0, "interceptor": 8.0, "heavy": 4.0}

@export var initial_gap: float = 64.0
@export var capture_gap: float = 7.0
@export var escape_gap: float = 100.0
@export var clean_escape_seconds: float = 5.0
@export var capture_seconds: float = 5.0
@export var capture_decay: float = 0.12
@export var approach_grace_seconds: float = 3.0
@export var grace_approach_speed: float = 4.0
@export var lateral_response: float = 2.5
# Sustain a clear-road closing advantage through the driver's 16 m/s² boost.
@export var acceleration: float = 18.0
@export var braking: float = 18.0
@export var lane_change_speed_loss: float = 11.0
@export var heavy_lane_change_speed_loss: float = 14.0

var active: bool = false
# The live introduction demonstrates finite physical separation at gentle speed.
var training_escape: bool = false
var heat: int = 0
var units: Array[Dictionary] = []
var capture_fraction: float = 0.0
var slowdown_fraction: float = 0.0
var disengagement_seconds: float = 0.0
var clean_seconds: float = 0.0
# Retain radar integration signature; radar duration is no longer an escape timer.
var timed_chase: bool = false
var chase_duration: float = 5.0
var gap_m: float:
	get:
		var closest := INF
		for unit in units:
			closest = minf(closest, absf(unit.z))
		return closest if active and not units.is_empty() else _last_gap
	set(value):
		_last_gap = maxf(0.0, value)
		if not units.is_empty():
			units[0].z = _last_gap

var _last_gap := 0.0
var _elapsed: float = 0.0
var _generation: int = 0
var _escape_queued: bool = false
var _visual: PoliceAftermath
var _visuals: Array[PoliceAftermath] = []
var _rear_view: SubViewport
var _rear_camera: Camera3D

func _ready() -> void:
	for index in range(MAX_UNITS):
		var visual := PoliceVisual.new()
		visual.name = "PoliceVisual" if index == 0 else "PoliceVisual%d" % index
		add_child(visual)
		_visuals.append(visual)
	_visual = _visuals[0]
	_rear_view = SubViewport.new()
	_rear_view.name = "RearView"
	_rear_view.size = Vector2i(384, 160)
	_rear_view.own_world_3d = false
	_rear_view.world_3d = get_world_3d()
	_rear_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_rear_view)
	_rear_camera = Camera3D.new()
	_rear_camera.name = "RearCamera"
	_rear_camera.near = 0.1
	_rear_camera.far = 180.0
	_rear_view.add_child(_rear_camera)
	_rear_camera.current = true
	reset_pursuit()

func set_heat(value: int) -> void:
	heat = clampi(value, 0, 6)
	# Existing units retain position and momentum on escalation.
	if active:
		_set_roles()

func begin(player_at: Vector3, _duration: float = 0.0) -> void:
	reset_pursuit()
	active = true
	visible = true
	chase_duration = clean_escape_seconds
	_add_units(player_at.x)
	_rear_view.world_3d = get_world_3d()
	_rear_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for index in range(units.size()):
		_visuals[index].start_roadworks(player_at)
	_update_visual(0.0, player_at, 1.0)

func _add_units(player_x: float) -> void:
	var count := 1 if heat < 2 else (2 if heat < 4 else MAX_UNITS)
	for index in range(units.size(), count):
		# Reinforcements enter visibly from behind, never beside the hero.
		units.append({"role": "patrol", "x": clampf(player_x + float(index) * 3.0, -5.0, 5.0), "z": initial_gap + float(index) * 18.0, "speed": -1.0, "state": "approach", "contact": false})
	_set_roles()

func _set_roles() -> void:
	for index in range(units.size()):
		units[index].role = "patrol" if heat == 0 else "pursuit"
		if heat >= 2 and index == 0:
			units[index].role = "interceptor"
		if heat >= 4 and index == units.size() - 1:
			units[index].role = "heavy"

func report_radar() -> void:
	if not active:
		return
	register_mistake()
	var previous := units.size()
	_add_units(float(units[0].x))
	for index in range(previous, units.size()):
		_visuals[index].start_roadworks(Vector3(float(units[index].x), 0.0, 0.0))

func advance(delta: float, player_at: Vector3, speed: float, base_speed: float, effects: float = 1.0, traffic: Array[RoadObstacle] = []) -> void:
	if not active or delta <= 0.0:
		return
	var remaining := delta
	while active and remaining > 0.000000001:
		var step := minf(remaining, 1.0 / 60.0)
		_elapsed += step
		clean_seconds += step
		var pressure := 0.0
		var contact := false
		for index in range(units.size()):
			_advance_unit(units[index], index, step, player_at, maxf(0.0, speed), maxf(0.0, base_speed), traffic, remaining)
			var unit := units[index]
			var lateral: float = absf(float(unit.x) - player_at.x)
			var longitudinal: float = absf(float(unit.z))
			if longitudinal <= capture_gap and lateral <= HALF_WIDTH + Player.COLLISION_SIZE.x * 0.5 + 0.6:
				pressure = maxf(pressure, 1.0 if speed < base_speed * 0.7 or unit.contact else 0.35)
			contact = contact or unit.contact
		if units.size() > 1 and _boxed(player_at.x):
			pressure = 1.0
		capture_fraction = clampf(capture_fraction + (pressure / maxf(0.1, capture_seconds) if pressure > 0.0 else -capture_decay) * step, 0.0, 1.0)
		slowdown_fraction = move_toward(slowdown_fraction, 0.16 if contact else 0.0, step * 0.8)
		if gap_m >= escape_gap and pressure == 0.0 and capture_fraction <= 0.001:
			disengagement_seconds = minf(clean_escape_seconds, disengagement_seconds + step)
		else:
			disengagement_seconds = maxf(0.0, disengagement_seconds - step * 2.0)
		remaining -= step
		if capture_fraction >= 1.0:
			_finish(false)
		elif _escape_reached() and not _escape_queued:
			_escape_queued = true
			_confirm_escape.call_deferred(_generation)
	if active:
		_update_visual(delta, player_at, effects)

func _advance_unit(unit: Dictionary, index: int, step: float, player_at: Vector3, speed: float, base_speed: float, traffic: Array[RoadObstacle], traffic_remaining: float) -> void:
	var role: String = unit.role
	var speed_offset: float = ROLE_SPEED[role]
	# Posted limits and the unboosted curve never cap pursuit capability. The
	# introductory escape alone intentionally uses its gentle demonstration pace.
	var closing_speed := base_speed - 1.0 if training_escape else speed + speed_offset
	var target_speed := maxf(0.0, closing_speed)
	var target_x := clampf(player_at.x, -6.1, 6.1)
	var desired_z := 5.6
	if index > 0:
		target_x = clampf(player_at.x + (-3.5 if index % 2 == 1 else 3.5), -6.1, 6.1)
		desired_z = 0.0 if role != "heavy" else 7.0
	if role == "interceptor":
		target_x = clampf(player_at.x + (3.5 if player_at.x <= 0.0 else -3.5), -6.1, 6.1)
		desired_z = -6.0
	elif role == "heavy":
		target_x = clampf(player_at.x, -6.1, 6.1)
		desired_z = 7.0
	unit.state = "rear_pressure" if index == 0 and role != "interceptor" else "side_pressure"
	if not training_escape and float(unit.z) < desired_z + 10.0:
		target_speed = maxf(0.0, speed + clampf((float(unit.z) - desired_z) * 0.8, -8.0, 4.0))
	var lookahead := 35.0 + pow(maxf(0.0, float(unit.speed)), 2.0) / maxf(1.0, braking * 2.0)
	var blocker: RoadObstacle = _blocker(float(unit.x), float(unit.z), player_at.z, traffic, lookahead, speed, traffic_remaining)
	if blocker != null:
		var best_x := float(unit.x)
		var best_score := INF
		for lane in LANES:
			if _blocker(lane, float(unit.z), player_at.z, traffic, lookahead, speed, traffic_remaining) != null:
				continue
			var score := absf(lane - target_x) + absf(lane - float(unit.x)) * 0.3
			for other in units:
				if other != unit and absf(float(other.z) - float(unit.z)) < 9.0 and absf(float(other.x) - lane) < 2.8:
					score += 20.0
			if score < best_score:
				best_score = score
				best_x = lane
		target_x = best_x
		var clear_distance := float(unit.z) - _traffic_z(blocker, player_at.z, speed, traffic_remaining) - HALF_LENGTH - blocker.half_length
		target_speed = minf(target_speed, sqrt(pow(blocker.cruise_speed, 2.0) + 2.0 * braking * maxf(0.0, clear_distance - 3.0)))
		unit.state = "overtake" if best_score < INF else "traffic_yield"
	var lateral_speed := lateral_response * (0.65 if role == "heavy" else 1.0)
	var previous_x := float(unit.x)
	var next_x := move_toward(previous_x, target_x, lateral_speed * step)
	if not _lateral_clear(previous_x, next_x, float(unit.z), player_at.z, traffic, speed, traffic_remaining, step):
		next_x = previous_x
		unit.state = "traffic_yield"
	for other_index in range(units.size()):
		if other_index == index:
			continue
		var other := units[other_index]
		var separation := float(unit.z) - float(other.z)
		if absf(separation) < HALF_LENGTH * 2.0 + 1.0 and minf(previous_x, next_x) < float(other.x) + HALF_WIDTH * 2.0 and maxf(previous_x, next_x) > float(other.x) - HALF_WIDTH * 2.0:
			next_x = previous_x
		if separation > 0.0 and separation < 15.0 and absf(next_x - float(other.x)) < HALF_WIDTH * 2.0 + 0.2 and float(other.speed) >= 0.0:
			target_speed = minf(target_speed, float(other.speed) + maxf(0.0, separation - HALF_LENGTH * 2.0 - 1.0))
	unit.x = next_x
	# Actual lane changes scrub speed; elapsed clean time never weakens units.
	if absf(float(unit.x) - previous_x) > 0.001:
		target_speed = maxf(0.0, target_speed - (heavy_lane_change_speed_loss if role == "heavy" else lane_change_speed_loss))
	if _elapsed < approach_grace_seconds:
		target_speed = minf(target_speed, speed + grace_approach_speed)
	if float(unit.speed) < 0.0:
		unit.speed = maxf(0.0, minf(closing_speed, speed + grace_approach_speed))
	unit.speed = move_toward(float(unit.speed), target_speed, (braking if target_speed < float(unit.speed) else acceleration) * step)
	var next_z := float(unit.z) + (speed - float(unit.speed)) * step
	for actor in traffic:
		if not is_instance_valid(actor) or not actor.active or actor.kind == RoadObstacle.Kind.POTHOLE:
			continue
		var side_extent := HALF_WIDTH + actor.half_width
		if minf(previous_x, float(unit.x)) > actor.global_position.x + side_extent or maxf(previous_x, float(unit.x)) < actor.global_position.x - side_extent:
			continue
		var previous_traffic_z := _traffic_z(actor, player_at.z, speed, traffic_remaining)
		var traffic_z := _traffic_z(actor, player_at.z, speed, maxf(0.0, traffic_remaining - step))
		var previous_gap := float(unit.z) - previous_traffic_z
		var next_gap := next_z - traffic_z
		var traffic_extent := HALF_LENGTH + actor.half_length + 0.25
		# Keep the contact margin while accepting a previously clear physical
		# bumper. Node3D positions round to floats; a margin equality must not
		# let the next step slip inside and disable all subsequent contacts.
		var physical_extent := HALF_LENGTH + actor.half_length
		if previous_gap >= physical_extent - 0.00001 and next_gap < traffic_extent:
			# A swept traffic bumper contact brakes the unit instead of phasing.
			next_z = traffic_z + traffic_extent
			unit.speed = minf(float(unit.speed), actor.cruise_speed)
			unit.state = "traffic_yield"
		elif previous_gap <= -physical_extent + 0.00001 and next_gap > -traffic_extent:
			# A rear bumper impact transfers velocity at contact. This physical
			# impulse is separate from finite engine throttle and cannot move x.
			next_z = traffic_z - traffic_extent
			unit.speed = maxf(float(unit.speed), actor.cruise_speed)
			unit.state = "traffic_yield"
	var extent := HALF_LENGTH + Player.COLLISION_SIZE.z * 0.5
	unit.contact = minf(float(unit.z), next_z) <= extent and maxf(float(unit.z), next_z) >= -extent and absf(float(unit.x) - player_at.x) <= HALF_WIDTH + Player.COLLISION_SIZE.x * 0.5
	if unit.contact:
		unit.speed = move_toward(float(unit.speed), speed, braking * step)
	unit.z = next_z

func _traffic_z(actor: RoadObstacle, player_z: float, speed: float, remaining: float) -> float:
	# Game advances the traffic for the whole frame before advancing police.
	# Rewind from that endpoint to this substep rather than replaying the same
	# final traffic position in every 1/60-second step. No snapshots allocate.
	return actor.global_position.z - player_z - (speed - actor.cruise_speed) * remaining

func _lateral_clear(from_x: float, to_x: float, at_z: float, player_z: float, traffic: Array[RoadObstacle], speed: float = 0.0, remaining: float = 0.0, step: float = 0.0) -> bool:
	for actor in traffic:
		if not is_instance_valid(actor) or not actor.active or actor.kind == RoadObstacle.Kind.POTHOLE:
			continue
		var from_z := _traffic_z(actor, player_z, speed, remaining)
		var to_z := _traffic_z(actor, player_z, speed, maxf(0.0, remaining - step))
		var extent := HALF_LENGTH + actor.half_length + 1.0
		if at_z < minf(from_z, to_z) - extent or at_z > maxf(from_z, to_z) + extent:
			continue
		# Include alongside and rear traffic in the swept lane-change corridor.
		if minf(from_x, to_x) < actor.global_position.x + actor.half_width + HALF_WIDTH + 0.25 and maxf(from_x, to_x) > actor.global_position.x - actor.half_width - HALF_WIDTH - 0.25:
			return false
	return true

func _blocker(at_x: float, at_z: float, player_z: float, traffic: Array[RoadObstacle], lookahead: float = 35.0, speed: float = 0.0, remaining: float = 0.0) -> RoadObstacle:
	var closest: RoadObstacle
	var distance := INF
	for actor in traffic:
		if not is_instance_valid(actor) or not actor.active or actor.kind == RoadObstacle.Kind.POTHOLE:
			continue
		var ahead := at_z - _traffic_z(actor, player_z, speed, remaining)
		if ahead > -HALF_LENGTH and ahead < lookahead + actor.half_length and absf(actor.global_position.x - at_x) < actor.half_width + HALF_WIDTH + 0.25 and ahead < distance:
			closest = actor
			distance = ahead
	return closest

func _boxed(player_x: float) -> bool:
	var left := false
	var right := false
	var rear := false
	for unit in units:
		if absf(float(unit.z)) > 9.0:
			continue
		left = left or (float(unit.x) < player_x - 2.0 and player_x - float(unit.x) < 5.0)
		right = right or (float(unit.x) > player_x + 2.0 and float(unit.x) - player_x < 5.0)
		rear = rear or (float(unit.z) > 0.0 and absf(float(unit.x) - player_x) < 2.8)
	return rear and (left and right or left and player_x > 4.0 or right and player_x < -4.0)

func register_mistake() -> void:
	if active:
		clean_seconds = 0.0
		disengagement_seconds = 0.0

func register_close_call() -> void:
	register_mistake()

func reset_pursuit() -> void:
	training_escape = false
	_generation += 1
	_escape_queued = false
	active = false
	units.clear()
	_last_gap = 0.0
	capture_fraction = 0.0
	slowdown_fraction = 0.0
	disengagement_seconds = 0.0
	clean_seconds = 0.0
	_elapsed = 0.0
	timed_chase = false
	chase_duration = clean_escape_seconds
	visible = false
	if _rear_view != null:
		_rear_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for visual in _visuals:
		visual.reset_scene()

func get_rearview_texture() -> Texture2D:
	return _rear_view.get_texture() if _rear_view != null else null

func get_escape_progress() -> float:
	return disengagement_seconds

func _escape_reached() -> bool:
	return disengagement_seconds >= clean_escape_seconds - 0.000000001 and gap_m >= escape_gap and capture_fraction <= 0.001

func _confirm_escape(generation: int) -> void:
	if generation != _generation or not active:
		return
	_escape_queued = false
	if _escape_reached():
		_finish(true)

func _finish(did_escape: bool) -> void:
	_last_gap = gap_m
	_escape_queued = false
	active = false
	visible = false
	_rear_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for visual in _visuals:
		visual.reset_scene()
	if did_escape:
		escaped.emit()
	else:
		caught.emit()

func _update_visual(delta: float, player_at: Vector3, effects: float) -> void:
	for index in range(units.size()):
		var unit := units[index]
		var visual := _visuals[index]
		visual.advance(delta, effects)
		visual.police.global_position = player_at + Vector3(float(unit.x) - player_at.x, 0.0, float(unit.z))
		visual.police.rotation = Vector3.ZERO
	_rear_camera.global_position = player_at + Vector3(0.0, 2.65, 2.8)
	var rear_target := player_at + Vector3(0.0, 1.0, 35.0)
	var rear_gap := INF
	for unit in units:
		if float(unit.z) > 4.0 and float(unit.z) < rear_gap:
			rear_gap = float(unit.z)
			rear_target = player_at + Vector3(float(unit.x) - player_at.x, 1.0, float(unit.z))
	var camera_gap := maxf(8.0, (rear_gap if rear_gap < INF else 35.0) - 2.8)
	_rear_camera.far = maxf(180.0, gap_m + 50.0)
	_rear_camera.fov = clampf(rad_to_deg(2.0 * atan((8.6 if units.size() > 1 else 2.6) / camera_gap)), 1.0, 70.0)
	_rear_camera.look_at(rear_target, Vector3.UP)
