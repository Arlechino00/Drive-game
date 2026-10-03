extends SceneTree
## Actual-scene background review; captures freeze only the diagnostic fixture.

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.run_seed = 2468
	game.start_game()
	game.set_process(false)
	game.set_physics_process(false)
	game.player.active = false
	game.obstacles.spawning_enabled = false
	game.obstacles.motion_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.world.set_secret_level(false)
	game.world.set_effects(1.0)
	game.speed = 62.0
	game.road.reset_road()
	game.road.advance(120.0)
	game.distance = 120.0
	game.camera.reset_camera()
	for frame in range(180):
		game.camera.follow(1.0 / 60.0, 0.0, 0.0, game.speed, false)
	game.obstacles._take_obstacle().activate(Vector3(-5, 0, -35), RoadObstacle.Kind.CAR)
	game.obstacles._take_obstacle().activate(Vector3(5, 0, -60), RoadObstacle.Kind.VAN)
	game.obstacles._take_obstacle().activate(Vector3(0, 0, -50), RoadObstacle.Kind.POTHOLE)
	game.ui.update_hud(game.get_score(), roundi(game.speed * 3.6))
	await process_frame
	if OS.get_cmdline_user_args().has("--baseline"):
		await _save("background_before.png")
	else:
		_test_world(game)
		if OS.get_cmdline_user_args().has("--capture"):
			await _save("background_sunset.png")
			_set_section(game, 520.0)
			await _save("background_city.png")
			_set_section(game, 920.0)
			await _save("background_canopy.png")
			_set_section(game, 120.0)
			game.world.set_secret_level(true)
			game.ui.configure_secret(true)
			game.ui.configure_mode(2)
			await _save("background_secret.png")
			game.world.set_secret_level(false)
			game.ui.configure_mode(0)
			game.ui.configure_secret(false)
			game.world.set_effects(0.0)
			await _save("background_effects_off.png")
			game.world.set_effects(1.0)
			root.content_scale_size = Vector2i(1920, 800)
			root.size = Vector2i(1920, 800)
			await _save("background_wide.png")
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < until:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("BACKGROUND PASS: actual-scene background fixture, readable hazards and palette/resource checks")
	quit(1 if failures else 0)


func _test_world(game) -> void:
	var world = game.world
	var nodes := _node_count(world)
	var resources := _resource_ids(world)
	var light_signature := _light_signature(world)
	var ambient: Color = world.environment.ambient_light_color
	var energy: float = world.environment.ambient_light_energy
	var fog_color: Color = world.environment.fog_light_color
	var hazards := _hazard_signature(game)
	_check(light_signature.size() >= 2 and energy >= 0.75, "key and rim lighting retained")
	_check_background_geometry(world)
	_check(world.sky_material.shader != null and world.sun_material.shader != null and world.halo_material.shader != null, "sky, sliced sun and halo shaders loaded")
	for material in [world.sky_material, world.sun_material, world.halo_material]:
		_check(_has_uniform(material, "secret_amount"), "all background shader layers expose Secret palette")
		_check(_has_uniform(material, "effects_amount"), "all background shader layers expose effects setting")
	for cycle in range(200):
		var effects := float(cycle % 3) * 0.5
		world.set_effects(effects)
		world.set_secret_level(true)
		for entry in world.backdrop_palette:
			var material: StandardMaterial3D = entry.material
			_check(material.albedo_color == entry.secret and material.emission == entry.secret, "mountain and skyline materials join Secret palette")
			_check(is_equal_approx(material.emission_energy_multiplier, entry.emission * effects), "backdrop glow follows effects without changing hazard materials")
		for material in [world.sky_material, world.sun_material, world.halo_material]:
			_check(material.get_shader_parameter("secret_amount") == 1.0, "Secret palette covers sky, sun and halo")
			_check(material.get_shader_parameter("effects_amount") == effects, "effects amount reaches each sky layer")
		_check(world.environment.ambient_light_energy >= 0.75, "Secret lighting keeps traffic readable")
		_check(world.environment.fog_sky_affect == 0.0 and world.environment.fog_density <= 0.002, "light haze preserves road hazard visibility")
		_check(_light_signature(world) == light_signature, "background switching preserves driving lights")
		world.set_secret_level(false)
		for entry in world.backdrop_palette:
			var material: StandardMaterial3D = entry.material
			_check(material.albedo_color == entry.sunset and material.emission == entry.sunset, "ordinary mountain and skyline palette restored in place")
		_check(world.environment.ambient_light_color == ambient and is_equal_approx(world.environment.ambient_light_energy, energy) and world.environment.fog_light_color == fog_color, "ordinary atmosphere restored exactly")
		for material in [world.sky_material, world.sun_material, world.halo_material]:
			_check(material.get_shader_parameter("secret_amount") == 0.0, "ordinary palette restored on every background layer")
		_check(world.effects_amount == effects and world.environment.glow_enabled == (effects > 0.0), "Secret switching preserves chosen effects intensity")
		_check(_node_count(world) == nodes and nodes < 600, "background node count stays finite through repeated switches")
		_check(_resource_ids(world) == resources, "background reuses exact mesh, material, shader and environment resources")
		_check(_hazard_signature(game) == hazards, "background settings preserve actual hazard paint, lamps, positions and collision shapes")
	for actor in game.obstacles.obstacle_pool:
		if actor.active:
			var screen: Vector2 = game.camera.unproject_position(actor.global_position + Vector3(0, 0.4, 0))
			_check(not game.camera.is_position_behind(actor.global_position) and Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(-20).has_point(screen), "traffic and pothole remain inside driving view")
	world.set_secret_level(false)
	world.set_effects(1.0)
	if failures == 0:
		print("BACKGROUND RUNTIME: 200 Secret/effects cycles; %d stable world nodes / %d resource identities; driving lights, fog and actual hazards preserved" % [nodes, resources.size()])


func _check_background_geometry(world: VisualWorld) -> void:
	var ridges := world.find_children("MountainRidge*", "MeshInstance3D", false, false)
	_check(ridges.size() == 3, "three authored mountain depth layers exist")
	var sun := world.get_node("SlicedSun") as MeshInstance3D
	for ridge in ridges:
		var arrays: Array = ridge.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var side_peak := 0.0
		var center_samples := 0
		var tones: Dictionary = {}
		_check(colors.size() == vertices.size(), "mountain triangle facets have authored vertex colors")
		for index in range(vertices.size()):
			var vertex: Vector3 = ridge.transform * vertices[index]
			_check(vertex.z > sun.position.z and vertex.z < -200.0, "sun sits behind separate distant mountain layers")
			if absf(vertex.x) <= 30.0:
				center_samples += 1
				_check(vertex.y < 8.0, "central mountain valley leaves sunset and highway visible")
			if absf(vertex.x) > 125.0:
				side_peak = maxf(side_peak, vertex.y)
			if index < colors.size():
				tones[colors[index]] = true
		_check(center_samples > 0 and side_peak > 20.0 and tones.size() >= 3, "mountains have visible side peaks and distinct triangular facets")
	var batches := world.find_children("Skyline*", "MultiMeshInstance3D", false, false)
	_check(not batches.is_empty(), "distant skyline uses authored instancing")
	for batch in batches:
		var authored: Array = batch.get_meta("authored_transforms")
		_check(authored.size() == batch.multimesh.instance_count and not authored.is_empty(), "skyline batch has a fixed populated transform catalog")
		for index in range(authored.size()):
			var authored_transform: Transform3D = authored[index]
			if DisplayServer.get_name() != "headless":
				_check(batch.multimesh.get_instance_transform(index).is_equal_approx(authored_transform), "rendered skyline batch matches authored footprints")
			var bounds: AABB = batch.transform * authored_transform * batch.multimesh.mesh.get_aabb()
			_check(bounds.end.x < -30.0 or bounds.position.x > 30.0, "skyline remains outside the central driving/sunset corridor")
			_check(bounds.end.z < -200.0, "skyline stays well behind live traffic and potholes")

func _has_uniform(material: ShaderMaterial, name: String) -> bool:
	for parameter in material.shader.get_shader_uniform_list():
		if parameter.name == name:
			return true
	return false


func _resource_ids(world: Node) -> Array[int]:
	var resources: Dictionary = {}
	_collect_resources(world, resources)
	var ids: Array[int] = []
	for id in resources:
		ids.append(int(id))
	ids.sort()
	return ids


func _collect_resources(node: Node, resources: Dictionary) -> void:
	if node is WorldEnvironment:
		resources[node.environment.get_instance_id()] = true
		resources[node.environment.sky.get_instance_id()] = true
		resources[node.environment.sky.sky_material.get_instance_id()] = true
		resources[node.environment.sky.sky_material.shader.get_instance_id()] = true
	if node is MeshInstance3D:
		resources[node.mesh.get_instance_id()] = true
	elif node is MultiMeshInstance3D:
		resources[node.multimesh.get_instance_id()] = true
		resources[node.multimesh.mesh.get_instance_id()] = true
	if (node is MeshInstance3D or node is MultiMeshInstance3D) and node.material_override != null:
		resources[node.material_override.get_instance_id()] = true
		if node.material_override is ShaderMaterial:
			resources[node.material_override.shader.get_instance_id()] = true
	for child in node.get_children():
		_collect_resources(child, resources)


func _light_signature(world: Node) -> Array:
	var result: Array = []
	for light in world.find_children("*", "Light3D", true, false):
		result.append([light.get_instance_id(), light.light_color, light.light_energy, light.transform])
	return result


func _hazard_signature(game) -> Array:
	var result: Array = []
	for actor in game.obstacles.obstacle_pool:
		if not actor.active:
			continue
		result.append([actor.get_instance_id(), actor.kind, actor.position, actor._collision.shape.size])
		for part in actor.find_children("*", "MeshInstance3D", true, false):
			var material = part.material_override
			if material is StandardMaterial3D:
				result.append([material.get_instance_id(), material.albedo_color, material.emission, material.emission_energy_multiplier, material.emission_enabled])
	return result


func _node_count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _node_count(child)
	return total


func _set_section(game, distance: float) -> void:
	game.road.reset_road()
	game.road.advance(distance)
	game.distance = distance
	_check(game.road.get_section_name() == ("OPEN GRID" if distance == 120.0 else ("CITY EDGE" if distance == 520.0 else "NEON CANOPY")), "capture frames authored road section")

func _save(file_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://tests/" + file_name) == OK, "capture saved: " + file_name)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 8:
			push_error("BACKGROUND FAIL: " + label)
