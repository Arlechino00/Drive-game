extends SceneTree

const Car = preload("res://scripts/player_car.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := Car.new()
	root.add_child(player)
	await process_frame
	var hull := player.visual.get_node_or_null("BodyShell") as MeshInstance3D
	_check(hull != null and hull.mesh is ArrayMesh, "beveled body mesh")
	var cabin := player.visual.get_node_or_null("CabinGlass") as MeshInstance3D
	_check(cabin != null and cabin.mesh is ArrayMesh, "sloped cabin mesh")
	var logo := player.visual.get_node_or_null("RoofLogo") as MeshInstance3D
	_check(logo != null, "roof carries supplied logo")
	if logo:
		var material := logo.material_override as StandardMaterial3D
		_check(material.albedo_texture.resource_path == "res://logo.png", "original logo texture")
		_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "logo transparency preserved")
		_check(material.albedo_color == Color.WHITE, "original logo color preserved")
		var logo_size: Vector2 = logo.mesh.size
		_check(is_equal_approx(logo_size.y / logo_size.x, 1619.0 / 1645.0), "original logo aspect ratio")
	_check(player.front_wheels.size() == 2 and player.exhausts.size() == 2, "steering and boost visual hooks preserved")
	for wheel in player.front_wheels:
		_check(wheel.mesh is CylinderMesh, "round front wheels")
	for mesh in player.visual.find_children("*", "MeshInstance3D", true, false):
		if mesh in player.exhausts:
			continue
		var bounds: AABB = mesh.mesh.get_aabb()
		for corner in range(8):
			var point: Vector3 = player.global_transform.affine_inverse() * (mesh.global_transform * bounds.get_endpoint(corner))
			_check(absf(point.x) <= Car.COLLISION_SIZE.x * 0.5 + 0.05, "%s width follows collision footprint" % mesh.name)
			_check(absf(point.z) <= Car.COLLISION_SIZE.z * 0.5 + 0.05, "%s length follows collision footprint" % mesh.name)
	var before: int = player.get_child_count()
	for index in range(50):
		player.set_boost(true, 1.0)
		player.reset_car()
	_check(player.get_child_count() == before, "reset reuses visual nodes")
	_check(not player.boosting and not player.exhausts[0].visible, "reset clears boost visual")
	player.queue_free()
	await process_frame
	if failures == 0:
		print("CAR DESIGN PASS: beveled body, sloped cabin, round wheels, original transparent logo, matching footprint and stable reset")
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("CAR DESIGN FAIL: " + label)
