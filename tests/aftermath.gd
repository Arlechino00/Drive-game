extends SceneTree

const Player = preload("res://scripts/player_car.gd")
const Obstacle = preload("res://scripts/obstacle.gd")
const Models = preload("res://scripts/traffic_models.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists("res://scripts/police_aftermath.gd"):
		_check(false, "police aftermath exists")
		quit(1)
		return
	var script = load("res://scripts/police_aftermath.gd")
	var aftermath = script.new()
	var player := Player.new()
	root.add_child(aftermath)
	root.add_child(player)
	await process_frame
	player.position = Vector3(2.5, 0.0, 0.0)
	var stopped_player := player.global_position
	var count := _node_count(aftermath)
	_check(not aftermath.active and not aftermath.visible, "inactive scene starts hidden")
	_check(_physics_node_count(aftermath) == 0, "cinematic actors cannot trigger gameplay collisions")
	_check(aftermath.police.find_children("*Wheel", "MeshInstance3D", true, false).size() == 4, "police car has four visible wheels")
	_check(aftermath.police.find_children("*PoliceLabel", "Label3D", true, false).size() >= 2, "police identity is readable on both sides")
	for kind in [Obstacle.Kind.CAR, Obstacle.Kind.VAN, Obstacle.Kind.WIDE]:
		aftermath.start_crash(stopped_player, kind, Vector3(2.5, 0.0, -1.0))
		_check(aftermath.active and aftermath.visible and not aftermath.arrived, "crash starts police approach")
		_check(aftermath.wreck.visible and aftermath.wreck_kind == kind, "crash keeps the collided traffic kind")
		var names := ["", "CarVisual", "VanVisual", "WideVisual"]
		for index in range(1, 4):
			_check(aftermath.wreck.get_node(names[index]).visible == (index == kind), "only the matching traffic replica is visible")
		_check(aftermath.wreck.global_position.z <= stopped_player.z - 6.0, "crashed traffic stops ahead without overlapping hero")
		_check(absf(aftermath.wreck.global_position.x - 2.5) < 0.01, "crashed traffic keeps its lane")
		_check(aftermath.police.global_position.z >= stopped_player.z + 24.0, "police enters from behind")
		var wreck_position: Vector3 = aftermath.wreck.global_position
		var previous_z: float = aftermath.police.global_position.z
		for frame in range(200):
			aftermath.advance(1.0 / 60.0)
			var at: Vector3 = aftermath.police.global_position
			_check(at.z <= previous_z + 0.001, "police approaches continuously")
			_check(absf(at.x) <= 6.15, "police stays inside the road")
			_check(absf(at.x - stopped_player.x) > 3.0 or absf(at.z - stopped_player.z) > 6.0, "police approach never intersects stopped hero")
			previous_z = at.z
		_check(aftermath.arrived, "police parks within about three seconds")
		_check(absf(aftermath.police.global_position.x - stopped_player.x) > 3.0, "police parks safely alongside hero")
		_check(absf(aftermath.police.global_position.z - stopped_player.z) < 2.0, "police reaches hero longitudinally")
		_check(aftermath.wreck.global_position.is_equal_approx(wreck_position), "traffic remains stopped during approach")
		_check(player.global_position.is_equal_approx(stopped_player), "aftermath preserves actual stopped player position")
		var parked_position: Vector3 = aftermath.police.global_position
		for frame in range(60):
			aftermath.advance(1.0 / 60.0)
		_check(aftermath.police.global_position.is_equal_approx(parked_position), "parked police does not drift")
		await _check_camera(aftermath, player)
		aftermath.reset_scene()
		_check(not aftermath.active and not aftermath.arrived and not aftermath.visible, "reset clears and hides aftermath")
		_check(not aftermath.police.visible and not aftermath.wreck.visible, "reset hides both actors")
		aftermath.advance(10.0)
		_check(not aftermath.arrived, "inactive scene cannot arrive")
		aftermath.start_roadworks(stopped_player)
		_check(aftermath.active and aftermath.police.visible and not aftermath.wreck.visible, "roadworks summons police without a traffic wreck")
		aftermath.advance(0.01)
		var blue := aftermath.police.get_node("BlueBeacon") as MeshInstance3D
		var red := aftermath.police.get_node("RedBeacon") as MeshInstance3D
		var blue_material := blue.material_override as StandardMaterial3D
		var red_material := red.material_override as StandardMaterial3D
		var blue_energy := blue_material.emission_energy_multiplier
		var red_energy := red_material.emission_energy_multiplier
		aftermath.advance(0.15)
		_check((blue_material.emission_energy_multiplier - blue_energy) * (red_material.emission_energy_multiplier - red_energy) < 0.0, "red and blue roof beacons alternate")
		aftermath.advance(4.0, 0.0)
		_check(aftermath.arrived and aftermath.police.visible, "effects-off setting keeps police arrival visible")
		var reduced_blue := blue_material.emission_energy_multiplier
		var reduced_red := red_material.emission_energy_multiplier
		aftermath.advance(0.15, 0.0)
		_check(is_equal_approx(blue_material.emission_energy_multiplier, reduced_blue) and is_equal_approx(red_material.emission_energy_multiplier, reduced_red), "effects-off keeps beacons steady")
		aftermath.reset_scene()
	# A divider impact can catch traffic in the adjacent lane. Both sides of
	# the road must remain in frame, rather than only same-lane collisions.
	for fixture in [Vector2(-6.2, -3.3), Vector2(6.2, 3.3), Vector2(-0.1, -3.0), Vector2(0.1, 3.0)]:
		player.position.x = fixture.x
		aftermath.start_crash(player.global_position, Obstacle.Kind.WIDE, Vector3(fixture.y, 0.0, -1.0))
		aftermath.advance(4.0)
		await _check_camera(aftermath, player)
		aftermath.reset_scene()
	for cycle in range(200):
		var at := Vector3(-6.2 if cycle % 2 == 0 else 6.2, 0.0, 0.0)
		aftermath.start_crash(at, 1 + cycle % 3, at + Vector3(0.0, 0.0, -1.0))
		aftermath.advance(4.0)
		_check(absf(aftermath.police.global_position.x) < 6.15, "edge-lane police parking stays on road")
		_check(absf(aftermath.police.global_position.x - at.x) > 3.0, "edge-lane police parking clears hero")
		aftermath.reset_scene()
		aftermath.start_roadworks(at)
		aftermath.advance(4.0)
		aftermath.reset_scene()
	_check(_node_count(aftermath) == count and count < 300, "200 crash/roadworks resets reuse bounded visual nodes")
	_check(_physics_node_count(aftermath) == 0, "restarts never create physics actors")
	for model in range(Models.COUNT):
		aftermath.start_crash(Vector3.ZERO, Models.kind_for_model(model), Vector3(5, 0, -1), model)
		var visible_models := 0
		for visual in aftermath.wreck.get_children():
			if visual.visible:
				visible_models += 1
				_check(visual.get_meta("traffic_model") == model, "after collision the replica preserves exact traffic design")
		_check(visible_models == 1, "only one of ten stopped models is visible")
		aftermath.reset_scene()
	var full_catalog_nodes := _node_count(aftermath)
	for cycle in range(200):
		var model := cycle % Models.COUNT
		aftermath.start_crash(Vector3.ZERO, Models.kind_for_model(model), Vector3(5, 0, -1), model)
		aftermath.reset_scene()
	_check(_node_count(aftermath) == full_catalog_nodes and _physics_node_count(aftermath) == 0, "all ten aftermath models have stable reuse and no collision actors")
	player.free()
	aftermath.free()
	await process_frame
	if failures == 0:
		print("AFTERMATH PASS: exact ten-model replicas, stopped hero/traffic, collision-free police approach/parking, responsive left-side framing, alternating beacons and 200 bounded catalog reuses (%s nodes)" % full_catalog_nodes)
	quit(1 if failures else 0)


func _check_camera(aftermath: Node3D, player: Node3D) -> void:
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	for size in [Vector2i(960, 540), Vector2i(2560, 2048), Vector2i(3440, 1440)]:
		viewport.size = size
		camera.position = Vector3(0.0, 5.2, 12.8)
		camera.look_at(Vector3(0.0, 1.0, -22.0), Vector3.UP)
		for frame in range(240):
			aftermath.frame_camera(camera, 1.0 / 60.0)
		for actor in [player, aftermath.police, aftermath.wreck]:
			var projected: Vector2 = camera.unproject_position(actor.global_position + Vector3.UP)
			var fraction := projected / Vector2(size)
			_check(not camera.is_position_behind(actor.global_position), "cinematic actor stays in front of camera")
			_check(fraction.x >= 0.02 and fraction.x <= 0.43 and fraction.y >= 0.15 and fraction.y <= 0.85, "actor center leaves right results region clear at %s: %s" % [size, fraction])
			for part in actor.find_children("*", "MeshInstance3D", true, false):
				if not part.is_visible_in_tree():
					continue
				var bounds: AABB = part.mesh.get_aabb()
				for corner in range(8):
					var world_point: Vector3 = part.global_transform * bounds.get_endpoint(corner)
					var point: Vector2 = camera.unproject_position(world_point) / Vector2(size)
					_check(point.x >= 0.0 and point.x < 0.45 and point.y >= 0.08 and point.y <= 0.92, "full actor silhouette leaves right results region clear at %s: %s" % [size, point])
	viewport.free()


func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func _physics_node_count(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _physics_node_count(child)
	return count


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("AFTERMATH FAIL: " + label)
