extends "res://tests/continuous.gd"
## Real generated traffic, ordinary finite starter fuel, and actual steering.
## Only the initial Apex encounter is a fixture; later rows come from spawner.

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	for seed_id in [4, 12]:
		for required in range(4, 8):
			game.run_seed = seed_id
			game.start_game(false)
			# Isolate generated finite-fuel race play from radar interruption.
			game.enforcement.sector_at = INF
			game.enforcement.radar_at = INF
			game.enforcement.sector_end = INF
			game.distance = 2000.0
			# Race at the former cruising pace on the continuous Stage Two curve.
			# Distance alone no longer implies a max-speed plateau.
			game.run_seconds = 630.0
			game.speed = game.director.get_base_speed(game.distance, game.run_seconds)
			var actor := game.obstacles._take_obstacle() as RoadObstacle
			actor.activate(Vector3(-5, 0, -13), RoadObstacle.Kind.WIDE, game.player.position.x, Models.Model.APEX)
			game._update_apex_race(0.0)
			game.apex_race.required_boost_seconds = float(required)
			var max_boost := 0.0
			var min_fuel: float = game.progress.boost_charge
			var race_finished := false
			var driving_frames := 0
			for frame in range(2000):
				var target := _earned_fuel_target(game)
				_set_steer(_steering_to(target - game.player.position.x, game.player.lateral_velocity, game.player.steering_release))
				# Count only fuel actually drained during racing. Release after an
				# empty tank to obey the real empty-lock input behavior.
				var request: bool = game.apex_race.countdown_remaining == 0.0 and game.apex_race.boost_seconds < required + 0.1 and not game.progress.boost_empty_lock
				_key(KEY_SHIFT, request)
				Input.flush_buffered_events()
				game.player._physics_process(1.0 / 60.0)
				game._physics_process(1.0 / 60.0)
				driving_frames += 1
				max_boost = maxf(max_boost, game.apex_race.boost_seconds)
				min_fuel = minf(min_fuel, game.progress.boost_charge)
				await process_frame
				if game.state != game.GameState.PLAYING or not game.apex_race.active:
					race_finished = true
					break
			_key(KEY_SHIFT, false)
			_set_steer(0)
			_check(race_finished and game.state == game.GameState.PLAYING and game.apex_ui.notification_title.text == "APEX DEFEATED", "generated finite-fuel victory seed %d target %d" % [seed_id, required])
			_check(max_boost >= required - 0.02 and game.progress.near_misses > 0 and not game.progress.infinite_boost and min_fuel >= 0.0, "earned close-pass fuel meets target %d for seed %d" % [required, seed_id])
			_check(game.progress.damage_remaining == 0.0 and not game.pursuit.active, "clean generated race survives real contacts")
			_check(driving_frames == 1980 and actor.position.z > 0.0, "generated win retains exactly three countdown plus thirty race seconds and a real positive lead")
			_check(is_equal_approx(game.progress.reward_boost_remaining, 10.0) and game.progress.bonus_points >= 20000, "generated win grants its actual ten-second reward and points")
			print("GENERATED APEX seed=%d target=%d result=%s boost=%.2f nearpasses=%d fuel=%.3f points=%d frames=%d lead=%.2f state=%d end=%s" % [seed_id, required, game.apex_ui.notification_title.text, max_boost, game.progress.near_misses, game.progress.boost_charge, game.progress.bonus_points, driving_frames, actor.position.z, game.state, game.end_reason])
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("APEX GENERATED PASS: two live-row seeds, every 4-7s target, real steering, finite starter fuel and earned close-pass refills, swept/Area collisions enabled")
	quit(1 if failures else 0)


func _earned_fuel_target(game) -> float:
	var player_x: float = game.player.position.x
	var closest: RoadObstacle
	var encounter := INF
	for obstacle in game.obstacles.obstacle_pool:
		if not obstacle.active or obstacle.racing:
			continue
		var closing: float = game.speed - obstacle.cruise_speed
		var extent: float = obstacle.half_length + obstacle.PLAYER_HALF_LENGTH
		if closing <= 0.0 or obstacle.position.z > extent:
			continue
		var time: float = maxf(0.0, (-extent - obstacle.position.z) / closing)
		if time < encounter:
			encounter = time
			closest = obstacle
	if closest == null:
		return _route_target(game, player_x)
	var best := player_x
	var preference := INF
	# A 0.25m footprint clearance is visible, earns actual refill, and leaves
	# room for real steering/braking error. Static hazards need the same space.
	for side in [-1.0, 1.0]:
		var target: float = closest.position.x + side * (closest.half_width + closest.PLAYER_HALF_WIDTH + 0.25)
		if absf(target) > game.player.road_limit:
			continue
		var horizon := _lane_change_time(game, absf(target - player_x)) + 0.10
		if _safe_steering_time(game, player_x, target, horizon) < horizon:
			continue
		if absf(target - player_x) < preference:
			preference = absf(target - player_x)
			best = target
	return best if preference != INF else _route_target(game, player_x)
