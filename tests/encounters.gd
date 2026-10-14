extends SceneTree

const Spawner = preload("res://scripts/obstacle_spawner.gd")
const Obstacle = preload("res://scripts/obstacle.gd")
const Player = preload("res://scripts/player_car.gd")
const Models = preload("res://scripts/traffic_models.gd")
const POTHOLE: int = 4
const ROADWORKS: int = 5
var failures: int = 0
var pothole_hits: int = 0
var roadworks_hits: int = 0
var traffic_hits: int = 0
var near_misses: int = 0
var maximum_pool: int = 0
var seen: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var example = Obstacle.new()
	root.add_child(example)
	_check(example.has_signal("pothole_hit") and example.has_signal("roadworks_entered"), "stationary hazards expose separate collision outcomes")
	if failures:
		example.free()
		quit(1)
		return
	example.free()
	await _test_swept_corner_contacts()
	await _test_swept_close_pass()
	_test_reentrant_contact_reuse()
	_test_nonfatal_contact_motion()
	await _test_hazard_contact()
	await _test_hazard_passes()
	await _test_forwarded_contact()
	await _test_main_scene_corner_contacts()
	_test_disabled_generation()
	_test_delayed_frame()
	_test_seed_and_motion()
	_test_long_runs()
	if failures == 0:
		print("ENCOUNTERS PASS: 60 Hz swept corner outcomes/contact positions/queued callback exclusion, close-pass reward, synchronous pool reuse, keyboard-driven normal/Secret consequences, real pothole/worksite contact and reuse, no hazard near-miss rewards, stationary movement, seed replay, 8 mixed-speed runs/149.6 km, 200 restarts, adjacent routes, encounter separation; maximum pool %d" % maximum_pool)
	quit(1 if failures else 0)


func _test_swept_corner_contacts() -> void:
	var player = Player.new()
	root.add_child(player)
	player.set_physics_process(false)
	var obstacle = Obstacle.new()
	root.add_child(obstacle)
	var outcomes: Array[int] = []
	var contact_positions: Array[Vector3] = []
	var rewards: Array[int] = []
	obstacle.player_hit.connect(func():
		outcomes.append(Obstacle.Kind.CAR)
		contact_positions.append(obstacle.position))
	obstacle.pothole_hit.connect(func():
		outcomes.append(POTHOLE)
		contact_positions.append(obstacle.position))
	obstacle.roadworks_entered.connect(func():
		outcomes.append(ROADWORKS)
		contact_positions.append(obstacle.position))
	obstacle.near_miss.connect(func(points, _clearance): rewards.append(points))
	# No endpoint overlap, but corners touch within a 60 Hz tick around actual edges.
	for fixture in _corner_fixtures():
		player.position.x = fixture.x
		obstacle.activate(Vector3(0.0, 0.0, fixture.z), fixture.kind, fixture.x)
		for frame in range(4):
			await physics_frame
		var before := outcomes.size()
		_check(before == contact_positions.size() and obstacle.active, "corner fixture starts before contact")
		# Simulate a physical callback already queued for this same encounter.
		obstacle.area_entered.emit.call_deferred(player)
		player.position.x += 15.0 / 60.0
		obstacle.advance_pass(fixture.movement, player.position.x)
		_check(outcomes.size() == before + 1 and outcomes.back() == fixture.kind, "60 Hz corner contact delivers its hazard outcome synchronously")
		_check(not obstacle.active and obstacle.pass_collided, "swept contact deactivates the pooled encounter")
		_check(is_equal_approx(obstacle.position.z, fixture.contact_z), "swept contact retains the first contact position for aftermath")
		if contact_positions.size() > before:
			_check(is_equal_approx(contact_positions[before].z, fixture.contact_z), "collision listener observes the contact position before emission")
		for frame in range(4):
			await physics_frame
		obstacle.advance_pass(30.0, 6.2)
		_check(outcomes.size() == before + 1, "queued Area callback cannot duplicate the swept outcome")
		_check(rewards.is_empty() and not obstacle.pass_awarded, "corner contact never earns a near-miss reward")
		_check(is_equal_approx(obstacle.position.z, fixture.contact_z), "inactive contact does not move after collision")
	player.free()
	obstacle.free()


func _test_swept_close_pass() -> void:
	var obstacle = Obstacle.new()
	root.add_child(obstacle)
	var outcomes: Array[int] = []
	var rewards: Array[int] = []
	obstacle.player_hit.connect(func(): outcomes.append(1))
	obstacle.near_miss.connect(func(points, _clearance): rewards.append(points))
	var fixture: Dictionary = _corner_fixtures()[0]
	var safe_x: float = fixture.x + 0.075
	obstacle.activate(Vector3(0.0, 0.0, fixture.z), Obstacle.Kind.CAR, safe_x)
	obstacle.advance_pass(66.0 / 60.0, safe_x + 0.25)
	_check(outcomes.is_empty() and not obstacle.pass_collided and obstacle.active, "non-overlapping corner remains a safe close pass")
	for frame in range(10):
		obstacle.advance_pass(66.0 / 60.0, safe_x + 0.25)
		await process_frame
	_check(rewards == [500] and outcomes.is_empty(), "safe 60 Hz close pass earns exactly one normal near-miss reward")
	obstacle.free()


func _test_reentrant_contact_reuse() -> void:
	var spawner = Spawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(81)
	spawner.spawning_enabled = false
	for obstacle in spawner.obstacle_pool:
		obstacle.deactivate()
	var source = spawner.obstacle_pool[0]
	var following = spawner.obstacle_pool[1]
	var fixture: Dictionary = _corner_fixtures()[0]
	source.activate(Vector3(0.0, 0.0, fixture.z), Obstacle.Kind.CAR, fixture.x)
	following.activate(Vector3(0.0, 0.0, -30.0), Obstacle.Kind.CAR, fixture.x)
	var outcomes: Array[int] = []
	spawner.player_hit.connect(func():
		outcomes.append(source.kind)
		# A synchronous consumer can reset/reuse the pool during emission.
		source.activate(Vector3(5.0, 0.0, -90.0), POTHOLE, 6.2)
		following.activate(Vector3(-5.0, 0.0, -120.0), ROADWORKS, 6.2))
	spawner.advance(80.0 / 60.0, 0.0, 1.0, 1.0 / 60.0, fixture.x + 0.25)
	_check(outcomes == [Obstacle.Kind.CAR], "spawner forwards one swept contact before reentrant pool reuse")
	_check(source.position.is_equal_approx(Vector3(5.0, 0.0, -90.0)) and source.active and not source.pass_collided, "old sweep cannot mutate a newly activated pooled obstacle")
	_check(following.position.is_equal_approx(Vector3(-5.0, 0.0, -120.0)), "contact stops spawner mutation after synchronous callback")
	spawner.free()


func _test_nonfatal_contact_motion() -> void:
	var spawner = Spawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(81)
	for obstacle in spawner.obstacle_pool:
		obstacle.deactivate()
	var fixture: Dictionary = _corner_fixtures()[0]
	# Place two parts of a future row around the hit actor in pool order.
	var before = spawner._take_obstacle()
	before.activate(Vector3(-5.0, 0.0, -70.0), Obstacle.Kind.CAR, fixture.x)
	var source = spawner._take_obstacle()
	source.activate(Vector3(0.0, 0.0, fixture.z), Obstacle.Kind.CAR, fixture.x)
	var after = spawner._take_obstacle()
	after.activate(Vector3(5.0, 0.0, -70.0), Obstacle.Kind.CAR, fixture.x)
	var serial: int = source._activation_serial
	# Generation is due this tick, but must not immediately reuse the hit actor.
	spawner._next_row_z = -285.5
	spawner.advance(80.0 / 60.0, 0.0, 1.0, 1.0 / 60.0, fixture.x + 0.25)
	_check(is_equal_approx(before.position.z, -68.9) and is_equal_approx(after.position.z, -68.9), "surviving an impact advances every other actor and keeps a row aligned")
	_check(not source.active and source._activation_serial == serial, "hit actor is not reused during the same advancement tick")
	spawner.free()


func _test_main_scene_corner_contacts() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	game.player.set_physics_process(false)
	game.obstacles.spawning_enabled = false
	var config := ConfigFile.new()
	config.set_value("secret_mode", "access_code", "SWEEP-CONTACT-TEST")
	_check(config.save("user://sweep_access_config.cfg") == OK, "sweep integration config is isolated")
	game.access = load("res://scripts/secret_access.gd").new("user://sweep_access.cfg", "user://sweep_access_config.cfg")
	_check(game.access.unlock("SWEEP-CONTACT-TEST"), "sweep integration can enter Secret Mode")
	var outcomes: Array[int] = []
	game.obstacles.player_hit.connect(func(): outcomes.append(Obstacle.Kind.CAR))
	game.obstacles.pothole_hit.connect(func(): outcomes.append(POTHOLE))
	game.obstacles.roadworks_entered.connect(func(): outcomes.append(ROADWORKS))
	for mode in [game.GameMode.INFINITE_BOOST, game.GameMode.SECRET]:
		for fixture in _corner_fixtures():
			game.selected_mode = mode
			game.start_game()
			for obstacle in game.obstacles.obstacle_pool:
				obstacle.deactivate()
			game.distance = 650.0
			game.speed = 80.0
			game.progress.distance_points = 3000.0
			game.player.position.x = fixture.x
			game.player.lateral_velocity = 15.0
			var source = game.obstacles._take_obstacle()
			source.activate(Vector3(0.0, 0.0, fixture.z), fixture.kind, fixture.x)
			for frame in range(4):
				await physics_frame
			var before := outcomes.size()
			_key(KEY_D, true)
			_key(KEY_SHIFT, true)
			game.player.set_physics_process(true)
			game.set_physics_process(true)
			await physics_frame
			await process_frame
			_key(KEY_D, false)
			_key(KEY_SHIFT, false)
			_check(outcomes.size() == before + 1 and outcomes.back() == fixture.kind and not source.active, "production steering/world tick delivers one swept corner outcome")
			_check(game.obstacles.last_hit_obstacle == source and game.progress.near_misses == 0, "game receives the actual contact without a near reward")
			if fixture.kind == POTHOLE:
				_check(game.state == game.GameState.PLAYING and game.speed < 65.0 and game.progress.pothole_remaining > 9.9, "main-scene swept first pothole applies score/speed/window penalties")
				_check(game.get_score() < 2600 and not game.pursuit.active, "first swept pothole preserves ordinary warning rules in both modes")
			elif mode == game.GameMode.SECRET:
				_check(game.state == game.GameState.PLAYING and game.pursuit.active and game.speed < 60.0 and game.get_score() < 2400, "Secret swept traffic/worksite contact starts penalized pursuit")
			else:
				_check(game.state == game.GameState.GAME_OVER and game.aftermath.active and not game.player.active, "ordinary swept traffic/worksite contact stops run with police response")
				if fixture.kind == ROADWORKS:
					_check(not game.progress.score_valid and game.get_score() == 0, "ordinary swept worksite contact disqualifies score")
				else:
					_check(game.aftermath.wreck_kind == Obstacle.Kind.CAR and is_equal_approx(source.position.z, fixture.contact_z), "ordinary swept traffic aftermath retains source kind/contact position")
			for frame in range(4):
				await physics_frame
			await process_frame
			_check(outcomes.size() == before + 1, "real physical callbacks after the sweep cannot repeat its game consequence")
			game.set_physics_process(false)
			game.player.set_physics_process(false)
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _test_hazard_contact() -> void:
	var player = Player.new()
	root.add_child(player)
	var obstacle = Obstacle.new()
	root.add_child(obstacle)
	obstacle.connect("pothole_hit", func(): pothole_hits += 1)
	obstacle.connect("roadworks_entered", func(): roadworks_hits += 1)
	obstacle.player_hit.connect(func(): traffic_hits += 1)
	for hazard_kind in [POTHOLE, ROADWORKS, POTHOLE]:
		obstacle.activate(Vector3.ZERO, hazard_kind)
		for frame in range(4):
			await physics_frame
		_check(not obstacle.active and obstacle.pass_collided, "physical hazard contact deactivates the pooled encounter")
		obstacle.area_entered.emit(player)
		await physics_frame
	_check(pothole_hits == 2 and roadworks_hits == 1 and traffic_hits == 0, "hazards report their own outcome exactly once per activation")
	player.free()
	obstacle.free()


func _test_hazard_passes() -> void:
	var obstacle = Obstacle.new()
	root.add_child(obstacle)
	obstacle.near_miss.connect(func(_points, _clearance): near_misses += 1)
	for hazard_kind in [POTHOLE, ROADWORKS]:
		var side_x := 3.15 if hazard_kind == POTHOLE else 3.85
		obstacle.activate(Vector3(0, 0, -20), hazard_kind, side_x)
		_check(is_zero_approx(obstacle.cruise_speed), "road hazard is stationary in the world")
		_check(is_equal_approx(obstacle.half_width, 1.3 if hazard_kind == POTHOLE else 2.0), "hazard footprint fits a single lane")
		_check(is_equal_approx(obstacle.half_length, 1.5 if hazard_kind == POTHOLE else 6.0), "hazard collision covers its visible footprint")
		var visual: Node3D = obstacle.get_node("PotholeVisual" if hazard_kind == POTHOLE else "RoadworksVisual")
		_check(visual.visible, "activation presents the hazard model")
		for part in visual.find_children("*", "MeshInstance3D", true, false):
			var bounds: AABB = part.mesh.get_aabb()
			for corner in range(8):
				var point: Vector3 = obstacle.global_transform.affine_inverse() * (part.global_transform * bounds.get_endpoint(corner))
				_check(absf(point.x) <= obstacle.half_width + 0.025 and absf(point.z) <= obstacle.half_length + 0.025, "visible hazard remains within the single-lane collision footprint")
		obstacle.advance_pass(32.0, side_x)
		await process_frame
	_check(near_misses == 0, "passing potholes and worksites cannot earn traffic near-miss points")
	obstacle.free()


func _test_forwarded_contact() -> void:
	var spawner = Spawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(43)
	var player = Player.new()
	root.add_child(player)
	var source = spawner.obstacle_pool[0]
	var forwarded: Array[int] = []
	spawner.connect("pothole_hit", func(): forwarded.append(spawner.get("last_hit_obstacle").kind))
	spawner.connect("roadworks_entered", func(): forwarded.append(spawner.get("last_hit_obstacle").kind))
	spawner.player_hit.connect(func(): forwarded.append(spawner.get("last_hit_obstacle").kind))
	for hazard_kind in [POTHOLE, ROADWORKS, Obstacle.Kind.CAR]:
		source.activate(Vector3.ZERO, hazard_kind)
		for frame in range(4):
			await physics_frame
		_check(spawner.get("last_hit_obstacle") == source, "forwarded contact carries the actual encounter before emitting")
	_check(forwarded == [POTHOLE, ROADWORKS, Obstacle.Kind.CAR], "spawner preserves each physical collision outcome")
	spawner.reset_spawner(43)
	_check(spawner.get("last_hit_obstacle") == null, "restart clears the collision source")
	player.free()
	spawner.free()


func _test_disabled_generation() -> void:
	var spawner = Spawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(57)
	spawner.spawning_enabled = false
	var source = spawner.obstacle_pool[0]
	source.activate(Vector3(0, 0, -100), POTHOLE)
	var initial_count: int = spawner.obstacle_pool.size()
	spawner.advance(40.0, 40.0, 1.0, 1.0)
	_check(is_equal_approx(source.position.z, -60.0), "disabling generation still advances existing stationary hazards")
	_check(spawner.obstacle_pool.size() == initial_count, "disabled generation cannot allocate new encounters")
	spawner.reset_spawner(57)
	_check(not spawner.spawning_enabled and spawner.get_active_count() == 0, "reset preserves the generation switch for controlled collision tests")
	spawner.free()


func _test_seed_and_motion() -> void:
	var first = Spawner.new()
	var replay = Spawner.new()
	root.add_child(first)
	root.add_child(replay)
	first.reset_spawner(8675309)
	replay.reset_spawner(8675309)
	for step in range(1200):
		var delta := 0.1
		var speed := 27.0 if step % 180 < 60 else 80.0
		var previous: Dictionary = {}
		for obstacle in first.obstacle_pool:
			if obstacle.active:
				previous[obstacle] = Vector3(obstacle.position.z, obstacle.cruise_speed, obstacle.get("_activation_serial"))
		# Generation-only runs stay outside every lane's collision footprint.
		first.advance(speed * delta, 0.0, 1.0, delta, 10.0)
		replay.advance(speed * delta, 0.0, 1.0, delta, 10.0)
		_check(_snapshot(first) == _snapshot(replay), "seed reproduces traffic/static transitions and pooled rows")
		for obstacle in first.obstacle_pool:
			if not obstacle.active:
				continue
			seen[obstacle.kind] = true
			if previous.has(obstacle) and int(previous[obstacle].z) == int(obstacle.get("_activation_serial")):
				_check(absf(obstacle.position.z - previous[obstacle].x - (speed - previous[obstacle].y) * delta) < 0.001, "traffic moves at 14 m/s and stationary encounters track all world movement")
	_check(seen.has(POTHOLE) and seen.has(ROADWORKS), "seeded endless generation actually includes both hazards")
	first.free()
	replay.free()


func _test_delayed_frame() -> void:
	var spawner = Spawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(1001)
	spawner.advance(1000.0, 1000.0, 1.0, 20.0)
	for obstacle in spawner.obstacle_pool:
		if obstacle.active:
			_check(obstacle.position.z <= -70.0, "a delayed frame cannot spawn a fresh encounter onto or behind the player")
	_check_encounters(spawner)
	spawner.free()


func _test_long_runs() -> void:
	for run_seed in range(8):
		var spawner = Spawner.new()
		root.add_child(spawner)
		spawner.reset_spawner(run_seed)
		for step in range(18000):
			# 27 m/s also covers the minimum speed after a pothole penalty.
			var speed := 27.0 if step % 900 < 300 else 80.0
			spawner.advance(speed / 60.0, 0.0, 1.0, 1.0 / 60.0, 10.0)
			maximum_pool = maxi(maximum_pool, spawner.obstacle_pool.size())
			if step % 30 == 0:
				_check_encounters(spawner)
				_check(spawner.obstacle_pool.size() <= 12, "mixed-speed endless encounters retain the spatial pool bound")
				_check(spawner.get_child_count() == spawner.obstacle_pool.size(), "every pooled hazard remains accounted for")
				for obstacle in spawner.obstacle_pool:
					_check(obstacle.player_hit.get_connections().size() == 1 and obstacle.pothole_hit.get_connections().size() == 1 and obstacle.roadworks_entered.get_connections().size() == 1 and obstacle.near_miss.get_connections().size() == 1, "pooled traffic and hazard callbacks connect exactly once")
		for restart in range(25):
			spawner.reset_spawner(run_seed)
			_check_encounters(spawner)
			_check(spawner.obstacle_pool.size() <= 12, "restart reuses the same bounded hazard pool")
		spawner.free()


func _check_encounters(spawner) -> void:
	var rows: Dictionary = {}
	for obstacle in spawner.obstacle_pool:
		if not obstacle.active or obstacle.position.z > 0.0:
			continue
		var z := snappedf(obstacle.position.z, 0.001)
		if not rows.has(z):
			rows[z] = {"lanes": [], "speed": obstacle.cruise_speed, "kinds": [], "half_length": obstacle.half_length}
		var lane: int = [-5.0, 0.0, 5.0].find(obstacle.position.x)
		_check(lane >= 0 and not rows[z].lanes.has(lane), "encounters occupy distinct readable lanes")
		_check(is_equal_approx(rows[z].speed, obstacle.cruise_speed), "a row never mixes traffic and stationary hazards")
		rows[z].lanes.append(lane)
		rows[z].kinds.append(obstacle.kind)
		rows[z].half_length = maxf(rows[z].half_length, obstacle.half_length)
	var positions: Array = rows.keys()
	positions.sort()
	positions.reverse()
	var reachable: Array[int] = [0, 1, 2]
	for index in range(positions.size()):
		var z: float = positions[index]
		_check(rows[z].lanes.size() <= 2, "at most two lanes close at each encounter")
		var next_reachable: Array[int] = []
		for lane in range(3):
			if rows[z].lanes.has(lane):
				continue
			for prior in reachable:
				if absi(lane - prior) <= 1:
					next_reachable.append(lane)
					break
		_check(not next_reachable.is_empty(), "an adjacent safe lane threads all upcoming encounters")
		reachable = next_reachable
		if index == 0:
			continue
		var front: float = positions[index - 1]
		_check(front - z >= 63.99, "actual row positions retain at least 64 m separation")
		# Test catch ordering at both penalty speed and maximum boost; spatial
		# separation alone misses a faster stationary row overtaking traffic.
		for player_speed in [27.0, 44.0, 64.0, 80.0]:
			var front_time: float = -front / (player_speed - float(rows[front].speed))
			var back_time: float = -z / (player_speed - float(rows[z].speed))
			_check((back_time - front_time) * player_speed >= 63.98, "catch times retain a reachable 64 m reaction interval")
			var front_clears: float = (-front + float(rows[front].half_length) + Obstacle.PLAYER_HALF_LENGTH) / (player_speed - float(rows[front].speed))
			var back_enters: float = (-z - float(rows[z].half_length) - Obstacle.PLAYER_HALF_LENGTH) / (player_speed - float(rows[z].speed))
			_check(back_enters - front_clears >= 0.70, "actual collision footprints leave time to finish an adjacent lane change")


func _corner_fixtures() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for kind in [Obstacle.Kind.CAR, POTHOLE, ROADWORKS]:
		var size: Vector3 = Models.dimensions(Models.Model.PULSE) if kind == Obstacle.Kind.CAR else (Vector3(2.6, 0.22, 3.0) if kind == POTHOLE else Vector3(4.0, 1.8, 12.0))
		var edge_x := Obstacle.PLAYER_HALF_WIDTH + size.x * 0.5
		var edge_z := Obstacle.PLAYER_HALF_LENGTH + size.z * 0.5
		result.append({"kind": kind, "x": edge_x - 0.05, "z": -edge_z - 0.1, "movement": (66.0 if kind == Obstacle.Kind.CAR else 80.0) / 60.0, "contact_z": -edge_z})
	return result

func _snapshot(spawner) -> Array[String]:
	var values: Array[String] = []
	for obstacle in spawner.obstacle_pool:
		if obstacle.active:
			values.append("%.3f/%.3f/%d" % [obstacle.position.x, obstacle.position.z, obstacle.kind])
	values.sort()
	return values


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 12:
			push_error("ENCOUNTERS FAIL: " + label)
