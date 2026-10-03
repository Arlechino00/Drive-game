class_name RoadChunk
extends Node3D

const LENGTH: float = 40.0
var chunk_index: int = 0
var category: int = 0
var category_groups: Array[Node3D] = []
var city_props: Array[Node3D] = []
var canopy_gates: Array[Node3D] = []


func build(materials: Dictionary) -> void:
	_build_highway(materials)
	for group_name in ["OpenGrid", "CityEdge", "NeonCanopy"]:
		var group := Node3D.new()
		group.name = group_name
		add_child(group)
		category_groups.append(group)
	_build_open(category_groups[0], materials)
	_build_city(category_groups[1], materials)
	_build_canopy(category_groups[2], materials)


func configure(index: int, section_length: int) -> void:
	chunk_index = index
	var safe_index := maxi(index, 0)
	category = floori(float(safe_index) / float(section_length)) % 3
	var section_chunk := safe_index % section_length
	for group_index in range(category_groups.size()):
		category_groups[group_index].visible = group_index == category
	# Entry and exit chunks thin the skyline and arch rhythm over 80 m.
	# Everything is pooled; transitions/recycling allocate no resources.
	var transition := section_chunk == 0 or section_chunk == section_length - 1
	for prop_index in range(city_props.size()):
		city_props[prop_index].visible = not transition or prop_index % 3 == 0
	for gate_index in range(canopy_gates.size()):
		canopy_gates[gate_index].visible = not transition or gate_index % 2 == 0


func _build_highway(m: Dictionary) -> void:
	_box(self, Vector3(0, -0.12, -20), Vector3(16, 0.2, LENGTH), m.road)
	var grid_transforms: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		_box(self, Vector3(side * 77, -0.25, -20), Vector3(138, 0.1, LENGTH), m.ground)
		_box(self, Vector3(side * 8.15, -0.04, -20), Vector3(0.5, 0.12, LENGTH), m.rail)
		_box(self, Vector3(side * 7.75, 0.025, -20), Vector3(0.13, 0.05, LENGTH), m.cyan)
		_box(self, Vector3(side * 8.6, 0.6, -20), Vector3(0.18, 0.19, LENGTH), m.rail)
		_box(self, Vector3(side * 8.49, 0.63, -20), Vector3(0.035, 0.055, LENGTH), m.pink)
		for marker in range(5):
			_box(self, Vector3(side * 8.6, 0.30, -4.0 - marker * 8), Vector3(0.16, 0.6, 0.20), m.rail)
			_box(self, Vector3(side * 8.49, 0.58, -4.0 - marker * 8), Vector3(0.05, 0.13, 0.35), m.cyan)
			_box(self, Vector3(side * 7.34, 0.014, -4.0 - marker * 8), Vector3(0.18, 0.02, 0.7), m.marking)
		for line in range(4):
			grid_transforms.append(Transform3D(Basis.from_scale(Vector3(138, 0.018, 0.055)), Vector3(side * 77, -0.19, -line * 10)))
		for column in range(18):
			grid_transforms.append(Transform3D(Basis.from_scale(Vector3(0.055, 0.018, LENGTH)), Vector3(side * (10 + column * 8), -0.19, -20)))
	_batch_boxes(self, grid_transforms, m.grid)
	for lane_edge in [-2.5, 2.5]:
		for dash in range(5):
			_box(self, Vector3(lane_edge, 0.015, -4.0 - dash * 8), Vector3(0.105, 0.025, 3.5), m.marking)
			_box(self, Vector3(lane_edge, 0.02, -6.5 - dash * 8), Vector3(0.12, 0.035, 0.18), m.pink)


func _build_open(group: Node3D, m: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		for marker in range(2):
			var z_position := -10.0 - marker * 20.0
			_box(group, Vector3(side * 12.5, 2.2, z_position), Vector3(0.65, 4.4, 0.7), m.dark)
			_box(group, Vector3(side * 12.12, 2.2, z_position), Vector3(0.075, 3.8, 0.5), m.cyan)
			_box(group, Vector3(side * 12.5, 4.4, z_position), Vector3(1.4, 0.1, 1.2), m.pink)
			_box(group, Vector3(side * 11.6, 4.15, z_position), Vector3(2.0, 0.18, 0.55), m.dark)
			_box(group, Vector3(side * 10.9, 4.04, z_position), Vector3(0.55, 0.05, 0.38), m.windows)
		_box(group, Vector3(side * 24, 2.8, -22), Vector3(1.4, 5.6, 1.4), m.dark)
		_box(group, Vector3(side * 24, 5.6, -22), Vector3(2.2, 0.1, 2.2), m.amber)


func _build_city(group: Node3D, m: Dictionary) -> void:
	for side in [-1.0, 1.0]:
		for index in range(4):
			var building := Node3D.new()
			group.add_child(building)
			city_props.append(building)
			var height := 9.0 + float((index * 7 + int(side) + 10) % 5) * 3.0
			var width := 4.0 + float(index % 2)
			var center := Vector3(side * (15.0 + (index % 2) * 5.5), height * 0.5 - 0.2, -5.0 - index * 10.0)
			_box(building, center, Vector3(width, height, 6.0), m.city)
			_box(building, Vector3(center.x, height + 0.4, center.z), Vector3(width * 0.6, 1.2, 4), m.dark)
			_box(building, Vector3(center.x, height + 1.1, center.z), Vector3(width * 0.65, 0.08, 4.1), m.cyan if index % 2 else m.pink)
			_box(building, Vector3(center.x - side * width * 0.5, height * 0.5, center.z + 3.05), Vector3(0.08, height, 0.11), m.pink if index % 2 == 0 else m.cyan)
			var windows: Array[Transform3D] = []
			for row in range(floori(height / 2.0) - 1):
				for column in range(3):
					if (row + column + index) % 4 == 0:
						continue
					windows.append(Transform3D(Basis.from_scale(Vector3(0.5, 0.32, 0.05)), Vector3(center.x + (column - 1) * width * 0.24, 2.0 + row * 1.8, center.z + 3.04)))
			_batch_boxes(building, windows, m.windows)
			_box(building, Vector3(center.x - side * (width * 0.5 + 0.04), height * 0.65, center.z), Vector3(0.05, height * 0.5, 0.6), m.windows)
		_box(group, Vector3(side * 10.6, 4.0, -18), Vector3(0.25, 8, 0.3), m.dark)
		_box(group, Vector3(side * 11.8, 6.4, -18), Vector3(2.5, 1.0, 0.2), m.dark)
		_box(group, Vector3(side * 11.8, 6.4, -17.88), Vector3(1.9, 0.12, 0.05), m.amber)


func _build_canopy(group: Node3D, m: Dictionary) -> void:
	for index in range(4):
		var gate := Node3D.new()
		group.add_child(gate)
		canopy_gates.append(gate)
		var z_position := -5.0 - index * 10.0
		for side in [-1.0, 1.0]:
			_box(gate, Vector3(side * 9.8, 4.0, z_position), Vector3(0.6, 8.0, 0.75), m.dark)
			_box(gate, Vector3(side * 9.45, 4.0, z_position), Vector3(0.08, 7.6, 0.8), m.cyan)
		_box(gate, Vector3(0, 8.0, z_position), Vector3(20.2, 0.45, 0.8), m.dark)
		_box(gate, Vector3(0, 7.72, z_position), Vector3(18.9, 0.065, 0.8), m.pink)
		for side in [-1.0, 1.0]:
			var brace := _box(gate, Vector3(side * 8.7, 6.9, z_position), Vector3(0.24, 2.8, 0.6), m.rail)
			brace.rotation.z = side * -PI / 4.0
			_box(gate, Vector3(side * 7.5, 7.62, z_position), Vector3(1.2, 0.10, 0.95), m.windows)
	# Open roof/side gaps retain horizon and traffic visibility.
	for side in [-1.0, 1.0]:
		_box(group, Vector3(side * 10.3, 6.8, -20), Vector3(0.25, 0.25, LENGTH), m.dark)
		_box(group, Vector3(side * 10.1, 6.65, -20), Vector3(0.06, 0.08, LENGTH), m.amber)


func _batch_boxes(parent: Node3D, transforms: Array[Transform3D], material: Material) -> void:
	# Repeated small details use a single draw call and never rebuild on recycle.
	var instance := MultiMeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for index in range(transforms.size()):
		batch.set_instance_transform(index, transforms[index])
	instance.multimesh = batch
	# The headless dummy renderer does not retain MultiMesh transform readback.
	# Keep authored transforms available for corridor validation in that mode.
	instance.set_meta("authored_transforms", transforms)
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = center
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
