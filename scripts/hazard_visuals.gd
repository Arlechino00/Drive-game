extends RefCounted
## Amber danger markers contrast with the highway's cyan/pink decoration.

const Parts = preload("res://scripts/vehicle_mesh.gd")
static var _crater: ArrayMesh
static var _rim: ArrayMesh
static var _cone: CylinderMesh


static func build(pothole: bool) -> Node3D:
	var visual := Node3D.new()
	visual.name = "PotholeVisual" if pothole else "RoadworksVisual"
	var dark := _material(Color("#080811"), 0.0)
	var asphalt := _material(Color("#4b3844"), 0.0)
	var amber := _material(Color("#ffbb37"), 1.3)
	var orange := _material(Color("#f37524"), 0.05)
	var white := _material(Color("#ece7cc"), 0.2)
	if pothole:
		_build_crater(visual, dark, asphalt, amber)
	else:
		_build_worksite(visual, dark, orange, white, amber)
	return visual


static func _build_crater(parent: Node3D, dark: Material, asphalt: Material, amber: Material) -> void:
	if _crater == null:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rim_surface := SurfaceTool.new()
		rim_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in range(20):
			var first := TAU * index / 20.0
			var second := TAU * (index + 1) / 20.0
			var outer_a := _edge(first, index, 1.0, 0.072)
			var outer_b := _edge(second, (index + 1) % 20, 1.0, 0.072)
			var inner_a := _edge(first, index, 0.77, 0.025)
			var inner_b := _edge(second, (index + 1) % 20, 0.77, 0.025)
			Parts.quad(rim_surface, outer_a, outer_b, inner_b, inner_a)
			Parts.triangle(surface, Vector3(0, 0.022, 0), inner_a, inner_b)
		_crater = surface.commit()
		_rim = rim_surface.commit()
	Parts.instance(parent, "DarkCrater", _crater, Vector3.ZERO, dark)
	Parts.instance(parent, "BrokenAsphaltRim", _rim, Vector3.ZERO, asphalt)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			Parts.box(parent, "AmberRimMarker", Vector3(side * 0.96, 0.095, end * 0.88), Vector3(0.13, 0.055, 0.38), amber)


static func _edge(angle: float, index: int, scale: float, height: float) -> Vector3:
	var roughness := 1.0 - float((index * 7) % 4) * 0.035
	return Vector3(cos(angle) * 1.3 * scale * roughness, height, sin(angle) * 1.5 * scale * roughness)


static func _build_worksite(parent: Node3D, dark: Material, orange: Material, white: Material, amber: Material) -> void:
	Parts.box(parent, "ClosedLaneSurface", Vector3(0, 0.018, 0), Vector3(3.9, 0.025, 11.9), dark)
	# Both ends are fenced: the entrance is obvious from the chase camera.
	for end in [-1.0, 1.0]:
		var fence := Node3D.new()
		fence.name = "StripedBarricade"
		fence.position = Vector3(0, 0, end * 5.55)
		parent.add_child(fence)
		Parts.box(fence, "WhiteBoard", Vector3(0, 0.83, 0), Vector3(3.55, 0.55, 0.16), white)
		for stripe in range(7):
			var mark := Parts.box(fence, "OrangeStripe", Vector3(-1.47 + stripe * 0.49, 0.83, end * 0.09), Vector3(0.24, 0.50, 0.025), orange)
			mark.rotation.z = -0.38
		for side in [-1.0, 1.0]:
			Parts.box(fence, "BarricadeLeg", Vector3(side * 1.35, 0.40, 0), Vector3(0.12, 0.8, 0.12), orange)
			Parts.box(fence, "WarningLamp", Vector3(side * 1.35, 1.18, 0), Vector3(0.22, 0.22, 0.16), amber)
	for side in [-1.0, 1.0]:
		for z in [-3.6, -0.4, 2.8]:
			_cone_at(parent, Vector3(side * 1.64, 0, z), orange, white, dark)
	# An orange compact road roller sits entirely inside the closed lane.
	Parts.box(parent, "RollerChassis", Vector3(0, 0.64, 0.9), Vector3(1.70, 0.82, 2.75), orange)
	Parts.box(parent, "RollerCab", Vector3(0, 1.3, 1.1), Vector3(1.32, 0.68, 1.25), dark)
	Parts.box(parent, "RollerRoof", Vector3(0, 1.69, 1.1), Vector3(1.65, 0.12, 1.5), orange)
	for z in [-0.35, 2.0]:
		var drum := Parts.cylinder(parent, "RollerDrum", Vector3(0, 0.40, z), 0.40, 1.82, dark)
		drum.rotation.z = PI * 0.5
	Parts.box(parent, "EquipmentBeacon", Vector3(0, 1.82, 1.1), Vector3(0.20, 0.16, 0.20), amber)


static func _cone_at(parent: Node3D, center: Vector3, orange: Material, white: Material, dark: Material) -> void:
	if _cone == null:
		_cone = CylinderMesh.new()
		_cone.top_radius = 0.035
		_cone.bottom_radius = 0.22
		_cone.height = 0.65
		_cone.radial_segments = 8
		_cone.rings = 1
	Parts.box(parent, "ConeBase", center + Vector3(0, 0.04, 0), Vector3(0.52, 0.08, 0.52), dark)
	Parts.instance(parent, "OrangeCone", _cone, center + Vector3(0, 0.40, 0), orange)
	Parts.cylinder(parent, "ConeReflector", center + Vector3(0, 0.45, 0), 0.125, 0.09, white)


static func _material(color: Color, glow: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.05
	material.roughness = 0.85
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material
