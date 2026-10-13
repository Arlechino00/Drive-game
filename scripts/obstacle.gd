class_name RoadObstacle
extends Area3D

signal player_hit
signal pothole_hit
signal roadworks_entered
signal near_miss(points: int, clearance: float)

enum Kind { BARRIER, CAR, VAN, WIDE, POTHOLE, ROADWORKS }

const VehicleMesh = preload("res://scripts/vehicle_mesh.gd")
const TrafficModels = preload("res://scripts/traffic_models.gd")
const HazardVisuals = preload("res://scripts/hazard_visuals.gd")
const TRAFFIC_SPEED: float = 14.0
const Player = preload("res://scripts/player_car.gd")
const Tuning = preload("res://scripts/stage_two_tuning.gd")
const PLAYER_HALF_WIDTH: float = Player.COLLISION_SIZE.x * 0.5
const PLAYER_HALF_LENGTH: float = Player.COLLISION_SIZE.z * 0.5
const NEAR_CLEARANCE: float = 1.0

var active: bool = false
var kind: int = Kind.BARRIER
var model_id: int = -1
var racing: bool = false
var _model_visuals: Dictionary = {}
var cruise_speed: float = 0.0
var speed_factor: float = 1.0
var lane_target: float = 0.0
var changing_lane: bool = false
var cut_in_done: bool = false
var motion_position := Vector3.ZERO
var motion_x := 0.0
var motion_speed := 0.0
var half_width: float = 1.6
var half_length: float = 0.625
var pass_collided: bool = false
var pass_awarded: bool = false
var minimum_clearance: float = INF
var _visuals: Array[Node3D] = []
var _collision: CollisionShape3D
var _activation_serial: int = 0
var _previous_player_x: float = 0.0
var _previous_actor_x: float = 0.0
var _pass_finished: bool = false
var _pass_reward_pending: bool = false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	area_entered.connect(_on_area_entered)
	_build_visuals()
	_collision = CollisionShape3D.new()
	_collision.shape = BoxShape3D.new()
	add_child(_collision)
	deactivate()


# Default barrier activation preserves the original collision/testing API.
func activate(at_position: Vector3, vehicle_kind: int = Kind.BARRIER, player_x: float = 0.0, vehicle_model: int = -1) -> void:
	_activation_serial += 1
	racing = false
	kind = clampi(vehicle_kind, Kind.BARRIER, Kind.ROADWORKS)
	model_id = -1
	if kind >= Kind.CAR and kind <= Kind.WIDE:
		model_id = TrafficModels.default_model(kind) if vehicle_model < 0 else clampi(vehicle_model, 0, TrafficModels.COUNT - 1)
		kind = TrafficModels.kind_for_model(model_id)
		_ensure_model(model_id)
	var dimensions: Vector3 = [Vector3(3.2, 1.05, 1.25), Vector3(2.0, 1.05, 4.4), Vector3(2.4, 1.9, 5.0), Vector3(2.8, 1.4, 4.8), Vector3(2.6, 0.22, 3.0), Vector3(4.0, 1.8, 12.0)][kind]
	if model_id >= 0:
		dimensions = TrafficModels.dimensions(model_id)
	half_width = dimensions.x * 0.5
	half_length = dimensions.z * 0.5
	cruise_speed = TRAFFIC_SPEED if kind >= Kind.CAR and kind <= Kind.WIDE else 0.0
	(_collision.shape as BoxShape3D).size = dimensions
	_collision.position.y = 0.15 + dimensions.y * 0.5
	for index in range(_visuals.size()):
		_visuals[index].visible = index == kind and model_id < 3
	for model in _model_visuals:
		_model_visuals[model].visible = model == model_id
	position = at_position
	speed_factor = 1.0
	lane_target = at_position.x
	changing_lane = false
	cut_in_done = false
	_previous_player_x = player_x
	_previous_actor_x = at_position.x
	minimum_clearance = INF
	pass_collided = false
	pass_awarded = false
	_pass_finished = false
	_pass_reward_pending = false
	visible = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	active = true


func deactivate() -> void:
	racing = false
	active = false
	visible = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)


func retire() -> void:
	# A long step can carry a clean pass beyond the pool's rear boundary in
	# the same tick. Resolve its queued reward/contact before reusing the slot.
	if _pass_reward_pending:
		_retire_pass.call_deferred(_activation_serial)
	else:
		deactivate()


func _retire_pass(serial: int) -> void:
	if serial == _activation_serial:
		deactivate()


# Sweep both footprints rather than judging a near miss at an arbitrary z point.
# Lateral samples are interpolated across the part of the frame alongside.
func advance_pass(relative_delta: float, player_x: float) -> bool:
	if not active:
		return false
	var previous_z := position.z
	var next_z := previous_z + relative_delta
	var longitudinal_extent := half_length + PLAYER_HALF_LENGTH
	if minf(previous_z, next_z) <= longitudinal_extent and maxf(previous_z, next_z) >= -longitudinal_extent:
		var start_t := 0.0
		var end_t := 1.0
		if relative_delta != 0.0:
			var first_t := (-longitudinal_extent - previous_z) / relative_delta
			var last_t := (longitudinal_extent - previous_z) / relative_delta
			start_t = clampf(minf(first_t, last_t), 0.0, 1.0)
			end_t = clampf(maxf(first_t, last_t), 0.0, 1.0)
		var side_start := lerpf(_previous_player_x, player_x, start_t) - lerpf(_previous_actor_x, position.x, start_t)
		var side_end := lerpf(_previous_player_x, player_x, end_t) - lerpf(_previous_actor_x, position.x, end_t)
		var closest_side := minf(absf(side_start), absf(side_end))
		if side_start * side_end <= 0.0:
			closest_side = 0.0
		var clearance := closest_side - half_width - PLAYER_HALF_WIDTH
		minimum_clearance = minf(minimum_clearance, clearance)
		if clearance <= 0.0:
			var contact_t := start_t
			var lateral_extent := half_width + PLAYER_HALF_WIDTH
			if absf(side_start) > lateral_extent:
				var side_t := (signf(side_start) * lateral_extent - side_start) / (side_end - side_start)
				contact_t = lerpf(start_t, end_t, side_t)
			# Consumers use this position for the stopped traffic aftermath.
			position.x = lerpf(_previous_actor_x, position.x, contact_t)
			position.z = lerpf(previous_z, next_z, contact_t)
			_resolve_player_contact()
			# Emission may synchronously reset/reuse this pooled obstacle.
			return true
	position.z = next_z
	_previous_player_x = player_x
	_previous_actor_x = position.x
	if not racing and not _pass_finished and next_z > longitudinal_extent:
		_pass_finished = true
		if cruise_speed > 0.0 and minimum_clearance > 0.0 and minimum_clearance <= NEAR_CLEARANCE and not pass_collided:
			# Let already queued Area3D collision callbacks cancel the reward.
			_pass_reward_pending = true
			_finish_pass.call_deferred(_activation_serial)
	return false


func _finish_pass(serial: int) -> void:
	if serial != _activation_serial:
		return
	_pass_reward_pending = false
	if racing or pass_collided or pass_awarded or not active or cruise_speed <= 0.0:
		return
	pass_awarded = true
	var points := 100
	if minimum_clearance <= 0.22:
		points = 500
	elif minimum_clearance <= 0.5:
		points = 250
	near_miss.emit(points, minimum_clearance)


func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("player"):
		_resolve_player_contact()


func _resolve_player_contact() -> void:
	if not active or pass_collided:
		return
	pass_collided = true
	deactivate()
	match kind:
		Kind.POTHOLE:
			pothole_hit.emit()
		Kind.ROADWORKS:
			roadworks_entered.emit()
		_:
			player_hit.emit()


func _build_visuals() -> void:
	var barrier := Node3D.new()
	barrier.name = "BarrierVisual"
	add_child(barrier)
	_visuals.append(barrier)
	var barrier_paint := _material(Color("#e8419a"), 0.15)
	var stripe := _material(Color("#ffe386"), 1.8)
	_add_box(barrier, Vector3(0, 0.675, 0), Vector3(3.2, 1.05, 1.25), barrier_paint)
	for side in [-0.9, 0.0, 0.9]:
		_add_box(barrier, Vector3(side, 0.675, 0.645), Vector3(0.21, 0.86, 0.055), stripe)
	for model in range(3):
		_ensure_model(model)
		_visuals.append(_model_visuals[model])
	for hazard_kind in [Kind.POTHOLE, Kind.ROADWORKS]:
		var visual := HazardVisuals.build(hazard_kind == Kind.POTHOLE)
		add_child(visual)
		_visuals.append(visual)


func _ensure_model(model: int) -> void:
	if _model_visuals.has(model):
		return
	# Each pool slot creates a model once; switching models never grows beyond
	# the finite ten-design catalog. Cached meshes/materials are shared.
	var visual := TrafficModels.build(model)
	visual.visible = false
	add_child(visual)
	_model_visuals[model] = visual

func _add_box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	VehicleMesh.box(parent, "BarrierPart", center, size, material)


func _material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.6
	material.roughness = 0.31
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material
