extends SceneTree

const Obstacle = preload("res://scripts/obstacle.gd")
const Models = preload("res://scripts/traffic_models.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var traffic := Obstacle.new()
	var second := Obstacle.new()
	root.add_child(traffic)
	root.add_child(second)
	await process_frame
	var names := ["Car", "Van", "Wide"]
	for kind in [Obstacle.Kind.CAR, Obstacle.Kind.VAN, Obstacle.Kind.WIDE]:
		traffic.activate(Vector3.ZERO, kind)
		second.activate(Vector3(8, 0, 0), kind)
		var visual: Node3D = traffic.get_node(names[kind - 1] + "Visual")
		var other: Node3D = second.get_node(names[kind - 1] + "Visual")
		var prefix: String = "Traffic" + names[kind - 1]
		var body := visual.get_node(prefix + "Body") as MeshInstance3D
		_check(body.mesh is ArrayMesh, names[kind - 1] + " faceted body")
		_check(visual.get_node(prefix + "Glass").mesh is ArrayMesh, names[kind - 1] + " sloping tinted cabin")
		_check(body.mesh == other.get_node(prefix + "Body").mesh, "pooled traffic shares immutable body meshes")
		var wheels := visual.find_children("Wheel*", "MeshInstance3D", true, false)
		_check(wheels.size() == 4, names[kind - 1] + " has four visible round wheels")
		for wheel in wheels:
			_check(wheel.mesh is CylinderMesh, "traffic tyre geometry")
		var tail := visual.get_node("RearLightBar") as MeshInstance3D
		var tail_material := tail.material_override as StandardMaterial3D
		_check(tail_material.emission_enabled and tail_material.emission.r > 0.9, "traffic rear signature stays red")
		var size: Vector3 = Models.dimensions(Models.default_model(kind))
		_check(traffic._collision.shape.size.is_equal_approx(size), "traffic collision footprint matches model catalog")
		for part in visual.find_children("*", "MeshInstance3D", true, false):
			var bounds: AABB = part.mesh.get_aabb()
			for corner in range(8):
				var point: Vector3 = traffic.global_transform.affine_inverse() * (part.global_transform * bounds.get_endpoint(corner))
				_check(absf(point.x) <= size.x * 0.5 + 0.025, names[kind - 1] + " mesh width matches hazard")
				_check(absf(point.z) <= size.z * 0.5 + 0.025, names[kind - 1] + " mesh length matches hazard")
				_check(point.y <= size.y + 0.15 + 0.025, names[kind - 1] + " mesh height matches hazard")
	var count := _node_count(traffic)
	for cycle in range(200):
		traffic.deactivate()
		traffic.activate(Vector3.ZERO, 1 + cycle % 3)
	_check(_node_count(traffic) == count, "activation reuses all model nodes")
	_check(count < 210, "detailed traffic geometry has a bounded node budget")
	traffic.free()
	second.free()
	await process_frame
	if failures == 0:
		print("TRAFFIC DESIGN PASS: three faceted silhouettes, tinted cabins, round wheels, red signatures, matching collision bounds, cached geometry and stable reuse (%s nodes)" % count)
	quit(1 if failures else 0)


func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("TRAFFIC DESIGN FAIL: " + label)
