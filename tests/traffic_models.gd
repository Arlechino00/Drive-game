extends SceneTree

const Obstacle = preload("res://scripts/obstacle.gd")
const Models = preload("res://scripts/traffic_models.gd")
const Meshes = preload("res://scripts/vehicle_mesh.gd")
var failures: int = 0
var near_misses: int = 0
var collisions: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var actor := Obstacle.new()
	var second := Obstacle.new()
	root.add_child(actor)
	root.add_child(second)
	await process_frame
	var bodies: Array[Mesh] = []
	var unique_widths: Dictionary = {}
	var expected_widths: Array[float] = [2.0, 2.4, 2.8, 3.1, 1.8, 3.0, 2.3, 3.2, 2.6, 2.7]
	for model in range(Models.COUNT):
		actor.activate(Vector3.ZERO, Models.kind_for_model(model), 0.0, model)
		second.activate(Vector3(8, 0, 0), Models.kind_for_model(model), 0.0, model)
		_check(actor.model_id == model and actor.kind == Models.kind_for_model(model), "model retains identity and physics category")
		var visual: Node3D = actor._model_visuals[model]
		var other: Node3D = second._model_visuals[model]
		_check(visual.visible, "chosen design visible")
		for previous in actor._model_visuals:
			_check(actor._model_visuals[previous].visible == (previous == model), "pool displays exactly one traffic model")
		var body := visual.find_children("*Body", "MeshInstance3D", false, false)[0] as MeshInstance3D
		var other_body := other.find_children("*Body", "MeshInstance3D", false, false)[0] as MeshInstance3D
		_check(body.mesh is ArrayMesh and not bodies.has(body.mesh), "ten unique faceted body meshes")
		_check(body.mesh == other_body.mesh and body.material_override == other_body.material_override, "instances share immutable body mesh and paint")
		bodies.append(body.mesh)
		_check(visual.find_children("Wheel*", "MeshInstance3D", true, false).size() == 4, "each design has four wheels")
		var size := Models.dimensions(model)
		unique_widths[size.x] = true
		_check(is_equal_approx(size.x, expected_widths[model]), "per-model width contract: " + Models.display_name(model))
		var kind_size: Vector3 = [Vector3(2.0, 1.05, 4.4), Vector3(2.4, 1.9, 5.0), Vector3(2.8, 1.4, 4.8)][Models.kind_for_model(model) - 1]
		_check(is_equal_approx(size.y, kind_size.y) and is_equal_approx(size.z, kind_size.z), "height and length category preserved")
		if model < 3:
			_check(size.is_equal_approx(kind_size), "original three vehicle footprints unchanged")
		_check(is_equal_approx(body.mesh.get_aabb().size.x, size.x), "visible body uses the full per-model width")
		_check(actor._collision.shape.size.is_equal_approx(size), "catalog matches actual collision dimensions")
		for part in visual.find_children("*", "MeshInstance3D", true, false):
			var bounds: AABB = part.mesh.get_aabb()
			for corner in range(8):
				var point: Vector3 = actor.global_transform.affine_inverse() * part.global_transform * bounds.get_endpoint(corner)
				_check(absf(point.x) <= size.x * 0.5 + 0.025 and absf(point.z) <= size.z * 0.5 + 0.025 and point.y <= size.y + 0.175, "readable geometry stays inside collision envelope: " + Models.display_name(model) + "/" + part.name)
		var signature: String = ["RearLightBar", "VerticalTail", "TailHook", "TripleTail", "LTailUpright", "SquareTail", "VerticalTail", "PickupTail", "RoundTail", "RectangularTail"][model]
		var lights := visual.find_children(signature + "*", "MeshInstance3D", true, false)
		_check(not lights.is_empty(), "approved rear signature: " + Models.display_name(model))
		for light in lights:
			var material := light.material_override as StandardMaterial3D
			_check(material.emission_enabled and material.emission.r > 0.9, "traffic rear lights remain red")
		if model == Models.Model.APEX:
			_check(lights.size() == 4 and visual.has_node("ApexRearWing"), "Apex has four round tails and tall wing")
		if model == Models.Model.HAULER:
			_check(visual.has_node("OpenBedFloor") and visual.has_node("Tailgate") and visual.find_children("BedSide*", "MeshInstance3D", false, false).size() == 2, "pickup has open bed with two sides and tailgate")
	_check(unique_widths.size() == Models.COUNT, "all ten models have distinct physical widths")
	var count := _node_count(actor)
	var mesh_counts := Vector3i(Meshes._hulls.size(), Meshes._boxes.size(), Meshes._cylinders.size())
	var material_count: int = Models._materials.size()
	for cycle in range(500):
		var model := cycle % Models.COUNT
		actor.deactivate()
		actor.activate(Vector3.ZERO, Models.kind_for_model(model), 0.0, model)
		_check(_node_count(actor) == count, "all warmed designs reuse fixed nodes")
	_check(Vector3i(Meshes._hulls.size(), Meshes._boxes.size(), Meshes._cylinders.size()) == mesh_counts and Models._materials.size() == material_count, "geometry and paint cache never grow with activation")
	_check(count < 620, "ten-design pool slot remains bounded")
	actor.activate(Vector3.ZERO, Obstacle.Kind.POTHOLE)
	_check(actor.model_id == -1 and actor.get_node("PotholeVisual").visible, "static hazards hide every model")
	for model in actor._model_visuals:
		_check(not actor._model_visuals[model].visible, "static activation hides traffic")
	actor.player_hit.connect(func(): collisions += 1)
	actor.near_miss.connect(func(_points: int, _clearance: float): near_misses += 1)
	actor.activate(Vector3(0, 0, 8), Obstacle.Kind.WIDE, 0.0, Models.Model.APEX)
	actor.racing = true
	_check(actor.advance_pass(-16.0, 0.0) and collisions == 1 and actor.pass_collided, "signed rival sweep catches head-on relative crossing")
	_check(is_equal_approx(actor.position.z, actor.half_length + actor.PLAYER_HALF_LENGTH), "backwards contact stops at leading footprint rather than overshooting")
	actor.activate(Vector3(0, 0, 20), Obstacle.Kind.WIDE, 0.0, Models.Model.APEX)
	actor.racing = true
	_check(not actor.advance_pass(-30.0, 12.0) and collisions == 1, "negative sweep interpolates lateral position only during longitudinal overlap")
	var close_x := Obstacle.PLAYER_HALF_WIDTH + Models.dimensions(Models.Model.APEX).x * 0.5 + 0.2
	actor.activate(Vector3(0, 0, -8), Obstacle.Kind.WIDE, close_x, Models.Model.APEX)
	actor.racing = true
	actor.advance_pass(16.0, close_x)
	await process_frame
	actor.advance_pass(-16.0, close_x)
	await process_frame
	_check(near_misses == 0, "rival back-and-forth passes never farm near-miss rewards")
	actor.racing = false
	actor.advance_pass(16.0, close_x)
	actor.racing = true
	await process_frame
	_check(near_misses == 0, "queued reward is canceled when actor becomes race rival")
	actor.deactivate()
	_check(not actor.racing, "deactivation resets racing state")
	actor.free()
	second.free()
	await process_frame
	await _test_width_contacts()
	if failures == 0:
		print("TRAFFIC MODELS PASS: ten distinct widths/designs, approved rear signatures, collision envelopes, real and swept narrow/wide contacts, shared meshes/materials, 500 stable reuses, signed rival contact and no race reward farming (%d nodes)" % count)
	if failures == 0 and OS.get_cmdline_user_args().has("--capture"):
		await _capture_catalog()
	quit(1 if failures else 0)


func _test_width_contacts() -> void:
	var player = load("res://scripts/player_car.gd").new()
	root.add_child(player)
	player.position.x = 3.0
	var actor := Obstacle.new()
	root.add_child(actor)
	var events: Dictionary = {"hits": 0, "awards": [], "clearances": []}
	actor.player_hit.connect(func(): events.hits += 1)
	actor.near_miss.connect(func(points: int, clearance: float):
		events.awards.append(points)
		events.clearances.append(clearance))
	actor.activate(Vector3.ZERO, Models.kind_for_model(Models.Model.VECTOR), 3.0, Models.Model.VECTOR)
	for frame in range(4):
		await physics_frame
	_check(events.hits == 0 and actor.active, "real 1.8m Vector leaves a gap for player at x3.0")
	actor.advance_pass(8.0, 3.0)
	await process_frame
	_check(events.awards == [250] and is_equal_approx(events.clearances[0], 0.45), "Vector physical footprint produces 0.45m close-pass clearance")
	actor.activate(Vector3.ZERO, Models.kind_for_model(Models.Model.HAULER), 3.0, Models.Model.HAULER)
	for frame in range(4):
		await physics_frame
	_check(events.hits == 1 and actor.pass_collided and not actor.active, "real 3.2m Hauler overlaps same player position by 0.25m")
	_check(events.awards == [250], "wide-body contact earns no close-pass points")
	actor.activate(Vector3(0, 0, -8), Models.kind_for_model(Models.Model.VECTOR), 3.0, Models.Model.VECTOR)
	_check(not actor.advance_pass(16.0, 3.0), "Vector swept pass clears same x3.0 path")
	await process_frame
	_check(events.awards == [250, 250] and is_equal_approx(events.clearances[-1], 0.45), "Vector sweep uses its narrow width for reward tier")
	actor.activate(Vector3(0, 0, -8), Models.kind_for_model(Models.Model.HAULER), 3.0, Models.Model.HAULER)
	_check(actor.advance_pass(16.0, 3.0) and events.hits == 2 and is_equal_approx(actor.minimum_clearance, -0.25), "Hauler sweep catches wider body on identical path")
	await process_frame
	_check(events.awards == [250, 250], "swept wide collision suppresses near-miss reward")
	# Each model's own edge, rather than its old physics category, decides contact.
	for model in [Models.Model.VECTOR, Models.Model.HAULER]:
		var edge: float = Obstacle.PLAYER_HALF_WIDTH + Models.dimensions(model).x * 0.5
		actor.activate(Vector3(0, 0, -8), Models.kind_for_model(model), edge + 0.01, model)
		_check(not actor.advance_pass(16.0, edge + 0.01), "one centimetre beyond model edge stays clear")
		await process_frame
		_check(is_equal_approx(actor.minimum_clearance, 0.01) and events.awards[-1] == 500, "model edge drives extremely-close reward")
		actor.activate(Vector3(0, 0, -8), Models.kind_for_model(model), edge - 0.01, model)
		_check(actor.advance_pass(16.0, edge - 0.01) and is_equal_approx(actor.minimum_clearance, -0.01), "one centimetre inside model edge collides")
	actor.free()
	player.free()
	await process_frame

func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 15:
			push_error("TRAFFIC MODELS FAIL: " + label)


func _capture_catalog() -> void:
	root.content_scale_size = Vector2i(1600, 1000)
	root.size = Vector2i(1600, 1000)
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#100d27")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#b6bfd9")
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -32, 0)
	sun.light_color = Color("#f5d8e5")
	sun.light_energy = 1.1
	stage.add_child(sun)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 28.0
	camera.position = Vector3(9, 21, 27)
	camera.look_at(Vector3(0, 0, -2.8))
	camera.current = true
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#171827")
	Meshes.box(stage, "Floor", Vector3(0, -0.11, -3), Vector3(32, 0.2, 23), ground_material)
	for model in range(Models.COUNT):
		var visual := Models.build(model)
		stage.add_child(visual)
		visual.position = Vector3((model % 5 - 2) * 5.2, 0, -float(model / 5) * 10.0 + 2)
		var label := Label3D.new()
		label.text = "%02d  %s  /  %.1f m" % [model + 1, Models.display_name(model), Models.dimensions(model).x]
		label.font_size = 36
		label.pixel_size = 0.008
		label.modulate = Color("#e2e6ff")
		label.position = visual.position + Vector3(0, 0.07, 3.3)
		label.rotation_degrees.x = -90
		label.no_depth_test = true
		stage.add_child(label)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image().save_png("res://tests/traffic_models.png")
	_check(result == OK, "ten-model contact sheet saved")
	stage.free()
	await process_frame
	print("TRAFFIC MODELS CAPTURE: res://tests/traffic_models.png")
