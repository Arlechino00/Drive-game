extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var director := DifficultyDirector.new()
	var road := RoadManager.new()
	root.add_child(road)
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	var camera := ChaseCamera.new()
	root.add_child(camera)
	var road_nodes := road.get_child_count()
	for kmh in [300.0, 600.0, 1000.0, 1600.0, 2000.0]:
		var speed: float = kmh / 3.6
		spawner.reset_spawner(roundi(kmh))
		spawner.configure_progression(speed, 3600.0)
		camera.follow(0.0, 0.0, 0.0, speed, false)
		_check(spawner.spawn_ahead >= speed * 4.0, "four seconds of preview at %.0f km/h" % kmh)
		_check(director.get_look_ahead(speed) >= speed * 4.0, "director preview matches high-speed world")
		_check(camera.far > spawner.spawn_ahead + camera.position.z, "camera can show the entire preview")
		var traveled := 0.0
		var fresh_rows := 0
		for tick in range(600):
			var delta := 0.05 if tick % 37 != 0 else 0.5
			traveled += speed * delta
			road.advance(speed * delta)
			spawner.configure_progression(speed, 3600.0 + tick * 0.05)
			spawner.set_speed_limit(30 if tick % 100 < 50 else 0)
			var serials := 0
			for actor in spawner.obstacle_pool:
				serials += actor._activation_serial
			spawner.advance(speed * delta, traveled, 1.0, delta, 20.0)
			var next_serials := 0
			for actor in spawner.obstacle_pool:
				next_serials += actor._activation_serial
			if tick > 300 and next_serials > serials:
				fresh_rows += 1
			var front := INF
			for segment in road.segments:
				front = minf(front, segment.position.z)
			_check(front < -spawner.spawn_ahead - 40.0, "road covers preview through delayed frames")
			_check(road.get_child_count() == road_nodes and spawner.obstacle_pool.size() <= spawner.MAX_POOL_SIZE, "high-speed road and traffic stay bounded")
		_check(fresh_rows > 0, "fresh traffic keeps spawning on long high-speed runs")
		var enforcement := SpeedEnforcement.new()
		enforcement.reset(roundi(kmh))
		enforcement.next_limit = 30
		enforcement.configure_progression(speed, 3600.0)
		var brake_distance := (speed * speed - pow(30.0 / 3.6, 2.0)) / 14.0
		_check(enforcement.warning_distance >= brake_distance + speed, "full braking and reaction budget at %.0f km/h" % kmh)
		# Follow the real warning using one second reaction, then bounded braking.
		enforcement.sector_at = 1.0
		enforcement.radar_at = enforcement.warning_distance
		enforcement.sector_end = enforcement.radar_at + 100.0
		enforcement.radar_pending = true
		var distance := 0.0
		var elapsed := 0.0
		var actual := speed
		while enforcement.radar_pending and elapsed < 180.0:
			var previous := actual
			if elapsed >= 1.0:
				actual = move_toward(actual, 8.0, 7.0 / 60.0)
			distance += actual / 60.0
			elapsed += 1.0 / 60.0
			enforcement.advance(distance, previous, actual)
		_check(not enforcement.radar_pending and enforcement.fine_points == 0, "real warned braking avoids fine at %.0f km/h" % kmh)
	road.free()
	spawner.free()
	camera.free()
	await process_frame
	var localization = load("res://scripts/localization.gd")
	for language in ["en", "ro"]:
		localization.set_language(language)
		for mobile in [false, true]:
			var ui := GameUI.new()
			ui.mobile_mode = mobile
			root.add_child(ui)
			var radar := RadarDisplay.new()
			root.add_child(radar)
			radar.attach(ui)
			ui.show_playing()
			ui.update_hud(99999999, 1600, 5.0, 1.0, true)
			radar.warning_distance = 16000.0
			radar.update_display(0.0, 30, 200, 15999.0, 16000.0, true, 1600.0, false, 9999999)
			for frame in range(4):
				await process_frame
			_check(ui.interface.get_global_rect().encloses(radar.panel.get_global_rect()), "%s long-range radar HUD fits mobile=%s" % [language, mobile])
			radar.free()
			ui.free()
	localization.set_language("en")
	# Approach triggers must survive skipping the old six-metre window and
	# crossing the ordinary pool retirement boundary in a delayed frame.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.set_process(false)
	game.player.set_physics_process(false)
	for entry in [[2000.0, 1.0 / 60.0], [800.0, 0.1], [400.0, 0.1], [1000.0, 0.5]]:
		game.start_game(false)
		game.obstacles.spawning_enabled = false
		for actor in game.obstacles.obstacle_pool:
			actor.deactivate()
		game.enforcement.sector_at = INF
		game.enforcement.radar_at = INF
		game.enforcement.sector_end = INF
		game.speed = float(entry[0]) / 3.6
		var actor: RoadObstacle = game.obstacles._take_obstacle()
		actor.activate(Vector3(-5.0, 0.0, -16.0), RoadObstacle.Kind.WIDE, 0.0, game.TrafficModels.Model.APEX)
		game._physics_process(float(entry[1]))
		_check(game.apex_race.active and actor.active and game.obstacles.race_actor == actor, "actual Apex encounter triggers at %.0f km/h over %.3fs" % entry)
	game.start_game(false)
	game.obstacles.spawning_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.enforcement.sector_at = INF
	game.enforcement.radar_at = INF
	game.enforcement.sector_end = INF
	game.speed = 300.0 / 3.6
	var rival: RoadObstacle = game.obstacles._take_obstacle()
	rival.activate(Vector3(-5.0, 0.0, -13.0), RoadObstacle.Kind.WIDE, 0.0, game.TrafficModels.Model.APEX)
	game._update_apex_race(0.0)
	rival.position.z = 100.0
	game.apex_race.countdown_remaining = 0.0
	game.apex_race.elapsed = 29.9
	game.apex_race.boost_seconds = game.apex_race.required_boost_seconds
	var pothole: RoadObstacle = game.obstacles._take_obstacle()
	pothole.activate(Vector3(0.0, 0.0, -20.0), RoadObstacle.Kind.POTHOLE)
	# The pothole is reached after the finish line inside the same delayed tick.
	game._physics_process(0.5)
	_check(game.apex_ui.notification_title.text == "APEX DEFEATED" and game.progress.reward_boost_remaining > 0.0, "post-finish pothole cannot retroactively lose the race")
	game.return_to_menu()
	game.audio.stop_all()
	# The mixer drains in real time even when simulated frames run uncapped.
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	game = null
	await process_frame
	print("HIGH SPEED BALANCE PASS: 300/600/1000/1600/2000 km/h, road, camera, traffic, radar braking" if failures == 0 else "HIGH SPEED BALANCE FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 10:
			push_error(label)
