class_name PolicePursuit
extends Node3D
## The game supplies driving time and actual speed; these police are visual only.

signal caught
signal escaped

const PoliceVisual = preload("res://scripts/police_aftermath.gd")

@export var initial_gap: float = 64.0
@export var capture_gap: float = 7.0
@export var escape_gap: float = 100.0
@export var clean_escape_seconds: float = 16.0
@export var approach_grace_seconds: float = 3.0
@export var grace_approach_speed: float = 4.0
@export var police_speed_advantage: float = 3.0
@export var clean_speed_reduction: float = 9.0
@export var clean_reduction_seconds: float = 10.0
@export var mistake_gap_loss: float = 14.0
@export var close_call_gap_loss: float = 6.0
@export var lateral_response: float = 4.5

var active: bool = false
var gap_m: float = 0.0
var clean_seconds: float = 0.0
var _elapsed: float = 0.0
var _visual: PoliceAftermath
var _rear_view: SubViewport
var _rear_camera: Camera3D


func _ready() -> void:
	_visual = PoliceVisual.new()
	_visual.name = "PoliceVisual"
	add_child(_visual)
	_rear_view = SubViewport.new()
	_rear_view.name = "RearView"
	_rear_view.size = Vector2i(384, 160)
	_rear_view.own_world_3d = false
	_rear_view.world_3d = get_world_3d()
	_rear_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_rear_view)
	_rear_camera = Camera3D.new()
	_rear_camera.name = "RearCamera"
	_rear_camera.fov = 28.0
	_rear_camera.near = 0.1
	_rear_camera.far = 150.0
	_rear_view.add_child(_rear_camera)
	_rear_camera.current = true
	reset_pursuit()


func begin(player_at: Vector3) -> void:
	reset_pursuit()
	gap_m = clampf(initial_gap, capture_gap + 1.0, escape_gap - 1.0)
	active = true
	visible = true
	_rear_view.world_3d = get_world_3d()
	_rear_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Use the existing public lifecycle to retain its meshes and beacon behavior.
	# Roadworks starts only the police, keeping the stopped-traffic replicas hidden.
	_visual.start_roadworks(player_at)
	_visual.police.global_position = player_at + Vector3(0.0, 0.0, gap_m)
	_update_visual(0.0, player_at, 1.0)


func advance(delta: float, player_at: Vector3, speed: float, base_speed: float, effects: float = 1.0) -> void:
	if not active or delta <= 0.0:
		return
	if _resolve_outcome():
		return
	# Small fixed slices preserve capture before a later recovery on long frames,
	# and keep results consistent when a caller advances a whole interval at once.
	var remaining := delta
	var advanced := 0.0
	while active and remaining > 0.000000001:
		var step := minf(remaining, 1.0 / 60.0)
		var police_speed: float
		if _elapsed < approach_grace_seconds:
			step = minf(step, approach_grace_seconds - _elapsed)
			# Cap relative approach during the initial impact, including strong damage.
			police_speed = minf(base_speed + police_speed_advantage, speed + grace_approach_speed)
		else:
			var clean_fraction := clampf((clean_seconds + step * 0.5) / maxf(0.01, clean_reduction_seconds), 0.0, 1.0)
			police_speed = base_speed + police_speed_advantage - clean_fraction * clean_speed_reduction
		gap_m = maxf(0.0, gap_m + (maxf(0.0, speed) - maxf(0.0, police_speed)) * step)
		clean_seconds = minf(clean_escape_seconds, clean_seconds + step)
		_elapsed += step
		remaining -= step
		advanced += step
		_resolve_outcome()
	if active:
		_update_visual(advanced, player_at, effects)


func register_mistake() -> void:
	if not active:
		return
	clean_seconds = 0.0
	gap_m = maxf(0.0, gap_m - mistake_gap_loss)
	_resolve_outcome()


func register_close_call() -> void:
	if not active:
		return
	clean_seconds = 0.0
	gap_m = maxf(0.0, gap_m - close_call_gap_loss)
	_resolve_outcome()


func reset_pursuit() -> void:
	active = false
	gap_m = 0.0
	clean_seconds = 0.0
	_elapsed = 0.0
	visible = false
	if _rear_view != null:
		_rear_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _visual != null:
		_visual.reset_scene()


func get_rearview_texture() -> Texture2D:
	return _rear_view.get_texture() if _rear_view != null else null


func _resolve_outcome() -> bool:
	if gap_m <= capture_gap:
		_finish(false)
		return true
	if gap_m >= escape_gap or clean_seconds >= clean_escape_seconds - 0.000000001:
		if clean_seconds >= clean_escape_seconds - 0.000000001:
			clean_seconds = clean_escape_seconds
		_finish(true)
		return true
	return false


func _finish(did_escape: bool) -> void:
	active = false
	visible = false
	_rear_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_visual.reset_scene()
	if did_escape:
		escaped.emit()
	else:
		caught.emit()


func _update_visual(delta: float, player_at: Vector3, effects: float) -> void:
	var previous_x := _visual.police.global_position.x
	_visual.advance(delta, effects)
	var blend := 1.0 - exp(-maxf(0.0, delta) * lateral_response)
	_visual.police.global_position = Vector3(lerpf(previous_x, clampf(player_at.x, -6.1, 6.1), blend), player_at.y, player_at.z + gap_m)
	_visual.police.rotation = Vector3.ZERO
	_rear_camera.global_position = player_at + Vector3(0.0, 2.65, 2.8)
	# Track the real police with a zoomed mirror so the initial 64 m gap is readable.
	var camera_gap := maxf(8.0, gap_m - 2.8)
	_rear_camera.fov = clampf(rad_to_deg(2.0 * atan(2.6 / camera_gap)), 3.0, 36.0)
	# Cars drive toward -Z, so a rear camera faces +Z. Aim at the actual car,
	# rather than a duplicate world, so steering and changing distance remain real.
	_rear_camera.look_at(_visual.police.global_position + Vector3.UP, Vector3.UP)
