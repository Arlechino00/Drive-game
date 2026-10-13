extends SceneTree
## Independent swept-body regressions for traffic advanced before police.
const Pursuit = preload("res://scripts/police_pursuit.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var pursuit := Pursuit.new()
	root.add_child(pursuit)
	var actor := RoadObstacle.new()
	root.add_child(actor)
	await process_frame
	for dt in [1.0 / 60.0, 1.0 / 30.0, 0.1, 0.35]:
		_test_rear(pursuit, actor, dt)
		_test_front(pursuit, actor, dt)
	_test_lateral(pursuit, actor)
	pursuit.free()
	actor.free()
	await _integrated_rear()
	await _integrated_incoming_merge()
	if failures == 0:
		print("POLICE TRAFFIC CONTACTS PASS: symmetric 60Hz contacts, whole-frame substeps, swept bodies and lateral clearance")
	quit(1 if failures else 0)

func _test_rear(pursuit: PolicePursuit, actor: RoadObstacle, dt: float) -> void:
	pursuit.set_heat(0)
	pursuit.begin(Vector3(-5, 0, 0))
	pursuit.units[0].x = 5.0
	pursuit.units[0].z = 6.0
	pursuit.units[0].speed = 8.0
	actor.activate(Vector3(5, 0, 0), RoadObstacle.Kind.CAR, -5.0)
	actor.position.z = 6.0 + Pursuit.HALF_LENGTH + actor.half_length + 0.8
	actor.cruise_speed = 14.0
	var traffic: Array[RoadObstacle] = [actor]
	for frame in range(ceili(1.0 / dt)):
		var from := Vector3(pursuit.units[0].x, 0, pursuit.units[0].z)
		var actor_from := actor.position
		actor.position.z += (8.0 - actor.cruise_speed) * dt
		pursuit.advance(dt, Vector3(-5, 0, 0), 8.0, 8.0, 1.0, traffic)
		var to := Vector3(pursuit.units[0].x, 0, pursuit.units[0].z)
		_check(not _swept_contact(from, to, actor_from, actor.position, actor), "rear traffic stays physically clear at %.3fs" % dt)
		_check(absf(to.x - from.x) <= pursuit.lateral_response * dt + 0.00001, "rear impact cannot teleport police sideways")
		_check(absf(to.z - from.z) <= 6.0 * dt + 0.3, "rear impulse corrects only the bounded contact displacement")
	_check(pursuit.active and pursuit.capture_fraction < 1.0, "rear contact cannot cause instant capture")

func _test_front(pursuit: PolicePursuit, actor: RoadObstacle, dt: float) -> void:
	for kmh in [130.0, 400.0, 800.0]:
		var speed: float = kmh / 3.6
		pursuit.set_heat(0)
		pursuit.begin(Vector3(-5, 0, 0))
		pursuit.units[0].x = 5.0
		pursuit.units[0].z = 6.0
		pursuit.units[0].speed = speed
		actor.activate(Vector3(5, 0, 0), RoadObstacle.Kind.CAR, -5.0)
		actor.position.z = 6.0 - Pursuit.HALF_LENGTH - actor.half_length - 0.8
		actor.cruise_speed = 14.0
		var traffic: Array[RoadObstacle] = [actor]
		for frame in range(ceili(0.7 / dt)):
			var from := Vector3(pursuit.units[0].x, 0, pursuit.units[0].z)
			var actor_from := actor.position
			actor.position.z += (speed - actor.cruise_speed) * dt
			pursuit.advance(dt, Vector3(-5, 0, 0), speed, speed, 1.0, traffic)
			var to := Vector3(pursuit.units[0].x, 0, pursuit.units[0].z)
			_check(not _swept_contact(from, to, actor_from, actor.position, actor), "front traffic cannot phase through police at %.0fkm/h %.3fs" % [kmh, dt])
			_check(absf(to.x - from.x) <= pursuit.lateral_response * dt + 0.00001, "front traffic avoidance has finite lateral movement")
			_check(absf(to.z - from.z) <= (speed - actor.cruise_speed) * dt + 0.3, "front impact corrects only the bounded contact displacement")
		_check(pursuit.active, "traffic collision does not instantly arrest the driver")

func _test_lateral(pursuit: PolicePursuit, actor: RoadObstacle) -> void:
	pursuit.begin(Vector3(5, 0, 0))
	pursuit.units[0].x = 0.0
	pursuit.units[0].z = 25.0
	pursuit.units[0].speed = 45.0
	actor.activate(Vector3(3, 0, 25), RoadObstacle.Kind.CAR, 5.0)
	actor.cruise_speed = 45.0
	var traffic: Array[RoadObstacle] = [actor]
	for frame in range(60):
		var from := Vector3(pursuit.units[0].x, 0, pursuit.units[0].z)
		pursuit.advance(1.0 / 60.0, Vector3(5, 0, 0), 45.0, 45.0, 1.0, traffic)
		var to := Vector3(pursuit.units[0].x, 0, pursuit.units[0].z)
		_check(not _swept_contact(from, to, actor.position, actor.position, actor), "swept lane change never enters adjacent traffic")
		_check(absf(to.z - from.z - (45.0 - pursuit.units[0].speed) / 60.0) < 0.00001, "adjacent traffic cannot create a longitudinal collision teleport")

func _integrated_rear() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.set_process(false)
	game.start_game(false)
	game.obstacles.spawning_enabled = false
	for obstacle in game.obstacles.obstacle_pool:
		obstacle.deactivate()
	game.enforcement.sector_at = INF
	game.enforcement.sector_end = INF
	game.enforcement.radar_at = INF
	game.player.position.x = -5.0
	game.speed = 8.0
	game.pursuit.begin(game.player.position)
	game.pursuit.units[0].x = 5.0
	game.pursuit.units[0].z = 6.0
	game.pursuit.units[0].speed = 8.0
	var actor = game.obstacles._take_obstacle()
	actor.activate(Vector3(5, 0, 0), RoadObstacle.Kind.CAR, -5.0)
	actor.position.z = 6.0 + Pursuit.HALF_LENGTH + actor.half_length + 0.8
	_key(true)
	for frame in range(60):
		var from := Vector3(game.pursuit.units[0].x, 0, game.pursuit.units[0].z)
		var actor_from: Vector3 = actor.position
		game._physics_process(1.0 / 60.0)
		var to := Vector3(game.pursuit.units[0].x, 0, game.pursuit.units[0].z)
		_check(not _swept_contact(from, to, actor_from, actor.position, actor), "real Brake and traffic-first game order preserve rear bumper separation at 60Hz")
	_key(false)
	game.return_to_menu()
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await process_frame
	game.free()
	await process_frame

func _integrated_incoming_merge() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.set_process(false)
	_check(game.obstacles.pursuit == game.pursuit, "game shares the existing bounded police units with traffic")
	for scenario in range(4):
		var dt := 1.0 / 60.0 if scenario % 2 == 0 else 0.1
		var unit_index := 0 if scenario < 2 else 2
		game.start_game(false)
		game.obstacles.spawning_enabled = false
		for obstacle in game.obstacles.obstacle_pool:
			obstacle.deactivate()
		game.enforcement.sector_at = INF
		game.enforcement.sector_end = INF
		game.enforcement.radar_at = INF
		game.speed = 45.0
		game.player.position.x = -5.0
		game.obstacles._mixed_wave = true
		game.obstacles.traffic_speed = 45.0
		game.obstacles._target_traffic_speed = 45.0
		game.pursuit.set_heat(0 if unit_index == 0 else 4)
		game.pursuit.begin(game.player.position)
		for unit in game.pursuit.units:
			unit.z = 180.0
		game.pursuit.units[unit_index].x = 5.0
		game.pursuit.units[unit_index].z = -40.0
		game.pursuit.units[unit_index].speed = 45.0
		var actor = game.obstacles._take_obstacle()
		actor.activate(Vector3(0, 0, -40), RoadObstacle.Kind.CAR, -5.0)
		actor.cruise_speed = 45.0
		actor.lane_target = 5.0
		var held := false
		for frame in range(ceili(0.7 / dt)):
			var from := Vector3(game.pursuit.units[unit_index].x, 0, game.pursuit.units[unit_index].z)
			var actor_from: Vector3 = actor.position
			game._physics_process(dt)
			var to := Vector3(game.pursuit.units[unit_index].x, 0, game.pursuit.units[unit_index].z)
			held = held or is_equal_approx(actor.position.x, actor_from.x)
			_check(not _swept_contact(from, to, actor_from, actor.position, actor), "incoming mixed merge preserves both swept bodies at %.3fs" % dt)
			_check(absf(actor.position.x - actor_from.x) <= 5.0 * dt + 0.00001 and absf(to.x - from.x) <= game.pursuit.lateral_response * dt + 0.00001, "merge guard cannot teleport either vehicle sideways")
		_check(held and actor.lane_target == 5.0, "nearby police hold traffic's turn without cancelling its target")
		game.pursuit.units[unit_index].z = 160.0
		var before: float = actor.position.x
		for frame in range(3):
			game._physics_process(dt)
		_check(actor.position.x > before, "incoming traffic retries its existing merge after police clear")
	game.return_to_menu()
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await process_frame
	game.free()
	await process_frame

func _swept_contact(from: Vector3, to: Vector3, other_from: Vector3, other_to: Vector3, actor: RoadObstacle) -> bool:
	for sample in range(65):
		var difference := from.lerp(to, sample / 64.0) - other_from.lerp(other_to, sample / 64.0)
		if absf(difference.x) < Pursuit.HALF_WIDTH + actor.half_width - 0.00001 and absf(difference.z) < Pursuit.HALF_LENGTH + actor.half_length - 0.00001:
			return true
	return false

func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_S
	event.physical_keycode = KEY_S
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		if failures <= 12:
			push_error("POLICE TRAFFIC CONTACTS FAIL: " + label)
