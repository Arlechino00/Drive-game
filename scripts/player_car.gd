class_name PlayerCar
extends Area3D

const VehicleMesh = preload("res://scripts/vehicle_mesh.gd")
const Tuning = preload("res://scripts/stage_two_tuning.gd")
const COLLISION_SIZE := Tuning.PLAYER_SIZE
const VISUAL_SCALE := Vector3(1.55, 1.2, 1.55)

@export var max_lateral_speed: float = 15.0
@export var steering_acceleration: float = 62.0
@export var steering_release: float = 58.0
@export var road_limit: float = 6.2

var active: bool = false
var lateral_velocity: float = 0.0
var visual: Node3D
var front_wheels: Array[MeshInstance3D] = []
var exhausts: Array[MeshInstance3D] = []
var boosting: bool = false
var effects_strength: float = 0.7
var touch_controls: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	# Sample this tick's steering before traffic computes swept close passes.
	process_physics_priority = -10
	add_to_group("player")
	collision_layer = 1
	collision_mask = 2
	monitoring = true
	monitorable = true
	_build_visual()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = COLLISION_SIZE
	collision.shape = shape
	collision.position.y = 0.9
	add_child(collision)
	reset_car()


func reset_car() -> void:
	position = Vector3.ZERO
	lateral_velocity = 0.0
	active = false
	boosting = false
	if visual:
		visual.rotation = Vector3.ZERO
	for wheel in front_wheels:
		wheel.rotation.y = 0.0
	for exhaust in exhausts:
		exhaust.visible = false


func _physics_process(delta: float) -> void:
	if not active:
		return
	var steering := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steering -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steering += 1.0
	if touch_controls != null:
		steering = clampf(steering + touch_controls.get_steering_axis(), -1.0, 1.0)
	if Input.get_connected_joypads().size() > 0:
		var stick := Input.get_joy_axis(Input.get_connected_joypads()[0], JOY_AXIS_LEFT_X)
		if absf(stick) > 0.15:
			steering = clampf(steering + stick, -1.0, 1.0)
	if is_zero_approx(steering):
		lateral_velocity = move_toward(lateral_velocity, 0.0, steering_release * delta)
	else:
		lateral_velocity = move_toward(lateral_velocity, steering * max_lateral_speed, steering_acceleration * delta)
	position.x = clampf(position.x + lateral_velocity * delta, -road_limit, road_limit)
	if absf(position.x) >= road_limit:
		lateral_velocity = 0.0
	visual.rotation.z = lerpf(visual.rotation.z, -lateral_velocity * 0.009, minf(1.0, delta * 10.0))
	visual.rotation.y = lerpf(visual.rotation.y, -lateral_velocity * 0.008, minf(1.0, delta * 10.0))
	for wheel in front_wheels:
		wheel.rotation.y = lerpf(wheel.rotation.y, -steering * 0.32, minf(1.0, delta * 12.0))
	for exhaust in exhausts:
		exhaust.visible = boosting and effects_strength > 0.0
		exhaust.scale.z = 1.0 + effects_strength * 1.2


func set_boost(enabled: bool, amount: float) -> void:
	boosting = enabled
	effects_strength = amount
	if not enabled:
		for exhaust in exhausts:
			exhaust.visible = false


func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "CarVisual"
	visual.scale = VISUAL_SCALE
	add_child(visual)
	var paint := _material(Color("#ce318e"), 0.04)
	paint.metallic = 0.72
	paint.roughness = 0.24
	var dark := _material(Color("#141523"), 0.0)
	var rubber := _material(Color("#080b14"), 0.0)
	rubber.metallic = 0.0
	rubber.roughness = 0.85
	var silver := _material(Color("#b6c1d3"), 0.0)
	silver.metallic = 0.85
	var glass := _material(Color("#163e54"), 0.04)
	glass.metallic = 0.7
	glass.roughness = 0.15
	var cyan := _material(Color("#45e5ed"), 2.2)
	var headlight := _material(Color("#fff1c7"), 2.4)
	var red := _material(Color("#ff326e"), 2.6)
	# A chamfered shell and tapered cabin form the silhouette; detail stays inside
	# the existing physics footprint so visual polish does not change lane safety.
	_add_hull("BodyShell", [Vector4(-1.90, 0.71, 0.34, 0.49), Vector4(-1.50, 0.93, 0.32, 0.64), Vector4(-0.62, 0.98, 0.32, 0.79), Vector4(0.92, 1.00, 0.32, 0.82), Vector4(1.56, 0.97, 0.34, 0.80), Vector4(1.85, 0.82, 0.36, 0.71)], 0.10, paint)
	_add_cabin(glass)
	_add_box(visual, Vector3(0, 1.275, 0.18), Vector3(1.23, 0.055, 0.89), paint)
	_add_logo(Vector3(0, 1.305, 0.18), Vector2(0.85, 0.85 * 1619.0 / 1645.0))
	_add_box(visual, Vector3(0, 0.32, -1.73), Vector3(1.77, 0.10, 0.28), dark)
	_add_box(visual, Vector3(0, 0.37, -1.875), Vector3(1.61, 0.035, 0.035), cyan)
	_add_box(visual, Vector3(0, 0.43, 1.855), Vector3(1.74, 0.22, 0.08), dark)
	_add_box(visual, Vector3(0, 0.68, 1.865), Vector3(1.66, 0.10, 0.055), dark)
	# Six lamps read as one wide rear signature from the chase camera.
	for index in range(6):
		_add_box(visual, Vector3(-0.68 + index * 0.272, 0.69, 1.90), Vector3(0.245, 0.06, 0.035), red)
	for height in [0.51, 0.55, 0.59]:
		_add_box(visual, Vector3(0, height, 1.907), Vector3(1.28, 0.018, 0.025), silver)
	_add_box(visual, Vector3(0, 0.28, 1.68), Vector3(1.55, 0.12, 0.31), dark)
	for x in [-0.56, -0.28, 0.0, 0.28, 0.56]:
		_add_box(visual, Vector3(x, 0.28, 1.80), Vector3(0.035, 0.15, 0.25), dark)
	for z in [1.12, 1.24, 1.36]:
		_add_box(visual, Vector3(0, 0.828, z), Vector3(1.17, 0.025, 0.052), dark)
	_add_hull("RearWing", [Vector4(1.42, 0.95, 0.88, 0.96), Vector4(1.68, 1.01, 0.91, 0.98)], 0.018, dark)
	_add_box(visual, Vector3(0, 0.981, 1.64), Vector3(1.90, 0.024, 0.035), cyan)
	for side in [-1.0, 1.0]:
		var lamp := _add_box(visual, Vector3(side * 0.56, 0.552, -1.64), Vector3(0.43, 0.035, 0.22), dark)
		lamp.rotation.x = -0.16
		_add_box(visual, Vector3(side * 0.56, 0.575, -1.64), Vector3(0.37, 0.018, 0.16), headlight)
		_add_box(visual, Vector3(side * 0.88, 0.38, 0.03), Vector3(0.13, 0.16, 2.95), dark)
		_add_box(visual, Vector3(side * 0.955, 0.44, 0.03), Vector3(0.02, 0.033, 2.77), cyan)
		var mirror := _add_box(visual, Vector3(side * 0.975, 0.92, -0.47), Vector3(0.14, 0.07, 0.18), paint)
		mirror.rotation.y = side * 0.16
		_add_box(visual, Vector3(side * 0.735, 0.85, 1.55), Vector3(0.065, 0.12, 0.08), dark)
		var intake := _add_box(visual, Vector3(side * 0.80, 0.70, 0.65), Vector3(0.10, 0.055, 0.42), dark)
		intake.rotation.z = side * 0.30
		var hood_vent := _add_box(visual, Vector3(side * 0.39, 0.713, -1.03), Vector3(0.15, 0.025, 0.45), dark)
		hood_vent.rotation.x = 0.17
		# Thin pillars frame the glass without an opaque block-shaped passenger cabin.
		var pillar := _add_box(visual, Vector3(side * 0.69, 1.015, -0.545), Vector3(0.045, 0.80, 0.045), paint)
		pillar.rotation.x = 0.88
		pillar.rotation.z = side * 0.23
		var rear_pillar := _add_box(visual, Vector3(side * 0.69, 1.015, 0.915), Vector3(0.045, 0.80, 0.045), paint)
		rear_pillar.rotation.x = -0.90
		rear_pillar.rotation.z = side * 0.23
		for axle in [-1.13, 1.19]:
			var wheel := _add_wheel(side, axle, rubber, silver, dark, cyan)
			if axle < 0.0:
				front_wheels.append(wheel)
		var tailpipe := _add_cylinder(visual, Vector3(side * 0.60, 0.33, 1.89), 0.07, 0.09, silver)
		tailpipe.rotation.x = PI * 0.5
		_add_cylinder(tailpipe, Vector3(0, 0.05, 0), 0.052, 0.01, rubber)
		var exhaust := _add_box(visual, Vector3(side * 0.55, 0.32, 2.9), Vector3(0.13, 0.08, 2.0), cyan)
		exhaust.visible = false
		exhausts.append(exhaust)


func _add_hull(node_name: String, stations: Array[Vector4], bevel: float, material: Material) -> MeshInstance3D:
	return VehicleMesh.hull(visual, node_name, stations, bevel, material)


func _add_cabin(material: Material) -> void:
	VehicleMesh.canopy(visual, "CabinGlass", 0.78, 0.60, 0.77, 1.26, Vector4(-0.84, -0.25, 0.61, 1.22), material)


func _add_wheel(side: float, axle: float, rubber: Material, silver: Material, dark: Material, cyan: Material) -> MeshInstance3D:
	var wheel := _add_cylinder(visual, Vector3(side * 0.90, 0.41, axle), 0.34, 0.22, rubber)
	wheel.name = ("Left" if side < 0.0 else "Right") + ("FrontWheel" if axle < 0.0 else "RearWheel")
	wheel.rotation.z = PI * 0.5
	_add_cylinder(wheel, Vector3(0, -side * 0.122, 0), 0.245, 0.018, silver)
	_add_cylinder(wheel, Vector3(0, -side * 0.134, 0), 0.19, 0.012, dark)
	for spoke in range(5):
		var angle := spoke * TAU / 5.0
		var part := _add_box(wheel, Vector3(sin(angle) * 0.12, -side * 0.146, cos(angle) * 0.12), Vector3(0.04, 0.014, 0.23), silver)
		part.rotation.y = angle
	_add_cylinder(wheel, Vector3(0, -side * 0.158, 0), 0.065, 0.016, cyan)
	return wheel


func _add_cylinder(parent: Node3D, center: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	parent.add_child(instance)
	return instance


func _add_logo(center: Vector3, size: Vector2) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "RoofLogo"
	var mesh := PlaneMesh.new()
	mesh.size = size
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_texture = preload("res://logo.png")
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	instance.material_override = material
	instance.position = center
	visual.add_child(instance)


func _add_box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = center
	parent.add_child(mesh_instance)
	return mesh_instance


func _material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.35
	material.roughness = 0.32
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material
