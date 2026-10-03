class_name PoliceAftermath
extends Node3D
## Reused visual actors only; the game owns frozen gameplay state and timing.

const VehicleMesh = preload("res://scripts/vehicle_mesh.gd")
const Obstacle = preload("res://scripts/obstacle.gd")
const Models = preload("res://scripts/traffic_models.gd")

@export var arrival_seconds: float = 3.0
@export var approach_distance: float = 28.0
@export var parking_separation: float = 4.4
@export var camera_offset := Vector3(10.5, 9.0, 19.5)
@export var camera_fov: float = 62.0
@export var camera_response: float = 2.8

var active: bool = false
var arrived: bool = false
var police: Node3D
var wreck: Node3D
var wreck_kind: int = Obstacle.Kind.BARRIER
var _traffic_visuals: Array[Node3D] = []
var _model_visuals: Dictionary = {}
var _blue_material: StandardMaterial3D
var _red_material: StandardMaterial3D
var _blue_light: OmniLight3D
var _red_light: OmniLight3D
var _elapsed: float = 0.0
var _player_position := Vector3.ZERO
var _approach_start := Vector3.ZERO
var _park_position := Vector3.ZERO
var _frame_center := Vector3.ZERO
var _frame_width: float = 0.0


func _ready() -> void:
	_build_police()
	_build_traffic()
	reset_scene()


func reset_scene() -> void:
	active = false
	arrived = false
	_elapsed = 0.0
	wreck_kind = Obstacle.Kind.BARRIER
	visible = false
	police.visible = false
	wreck.visible = false
	_blue_light.light_energy = 0.0
	_red_light.light_energy = 0.0
	for visual in _traffic_visuals:
		visual.visible = false
	for visual in _model_visuals.values():
		visual.visible = false


func start_crash(player_position: Vector3, traffic_kind: int, traffic_position: Vector3, model_id: int = -1) -> void:
	_start(player_position)
	wreck_kind = clampi(traffic_kind, Obstacle.Kind.CAR, Obstacle.Kind.WIDE)
	wreck.visible = true
	for index in range(_traffic_visuals.size()):
		_traffic_visuals[index].visible = index + 1 == wreck_kind and model_id < 3
	if model_id >= 3 and model_id < 10:
		if not _model_visuals.has(model_id):
			var visual: Node3D = Models.build(model_id)
			wreck.add_child(visual)
			_model_visuals[model_id] = visual
		_model_visuals[model_id].visible = true
	# The impact hides the gameplay traffic. Keep a stopped visual in its lane,
	# just ahead of the hero when the two collision footprints have overlapped.
	var traffic_half_length: float = [0.0, 2.2, 2.5, 2.4][wreck_kind]
	var safe_z := minf(traffic_position.z, player_position.z - 3.0 - traffic_half_length - 0.8)
	wreck.global_position = Vector3(clampf(traffic_position.x, -6.0, 6.0), player_position.y, safe_z)
	wreck.rotation = Vector3.ZERO
	_update_frame_center()


func start_roadworks(player_position: Vector3) -> void:
	_start(player_position)
	_update_frame_center()


func _start(player_position: Vector3) -> void:
	reset_scene()
	_player_position = player_position
	# Choose the side with more road available. A parallel approach avoids
	# sweeping across the hero while the police slows into its parking spot.
	var side := 1.0 if player_position.x <= 0.0 else -1.0
	_park_position = player_position + Vector3(side * parking_separation, 0.0, 0.75)
	_park_position.x = clampf(_park_position.x, -6.1, 6.1)
	_approach_start = _park_position + Vector3(0.0, 0.0, approach_distance)
	police.global_position = _approach_start
	police.rotation = Vector3.ZERO
	active = true
	visible = true
	police.visible = true
	_update_beacons(1.0)


func advance(delta: float, effects: float = 1.0) -> void:
	if not active:
		return
	_elapsed += maxf(0.0, delta)
	var progress := clampf(_elapsed / maxf(0.05, arrival_seconds), 0.0, 1.0)
	# Ease out as the police brakes; no repeated interpolation or endpoint drift.
	var eased := 1.0 - pow(1.0 - progress, 3.0)
	police.global_position = _approach_start.lerp(_park_position, eased)
	arrived = progress >= 1.0
	_update_beacons(clampf(effects, 0.0, 1.0))


func frame_camera(camera: Camera3D, delta: float) -> void:
	if not active:
		return
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	# Narrow windows need a little more distance for the full three-car group.
	var distance_scale := maxf(1.0, 1.65 / aspect) * maxf(1.0, (_frame_width + 3.3) / 7.7)
	var target_position := _frame_center + camera_offset * distance_scale
	var target_basis := Basis.looking_at(_frame_center - target_position, Vector3.UP)
	# Aim slightly right of the group to leave the results panel clear. Rotating
	# the lens keeps camera offsets at zero, so the ordinary chase reset works.
	var pan := atan(0.53 * tan(deg_to_rad(camera_fov) * 0.5) * aspect)
	target_basis = target_basis * Basis(Vector3.UP, -pan)
	var blend := 1.0 - exp(-maxf(0.0, delta) * camera_response)
	camera.global_position = camera.global_position.lerp(target_position, blend)
	camera.global_basis = Basis(camera.global_basis.get_rotation_quaternion().slerp(target_basis.get_rotation_quaternion(), blend))
	camera.fov = lerpf(camera.fov, camera_fov, blend)


func _update_frame_center() -> void:
	var minimum := _player_position.min(_park_position)
	var maximum := _player_position.max(_park_position)
	if wreck.visible:
		minimum = minimum.min(wreck.global_position)
		maximum = maximum.max(wreck.global_position)
	_frame_center = (minimum + maximum) * 0.5 + Vector3(0.0, 1.0, 0.0)
	_frame_width = maximum.x - minimum.x


func _update_beacons(effects: float) -> void:
	if effects <= 0.0:
		_blue_material.emission_energy_multiplier = 0.8
		_red_material.emission_energy_multiplier = 0.8
		_blue_light.light_energy = 0.0
		_red_light.light_energy = 0.0
		return
	var blue_on := fmod(_elapsed, 0.28) < 0.14
	var low := 0.25
	var high := 1.5 + effects * 2.0
	_blue_material.emission_energy_multiplier = high if blue_on else low
	_red_material.emission_energy_multiplier = low if blue_on else high
	_blue_light.light_energy = (1.2 if blue_on else 0.0) * effects
	_red_light.light_energy = (0.0 if blue_on else 1.2) * effects


func _build_traffic() -> void:
	wreck = Node3D.new()
	wreck.name = "StoppedTraffic"
	add_child(wreck)
	# Build the current traffic visuals off-tree, then retain only their meshes.
	# No Area3D, signal, collision shape or per-frame traffic behavior survives.
	var source := Obstacle.new()
	source._build_visuals()
	for kind in [Obstacle.Kind.CAR, Obstacle.Kind.VAN, Obstacle.Kind.WIDE]:
		var visual: Node3D = source._visuals[kind]
		source.remove_child(visual)
		wreck.add_child(visual)
		_traffic_visuals.append(visual)
	source.free()


func _build_police() -> void:
	police = Node3D.new()
	police.name = "PoliceCar"
	add_child(police)
	var black := _material(Color("#111827"), 0.0)
	var white := _material(Color("#dce7f1"), 0.08)
	var glass := _material(Color("#173c50"), 0.08)
	glass.roughness = 0.16
	var rubber := _material(Color("#080c15"), 0.0)
	rubber.metallic = 0.0
	rubber.roughness = 0.85
	var metal := _material(Color("#a9bdd0"), 0.0)
	var cyan := _material(Color("#4bddff"), 1.1)
	var headlight := _material(Color("#defaff"), 1.8)
	var tail := _material(Color("#ff335a"), 1.8)
	_blue_material = _material(Color("#2276ff"), 3.5)
	_red_material = _material(Color("#ff304c"), 3.5)
	VehicleMesh.hull(police, "PoliceBody", [Vector4(-2.65, 0.80, 0.32, 0.57), Vector4(-2.08, 1.10, 0.29, 0.83), Vector4(-0.85, 1.18, 0.29, 0.92), Vector4(1.25, 1.18, 0.29, 0.92), Vector4(2.20, 1.09, 0.31, 0.83), Vector4(2.62, 0.92, 0.35, 0.74)], 0.13, black)
	VehicleMesh.canopy(police, "PoliceGlass", 0.95, 0.73, 0.93, 1.58, Vector4(-1.05, -0.47, 0.85, 1.51), glass)
	VehicleMesh.hull(police, "PoliceRoof", [Vector4(-0.48, 0.75, 1.58, 1.63), Vector4(0.86, 0.75, 1.58, 1.63)], 0.014, white)
	VehicleMesh.box(police, "WhiteHood", Vector3(0.0, 0.843, -1.83), Vector3(1.65, 0.06, 1.04), white)
	VehicleMesh.box(police, "FrontSplitter", Vector3(0.0, 0.29, -2.55), Vector3(1.75, 0.06, 0.32), black)
	VehicleMesh.box(police, "FrontSignature", Vector3(0.0, 0.61, -2.658), Vector3(1.58, 0.07, 0.025), headlight)
	VehicleMesh.box(police, "RearSignature", Vector3(0.0, 0.68, 2.633), Vector3(1.67, 0.065, 0.025), tail)
	VehicleMesh.box(police, "RearDiffuser", Vector3(0.0, 0.30, 2.40), Vector3(1.85, 0.13, 0.35), black)
	VehicleMesh.hull(police, "PoliceWing", [Vector4(2.16, 1.02, 0.98, 1.04), Vector4(2.42, 1.08, 1.00, 1.07)], 0.014, black)
	VehicleMesh.box(police, "LightbarBase", Vector3(0.0, 1.69, 0.20), Vector3(1.56, 0.09, 0.32), black)
	VehicleMesh.box(police, "BlueBeacon", Vector3(-0.43, 1.79, 0.20), Vector3(0.62, 0.13, 0.28), _blue_material)
	VehicleMesh.box(police, "RedBeacon", Vector3(0.43, 1.79, 0.20), Vector3(0.62, 0.13, 0.28), _red_material)
	_blue_light = _beacon_light("BlueLight", Vector3(-0.43, 1.86, 0.20), Color("#2276ff"))
	_red_light = _beacon_light("RedLight", Vector3(0.43, 1.86, 0.20), Color("#ff304c"))
	for side in [-1.0, 1.0]:
		VehicleMesh.box(police, "WhiteDoor", Vector3(side * 1.175, 0.74, 0.18), Vector3(0.028, 0.27, 1.65), white)
		VehicleMesh.box(police, "SideBlade", Vector3(side * 1.12, 0.38, 0.13), Vector3(0.09, 0.15, 3.95), black)
		VehicleMesh.box(police, "SideAccent", Vector3(side * 1.177, 0.46, 0.10), Vector3(0.016, 0.025, 3.75), cyan)
		VehicleMesh.box(police, "Mirror", Vector3(side * 1.19, 1.07, -0.78), Vector3(0.14, 0.085, 0.24), white)
		var label := Label3D.new()
		label.name = ("Left" if side < 0.0 else "Right") + "PoliceLabel"
		label.text = "POLICE"
		label.font_size = 48
		label.pixel_size = 0.007
		label.modulate = Color("#101d34")
		label.outline_size = 0
		label.shaded = false
		label.position = Vector3(side * 1.195, 0.76, 0.18)
		label.rotation.y = side * PI * 0.5
		police.add_child(label)
		for axle in [-1.68, 1.60]:
			var wheel_name := ("Left" if side < 0.0 else "Right") + ("FrontWheel" if axle < 0.0 else "RearWheel")
			var wheel := VehicleMesh.cylinder(police, wheel_name, Vector3(side * 1.08, 0.46, axle), 0.38, 0.23, rubber)
			wheel.rotation.z = PI * 0.5
			VehicleMesh.cylinder(wheel, "AlloyRim", Vector3(0.0, -side * 0.122, 0.0), 0.28, 0.016, metal)
			VehicleMesh.cylinder(wheel, "AeroHub", Vector3(0.0, -side * 0.136, 0.0), 0.20, 0.016, black)
			VehicleMesh.cylinder(wheel, "HubAccent", Vector3(0.0, -side * 0.150, 0.0), 0.075, 0.016, cyan)


func _beacon_light(node_name: String, center: Vector3, color: Color) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = node_name
	light.position = center
	light.light_color = color
	light.omni_range = 5.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	police.add_child(light)
	return light


func _material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.6
	material.roughness = 0.30
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material
