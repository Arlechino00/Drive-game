extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var road := RoadManager.new()
	root.add_child(road)
	var nodes_before := _node_count(road)
	var materials_before := _material_ids(road)
	var distances: Array[float] = [0.0, 399.0, 400.0, 799.0, 800.0, 1199.0, 1200.0]
	var expected_sections: Array[String] = ["OPEN GRID", "OPEN GRID", "CITY EDGE", "CITY EDGE", "NEON CANOPY", "NEON CANOPY", "OPEN GRID"]
	for index in range(distances.size()):
		road.reset_road()
		road.advance(distances[index])
		_check(road.get_section_name() == expected_sections[index], "authored 400 m section boundaries")
	road.reset_road()
	var sections: Dictionary = {}
	_check_prop_corridor(road)
	for step in range(30000):
		var previous_categories: Dictionary = {}
		for segment in road.segments:
			previous_categories[segment.get_instance_id()] = segment.category
		road.advance(7.75)
		for segment in road.segments:
			if previous_categories[segment.get_instance_id()] != segment.category:
				_check(segment.position.z < -220.0, "category changes ahead of visible approach")
		sections[road.get_section_name()] = true
		if step % 47 == 0:
			_check_seams(road)
	_check(sections.size() == 3, "all authored sections reached")
	_check(_node_count(road) == nodes_before, "bounded recycled prop nodes")
	_check(_material_ids(road) == materials_before, "material resources reused")
	for restart in range(200):
		road.reset_road()
		_check_seams(road)
		_check(road.get_section_name() == "OPEN GRID", "deterministic reset section")
	_check(_node_count(road) == nodes_before, "restart reuses all prop nodes")
	# Large advances must recycle as many times as necessary without a seam.
	road.advance(10000.0)
	_check_seams(road)
	var world := VisualWorld.new()
	root.add_child(world)
	var world_nodes := _node_count(world)
	for setting in [0.0, 0.5, 1.0, 0.0]:
		world.set_effects(setting)
	_check(_node_count(world) == world_nodes, "effects setting keeps world bounded")
	_check(world.environment.fog_sky_affect == 0.0 and world.environment.fog_density <= 0.002, "horizon stays clear while road gets light haze")
	_check(world.sun_material.shader != null, "sliced sun shader exists")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture_sections(road)
	road.free()
	world.free()
	if failures == 0:
		print("WORLD PASS: 232.5 km, 200 resets, seamless coverage, three sections, %d fixed nodes / %d materials, effects settings" % [nodes_before, materials_before.size()])
	quit(1 if failures > 0 else 0)


func _check_seams(road: RoadManager) -> void:
	var positions: Array[float] = []
	for segment in road.segments:
		positions.append(segment.position.z)
	positions.sort()
	for index in range(1, positions.size()):
		_check(absf(positions[index] - positions[index - 1] - 40.0) < 0.001, "road seams")
	_check(positions[0] < -200.0 and positions[-1] >= 0.0, "player and horizon covered")
	_check(road.segments.size() == road.SEGMENT_COUNT, "fixed road segment budget covers high-speed look-ahead")


func _node_count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _node_count(child)
	return total


func _material_ids(node: Node) -> Array[int]:
	var unique: Dictionary = {}
	_collect_materials(node, unique)
	var ids: Array[int] = []
	for id in unique:
		ids.append(int(id))
	ids.sort()
	return ids


func _collect_materials(node: Node, unique: Dictionary) -> void:
	if (node is MeshInstance3D or node is MultiMeshInstance3D) and node.material_override != null:
		unique[node.material_override.get_instance_id()] = true
	for child in node.get_children():
		_collect_materials(child, unique)


func _check_prop_corridor(road: RoadManager) -> void:
	for segment in road.segments:
		for group in segment.category_groups:
			_check_prop_node(group)


func _check_prop_node(node: Node3D) -> void:
	if node is MeshInstance3D:
		_check_prop_bounds(node.transform * node.mesh.get_aabb())
	elif node is MultiMeshInstance3D:
		var authored: Array = node.get_meta("authored_transforms")
		for index in range(node.multimesh.instance_count):
			var instance_transform: Transform3D = authored[index]
			if DisplayServer.get_name() != "headless":
				instance_transform = node.multimesh.get_instance_transform(index)
				_check(instance_transform.is_equal_approx(authored[index]), "rendered batch matches authored position")
			_check_prop_bounds(node.transform * instance_transform * node.multimesh.mesh.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_check_prop_node(child)


func _check_prop_bounds(bounds: AABB) -> void:
	if bounds.position.y < 5.0:
		_check(bounds.end.x <= -8.0 or bounds.position.x >= 8.0, "roadside props leave highway clear: %s" % bounds)


func _capture_sections(road: RoadManager) -> void:
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 75.0
	camera.far = 550.0
	camera.position = Vector3(0, 6.5, 15)
	root.add_child(camera)
	camera.look_at(Vector3(0, 1.2, -20))
	root.size = Vector2i(1280, 720)
	var distances: Array[float] = [120.0, 520.0, 920.0]
	var labels: Array[String] = ["open", "city", "canopy"]
	for index in range(distances.size()):
		road.reset_road()
		road.advance(distances[index])
		for frame in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png("res://.godot/validation/world_%s.png" % labels[index])
		_check(result == OK, "world capture saved")
	camera.free()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures < 10:
			push_error("WORLD FAIL: " + label)
