extends SceneTree
## Combined real game ticks: Apex, moving/generated traffic and swept radar.

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if game.tutorial == null or game.touch_controls == null or game.audio == null:
		push_error("Main scene failed initialization; high-speed interaction checks cannot run")
		game.free()
		await process_frame
		quit(1)
		return
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.set_process(false)
	var fixed_road_nodes: int = game.road.get_child_count()
	for kmh in [450.0, 600.0, 800.0, 936.8]:
		game.run_seed = 771
		game.start_game(false)
		var boosted: bool = kmh > 900.0
		var initial_speed: float = kmh / 3.6
		var cruise: float = initial_speed - (38.0 if boosted else 0.0)
		game.run_seconds = _run_age(game.director, cruise)
		game.speed = initial_speed
		for actor in game.obstacles.obstacle_pool:
			actor.deactivate()
		game.obstacles.configure_progression(initial_speed, game.run_seconds)
		game.obstacles._next_row_z = -game.obstacles.spawn_ahead
		var rival: RoadObstacle = game.obstacles._take_obstacle()
		rival.activate(Vector3(5.0, 0.0, -15.0), RoadObstacle.Kind.WIDE, 0.0, game.TrafficModels.Model.APEX)
		var moving: RoadObstacle = game.obstacles._take_obstacle()
		moving.activate(Vector3(-5.0, 0.0, -60.0), RoadObstacle.Kind.CAR, 0.0)
		# No artificial fine dispatch: this boundary is crossed by actual motion.
		game.enforcement.sector_at = initial_speed * 0.2
		game.enforcement.radar_at = initial_speed * 0.45
		game.enforcement.sector_end = initial_speed * 10.0
		game.enforcement.next_limit = 200
		game.enforcement.radar_pending = true
		var non_traffic_nodes: int = _count(game) - _count(game.obstacles)
		var saw_combined := false
		var saw_radar_crossing := false
		var saw_traffic_motion := false
		var saw_generated_traffic := false
		var maximum_pool := 0
		var minimum_speed := INF
		var maximum_speed := 0.0
		_key(KEY_SHIFT, boosted)
		for frame in range(72):
			var before_distance: float = game.distance
			var previous_z: float = moving.position.z
			var was_active: bool = moving.active
			var previous_fines: int = game.enforcement.fine_points
			game.player._physics_process(1.0 / 60.0)
			game._physics_process(1.0 / 60.0)
			await process_frame
			minimum_speed = minf(minimum_speed, game.speed)
			maximum_speed = maxf(maximum_speed, game.speed)
			maximum_pool = maxi(maximum_pool, game.obstacles.obstacle_pool.size())
			for actor in game.obstacles.obstacle_pool:
				saw_generated_traffic = saw_generated_traffic or (actor.active and actor != rival and actor != moving)
			if was_active and moving.active:
				var expected_motion: float = game.distance - before_distance - moving.cruise_speed / 60.0
				saw_traffic_motion = saw_traffic_motion or moving.position.z > previous_z
				_check(absf(moving.position.z - previous_z - expected_motion) < 0.001, "signed traffic motion follows actual speed at %.1f km/h" % kmh)
			if game.enforcement.fine_points > previous_fines:
				saw_radar_crossing = before_distance < game.enforcement.radar_at and game.distance >= game.enforcement.radar_at
				_check(game.pursuit.active and game.apex_race.active, "swept radar starts police during Apex at %.1f km/h" % kmh)
				saw_combined = game.pursuit.active and game.apex_race.active
			_check(game.state == game.GameState.PLAYING and game.progress.damage_remaining == 0.0, "clear lane preserves the run at %.1f km/h" % kmh)
			_check(is_finite(game.speed) and is_finite(game.distance) and is_finite(game.progress.distance_points) and game.get_score() >= 0, "finite combined-interaction state at %.1f km/h" % kmh)
			_check(game.obstacles.obstacle_pool.size() <= 20 and game.pursuit.units.size() <= 3, "bounded traffic and police at %.1f km/h" % kmh)
			_check(game.road.get_child_count() == fixed_road_nodes and _count(game) <= non_traffic_nodes + 1 + 20 * 620, "bounded world and catalog nodes at %.1f km/h" % kmh)
		_key(KEY_SHIFT, false)
		_check(saw_combined and saw_radar_crossing and saw_traffic_motion, "actual Apex, radar and traffic interact at %.1f km/h" % kmh)
		_check(saw_generated_traffic, "generation continues alongside active Apex and police at %.1f km/h" % kmh)
		_check(minimum_speed * 3.6 >= kmh - 1.0 and maximum_speed * 3.6 <= kmh + 1.0, "actual physics maintains the requested %.1f km/h scenario" % kmh)
		_check(game.progress.score_penalty == game.enforcement.fine_points and game.enforcement.fine_points > 0, "actual fine reaches score at %.1f km/h" % kmh)
		_check(game.apex_race.clean and game.apex_race.countdown_remaining > 0.0 and game.apex_race.elapsed == 0.0, "radar preserves clean race countdown at %.1f km/h" % kmh)
		_check(game.progress.ranked_eligible and not game.progress.infinite_boost, "high speed remains ranked with finite fuel at %.1f km/h" % kmh)
		if boosted:
			_check(game.progress.boost_charge < 0.4 and game.progress.boost_charge > 0.0 and game.progress.boosting, "800 km/h plus Boost uses actual finite charge")
		var snapshot := _snapshot(game)
		game.pause_game()
		game.player._physics_process(5.0)
		game._physics_process(5.0)
		_check(_snapshot(game) == snapshot, "pause freezes combined high-speed systems at %.1f km/h" % kmh)
		game.resume_game()
		game._physics_process(1.0 / 60.0)
		_check(game.distance > float(snapshot.distance) and game.apex_race.countdown_remaining < float(snapshot.countdown), "resume restores world and race motion at %.1f km/h" % kmh)
		print("HIGH SPEED INTERACTIONS %.1f km/h actual %.1f..%.1f fine %d heat %d pool %d Apex+police %s" % [kmh, minimum_speed * 3.6, maximum_speed * 3.6, game.enforcement.fine_points, game.heat.level(), maximum_pool, saw_combined])
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	print("HIGH SPEED INTERACTIONS PASS" if failures == 0 else "HIGH SPEED INTERACTIONS FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _run_age(director, cruise: float) -> float:
	# Establish the actual curve age instead of forcing a stale fixed speed.
	var low := 0.0
	var high := 14400.0
	for step in range(48):
		var middle := (low + high) * 0.5
		if director.get_base_speed(0.0, middle) < cruise:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5

func _snapshot(game) -> Dictionary:
	var actors: Array = []
	for actor in game.obstacles.obstacle_pool:
		actors.append([actor.active, actor.position, actor.cruise_speed])
	return {"distance": game.distance, "seconds": game.run_seconds, "speed": game.speed, "score": game.get_score(), "fuel": game.progress.boost_charge, "fines": game.enforcement.fine_points, "gap": game.pursuit.gap_m, "capture": game.pursuit.capture_fraction, "countdown": game.apex_race.countdown_remaining, "actors": actors}

func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 12:
			push_error(label)
