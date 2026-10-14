extends SceneTree

const Models = preload("res://scripts/traffic_models.gd")

var failures: int = 0
var left_pressed: bool = false
var right_pressed: bool = false
var route_has_safe_transition: bool = true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var cold_start := Time.get_ticks_usec()
	var cold := OS.get_cmdline_user_args().has("--cold-benchmark")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.run_seed = 2468
	var unlimited := OS.get_cmdline_user_args().has("--infinite-boost")
	var secret := OS.get_cmdline_user_args().has("--secret")
	var radar_braking := OS.get_cmdline_user_args().has("--radar-braking")
	# The Infinite layout needs its own fixed seed to include a rare Apex.
	if unlimited:
		game.run_seed = 2469
	if secret:
		var config := ConfigFile.new()
		config.set_value("secret_mode", "access_code", "CONTINUOUS-TEST")
		config.save("user://continuous_secret_config.cfg")
		game.access = load("res://scripts/secret_access.gd").new("user://continuous_secret_access.cfg", "user://continuous_secret_config.cfg")
		_check(game.access.unlock("CONTINUOUS-TEST"), "test-only Secret access")
		game.select_mode(2)
	if unlimited:
		game.select_mode(1)
	game.start_game()
	if unlimited:
		_key(KEY_SHIFT, true)
	var initial_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var fixed_nodes: int = _count(game) - _count(game.obstacles)
	# Cold runs deliberately keep the normal three-model startup cache and
	# include lazy construction of additional traffic models in frame timings.
	var vehicle_nodes: int = 620 if cold else _catalog_node_budget()
	var maximum_nodes := 0
	var race_frames := 0
	var races_started := 0
	var previously_racing := false
	var police_frames := 0
	var police_chases := 0
	var previously_pursuing := false
	var safe_radars := 0
	var boosted_frames := 0
	var braking_frames := 0
	var braking_intervals := 0
	var braking_until := -1
	var previously_braking := false
	var frames := 10800
	var benchmark := cold or OS.get_cmdline_user_args().has("--render-benchmark")
	var pursuit_benchmark := benchmark and not cold and secret and OS.get_cmdline_user_args().has("--pursuit")
	var apex_benchmark := benchmark and not cold and OS.get_cmdline_user_args().has("--apex")
	var rendering := benchmark or OS.get_cmdline_user_args().has("--render-soak")
	if benchmark:
		frames = 1800 if cold else 600
	if rendering:
		game.distance = 2300.0
		game.speed = game.director.MAX_CRUISE_SPEED
		game.road.advance(game.distance)
	if OS.get_cmdline_user_args().has("--late-run"):
		game.run_seconds = 3600.0
		game.distance = 180000.0
		game.speed = game.director.get_base_speed(game.distance, game.run_seconds)
	if pursuit_benchmark:
		game.obstacles.spawning_enabled = false
		for obstacle in game.obstacles.obstacle_pool:
			obstacle.deactivate()
		game._secret_impact("BENCHMARK IMPACT", 1000, 30.0)
	if apex_benchmark:
		game.obstacles.spawning_enabled = false
		for obstacle in game.obstacles.obstacle_pool:
			obstacle.deactivate()
		var rival := game.obstacles._take_obstacle() as RoadObstacle
		rival.activate(Vector3(-5, 0, -13), RoadObstacle.Kind.WIDE, game.player.position.x, Models.Model.APEX)
		game._update_apex_race(0.0)
	var start_time := Time.get_ticks_msec()
	var startup_ms := (Time.get_ticks_usec() - cold_start) / 1000.0
	var frame_times: Array[float] = []
	var lazy_frames: Array[float] = []
	var built_models := _built_models(game)
	var observed_models: Dictionary = {}
	var drawn_start := Engine.get_frames_drawn()
	for frame in range(frames):
		var frame_start := Time.get_ticks_usec()
		var radar_was_pending: bool = game.enforcement.radar_pending
		var previous_fines: int = game.enforcement.fine_points
		if radar_braking:
			# React to the actual warning and modulate the real brake key below
			# the approaching limit, including negative traffic approach speeds.
			var warning_distance: float = game.enforcement.radar_at - game.distance
			var needs_limit: bool = game.enforcement.radar_pending and warning_distance <= game.enforcement.warning_distance
			var legal_speed: float = float(game.enforcement.next_limit - 1) / 3.6
			_key(KEY_S, needs_limit and game.speed > legal_speed)
		var target_x := _route_target(game, game.player.position.x)
		if unlimited and not benchmark and not rendering:
			# Release the real boost key when Apex and nearby traffic leave
			# no safe sustained trajectory. Deceleration takes actual time.
			var approaching_apex := false
			for actor in game.obstacles.obstacle_pool:
				if actor.active and actor.model_id == Models.Model.APEX and actor.position.z > -80.0 and actor.position.z < 20.0:
					approaching_apex = true
			var safe_hold := false
			if approaching_apex:
				for lane_x in game.obstacles.LANE_CENTERS:
					if _safe_steering_time(game, game.player.position.x, lane_x) >= 2.0:
						safe_hold = true
			if (approaching_apex and not safe_hold) or not route_has_safe_transition:
				braking_until = maxi(braking_until, frame + 90)
			var braking := frame < braking_until
			if braking:
				braking_frames += 1
				if not previously_braking:
					braking_intervals += 1
			_key(KEY_SHIFT, not braking)
			previously_braking = braking
		var velocity: float = game.player.lateral_velocity
		_set_steer(_steering_to(target_x - game.player.position.x, velocity, game.player.steering_release))
		await physics_frame
		await process_frame
		if cold:
			var frame_ms := (Time.get_ticks_usec() - frame_start) / 1000.0
			frame_times.append(frame_ms)
			var now_built := _built_models(game)
			if now_built > built_models:
				lazy_frames.append(frame_ms)
			built_models = now_built
			for actor in game.obstacles.obstacle_pool:
				if actor.active and actor.model_id >= 0:
					observed_models[actor.model_id] = true
		if game.progress.boosting:
			boosted_frames += 1
		if radar_was_pending and not game.enforcement.radar_pending and game.enforcement.fine_points == previous_fines:
			safe_radars += 1
		if game.pursuit.active:
			police_frames += 1
			if not previously_pursuing:
				police_chases += 1
		previously_pursuing = game.pursuit.active
		if game.state != game.GameState.PLAYING:
			print("AUTOPILOT CONTACT: frame=%d player=%.3f speed=%.3f target=%.3f velocity=%.3f" % [frame, game.player.position.x, game.speed, target_x, velocity])
			for actor in game.obstacles.obstacle_pool:
				if actor.active or actor.pass_collided:
					print("  actor model=%d x=%.3f z=%.3f speed=%.3f race=%s hit=%s" % [actor.model_id, actor.position.x, actor.position.z, actor.cruise_speed, actor.racing, actor.pass_collided])
			_check(false, "autopilot survives reachable traffic, frame %d" % frame)
			break
		if game.apex_race.active:
			race_frames += 1
			if not previously_racing:
				races_started += 1
		previously_racing = game.apex_race.active
		if frame % 120 == 0:
			var nodes: int = _count(game)
			maximum_nodes = maxi(maximum_nodes, nodes)
			_check(nodes <= fixed_nodes + 1 + vehicle_nodes * game.obstacles.MAX_POOL_SIZE, "bounded complete scene nodes")
			_check(int(Performance.get_monitor(Performance.MEMORY_STATIC)) < initial_memory + 24 * 1024 * 1024, "bounded live memory")
			_check(game.obstacles.obstacle_pool.size() <= game.obstacles.MAX_POOL_SIZE, "bounded live traffic")
	if not benchmark and not rendering:
		if radar_braking:
			_check(safe_radars >= 2 and game.enforcement.fine_points == 0, "responsive warning/brake driver clears radars without fines")
		else:
			# The speeding driver exercises pursuit, including concurrent Apex;
			# generated finite-fuel races also isolate the actual win conditions.
			_check(police_chases > 0 and police_frames > 0 and game.enforcement.fine_points > 0, "seeded survival exercises real radar police and score penalties")
		if unlimited and not radar_braking:
			_check(boosted_frames >= frames * 0.90, "Infinite endurance sustains boost for at least 90 percent of frames")
	_set_steer(0)
	_key(KEY_SHIFT, false)
	_key(KEY_S, false)
	var elapsed := (Time.get_ticks_msec() - start_time) / 1000.0
	var rendered_frames := Engine.get_frames_drawn() - drawn_start
	if cold:
		_check(rendered_frames > 0, "cold benchmark requires actual rendering")
		frame_times.sort()
		lazy_frames.sort()
		var report := {
			"engine": Engine.get_version_info().string,
			"gpu": RenderingServer.get_video_adapter_name(),
			"window": str(root.size),
			"startup_ms": startup_ms,
			"frames": frame_times.size(),
			"drawn_frames": rendered_frames,
			"median_ms": _percentile(frame_times, 0.5),
			"p95_ms": _percentile(frame_times, 0.95),
			"p99_ms": _percentile(frame_times, 0.99),
			"maximum_ms": frame_times.back(),
			"lazy_build_frames": lazy_frames.size(),
			"lazy_build_maximum_ms": _percentile(lazy_frames, 1.0),
			"observed_models": observed_models.keys(),
			"seed": game.obstacles.active_seed,
		}
		DirAccess.make_dir_recursive_absolute("res://.godot/validation")
		var output := FileAccess.open("res://.godot/validation/cold-benchmark.json", FileAccess.WRITE)
		_check(output != null, "cold benchmark report opens")
		if output != null:
			output.store_string(JSON.stringify(report, "\t"))
			output.close()
		_check(lazy_frames.size() > 0 and observed_models.size() >= 4, "cold benchmark exercises real additional traffic construction")
		print("COLD TRAFFIC BENCHMARK: " + JSON.stringify(report))
	var final_distance: float = game.distance
	if pursuit_benchmark:
		_check(game.pursuit.active and game.community.rearview_panel.visible, "live police mirror stays active throughout the short benchmark")
	if apex_benchmark:
		_check(game.apex_race.active and game.apex_ui.opponent_panel.visible, "live Apex screen remains active throughout rendered benchmark")
	game.return_to_menu()
	game.audio.stop_all()
	# Fixed-FPS simulation runs faster than the audio mix thread's real clock.
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("CONTINUOUS PASS: %s, %d physics frames, %.2f km, max %d nodes, stable memory; %d races/%d race frames%s" % ["Secret" if secret else ("Infinite Boost" if unlimited else "Fair"), frames, final_distance / 1000.0, maximum_nodes, races_started, race_frames, "; %d drawn frames / %.1f rendered fps" % [rendered_frames, rendered_frames / maxf(elapsed, 0.001)] if rendering else ""])
		print("RADAR ENCOUNTERS: %d police chases / %d police frames; %d safe radars" % [police_chases, police_frames, safe_radars])
		if unlimited and not benchmark and not rendering:
			print("INFINITE INPUT: %d boosted frames; %d release frames across %d intervals" % [boosted_frames, braking_frames, braking_intervals])
	quit(1 if failures > 0 else 0)


func _catalog_node_budget() -> int:
	var models = load("res://scripts/traffic_models.gd")
	var meshes = load("res://scripts/vehicle_mesh.gd")
	var fixture = load("res://scripts/obstacle.gd").new()
	root.add_child(fixture)
	for model in range(models.COUNT):
		fixture.activate(Vector3(20, 0, -300), models.kind_for_model(model), 0.0, model)
	var nodes := _count(fixture)
	var cache_sizes := Vector3i(meshes._hulls.size(), meshes._boxes.size(), meshes._cylinders.size())
	var materials: int = models._materials.size()
	for model in range(models.COUNT):
		fixture.activate(Vector3(20, 0, -300), models.kind_for_model(model), 0.0, model)
	_check(_count(fixture) == nodes and nodes < 620, "finite complete traffic catalog per pool slot")
	_check(Vector3i(meshes._hulls.size(), meshes._boxes.size(), meshes._cylinders.size()) == cache_sizes and models._materials.size() == materials, "warmed catalog mesh/material caches are stable")
	fixture.free()
	return nodes


func _route_target(game, player_x: float) -> float:
	var spawner = game.obstacles
	var rows: Dictionary = {}
	for obstacle in spawner.obstacle_pool:
		if not obstacle.active:
			continue
		var extent: float = obstacle.half_length + obstacle.PLAYER_HALF_LENGTH
		var closing_speed: float = game.speed - obstacle.cruise_speed
		var encounter_time := 0.0
		var clear_time := INF
		if is_zero_approx(closing_speed):
			if absf(obstacle.position.z) > extent:
				continue
		else:
			var first: float = (-extent - obstacle.position.z) / closing_speed
			var second: float = (extent - obstacle.position.z) / closing_speed
			clear_time = maxf(first, second)
			if clear_time < 0.0:
				# Pulling-away traffic has no encounter. Recompute immediately
				# if its actual speed changes on a later physics frame.
				continue
			encounter_time = maxf(0.0, minf(first, second))
		var row_key := "rival" if obstacle.racing else str(snappedf(obstacle.position.z, 0.001))
		if not rows.has(row_key):
			rows[row_key] = {"time": encounter_time, "clear": clear_time, "blocked": []}
		rows[row_key].time = minf(rows[row_key].time, encounter_time)
		rows[row_key].clear = maxf(rows[row_key].clear, clear_time)
		# Live physical footprints also occupy intermediate positions during
		# Apex turns. Exact lane lookup previously returned -1 for the rival.
		for lane in range(3):
			var lateral_extent: float = obstacle.half_width + obstacle.PLAYER_HALF_WIDTH + 0.25
			if absf(spawner.LANE_CENTERS[lane] - obstacle.position.x) < lateral_extent:
				if not rows[row_key].blocked.has(lane):
					rows[row_key].blocked.append(lane)
	var positions: Array = rows.keys()
	positions.sort_custom(func(first, second): return rows[first].time > rows[second].time)
	var viable: Array[int] = [0, 1, 2]
	var next_entry := INF
	# Stay in one common clear lane across overlapping occupancy windows.
	# Otherwise allow the real acceleration, crossing and braking time.
	for row_time in positions:
		var previous: Array[int] = []
		for lane in range(3):
			if rows[row_time].blocked.has(lane):
				continue
			for next_lane in viable:
				var distance: float = absf(spawner.LANE_CENTERS[next_lane] - spawner.LANE_CENTERS[lane])
				if lane == next_lane or next_entry - rows[row_time].clear >= _lane_change_time(game, distance):
					previous.append(lane)
					break
		viable = previous
		next_entry = rows[row_time].time
	var best_x := player_x
	var best_safety := -1.0
	var smallest := INF
	route_has_safe_transition = false
	# Verify the immediate transition separately from the multi-row route:
	# an end lane can be clear while crossing the center would hit Apex.
	for lane in range(3):
		var lane_x: float = spawner.LANE_CENTERS[lane]
		var horizon := _lane_change_time(game, absf(lane_x - player_x)) + 0.10
		var safety := _safe_steering_time(game, player_x, lane_x, horizon)
		if safety >= horizon and viable.has(lane):
			route_has_safe_transition = true
		safety = 1.0 if safety >= horizon else safety / horizon
		var preference := absf(lane_x - player_x) + (0.0 if viable.has(lane) else 20.0)
		if safety > best_safety + 0.001 or (is_equal_approx(safety, best_safety) and preference < smallest):
			best_safety = safety
			smallest = preference
			best_x = lane_x
	return best_x


func _steering_to(difference: float, velocity: float, release: float) -> int:
	var braking_distance := velocity * velocity / (2.0 * release)
	if absf(difference) > braking_distance + 0.07 or velocity * difference < 0.0:
		return 1 if difference > 0.0 else -1
	return 0


func _lane_change_time(game, distance: float) -> float:
	var speed: float = game.player.max_lateral_speed
	return distance / speed + speed / (2.0 * game.player.steering_acceleration) + speed / (2.0 * game.player.steering_release) + 0.05


func _safe_steering_time(game, player_x: float, target_x: float, horizon: float = 2.0) -> float:
	const STEP := 1.0 / 60.0
	var projected_x := player_x
	var velocity: float = game.player.lateral_velocity
	for tick in range(1, int(ceil(horizon / STEP)) + 1):
		var elapsed := tick * STEP
		var previous_x := projected_x
		var steer := _steering_to(target_x - projected_x, velocity, game.player.steering_release)
		velocity = move_toward(velocity, steer * game.player.max_lateral_speed, (game.player.steering_release if steer == 0 else game.player.steering_acceleration) * STEP)
		projected_x = clampf(projected_x + velocity * STEP, -game.player.road_limit, game.player.road_limit)
		if absf(projected_x) >= game.player.road_limit:
			velocity = 0.0
		for actor in game.obstacles.obstacle_pool:
			if not actor.active:
				continue
			var travel: float = game.speed - actor.cruise_speed
			var previous_z: float = actor.position.z + travel * (elapsed - STEP)
			var projected_z: float = actor.position.z + travel * elapsed
			var extent: float = actor.half_length + actor.PLAYER_HALF_LENGTH + 0.15
			if minf(previous_z, projected_z) > extent or maxf(previous_z, projected_z) < -extent:
				continue
			var lateral: float = actor.half_width + actor.PLAYER_HALF_WIDTH + 0.15
			if minf(previous_x, projected_x) < actor.position.x + lateral and maxf(previous_x, projected_x) > actor.position.x - lateral:
				return elapsed
	return horizon

func _set_steer(direction: int) -> void:
	if left_pressed != (direction < 0):
		left_pressed = direction < 0
		_key(KEY_A, left_pressed)
	if right_pressed != (direction > 0):
		right_pressed = direction > 0
		_key(KEY_D, right_pressed)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total


func _built_models(game) -> int:
	var count := 0
	for actor in game.obstacles.obstacle_pool:
		count += actor._model_visuals.size()
	return count


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(values.size() * fraction) - 1, 0, values.size() - 1)] if not values.is_empty() else 0.0


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 5:
			push_error("CONTINUOUS FAIL: " + label)
