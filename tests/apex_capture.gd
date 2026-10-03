extends SceneTree

const Models = preload("res://scripts/traffic_models.gd")
const Race = preload("res://scripts/apex_race.gd")
const STEP := 1.0 / 60.0

var failures: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.run_seed = 2468
	game.obstacles.spawning_enabled = false
	_start_race(game, false)
	_check(game.apex_race.active and game.apex_ui.notification_panel.visible, "real pooled Apex starts challenge")
	_check(game.apex_race.actor.model_id == Models.Model.APEX and game.apex_race.actor.position == Vector3(-5, 0, -13), "challenge uses the actual Apex model beside the player")
	await _save("apex_challenge.png")
	var popup: Rect2 = game.apex_ui.notification_panel.get_global_rect()
	_check(not popup.has_point(game.camera.unproject_position(game.apex_race.actor.position + Vector3.UP)), "side popup leaves visible Apex unobscured")
	_check(not popup.has_point(game.camera.unproject_position(game.player.position + Vector3.UP)), "side popup leaves visible player unobscured")
	_check("/7.0s" in game.apex_ui.requirements_label.text and game.apex_ui.opponent_panel.visible, "challenge shows chosen7s target and live rival")
	_check(game.apex_ui.opponent_road_floor.material_override == game.road.materials.road, "feed backdrop reuses actual highway material")
	# Test fixture fuel refills stand in for already earned near-miss charge.
	# The game's real boost input, speed, elapsed time and finish rules still run.
	_key(true)
	for tick in range(420):
		if tick in [120, 240, 360]:
			game.progress.boost_charge = 1.0
		_ticks(game, 1)
	_key(false)
	_ticks(game, 1380)
	_check(game.state == game.GameState.PLAYING and not game.apex_race.active, "clean boosted thirty-second race completes without ending run")
	_check(game.apex_ui.notification_title.text == "APEX DEFEATED" and not game.pursuit.active, "actual boost and clean driving defeat Apex")
	_check(game.progress.bonus_points == Race.POINTS and is_equal_approx(game.progress.reward_boost_remaining, Race.REWARD_SECONDS), "win grants the real points and unlimited boost reward")
	_check(game.apex_ui.reward_panel.visible and game.ui.boost_meter.value == 100.0, "reward is visible in both quest timer and boost meter")
	await _save("apex_win.png")
	_start_race(game, false)
	for fixture in [{"lead": -180.0, "file": "apex_rival_ahead.png"}, {"lead": 180.0, "file": "apex_rival_behind.png"}, {"lead": 24.0, "file": "apex_near_rival.png"}]:
		var rival: RoadObstacle = game.apex_race.actor
		rival.position.z = fixture.lead
		game._update_apex_race(0.0)
		game.apex_ui.notification_remaining = 0.0
		for tick in range(120):
			game._process(STEP)
		game.apex_ui._process(0.0)
		_check(game.apex_ui.opponent_panel.visible and game.apex_ui.opponent_view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "actual rival feed remains live in every distance fixture")
		_check(("AHEAD" if fixture.lead < 0.0 else "BEHIND") in game.apex_ui.opponent_caption.text, "rival feed labels actual direction")
		_check(rival.position.z == fixture.lead, "feed tracking preserves real rival position")
		await _save(fixture.file)
		_check(_feed_has_car(game.apex_ui.opponent_view), "actual rival image is rendered rather than an empty feed")
		_check(_feed_has_road(game.apex_ui.opponent_view), "far rival remains on rendered asphalt in feed")
		_check((game.camera.cull_mask & game.apex_ui.FEED_ROAD_LAYER) == 0, "main camera excludes feed-only road backdrop")
	_start_race(game, true)
	_ticks(game, 1800)
	_check(game.state == game.GameState.PLAYING and not game.apex_race.active, "unboosted Secret race ends after thirty seconds")
	_check(game.apex_ui.notification_title.text == "APEX WINS" and game.pursuit.active, "actual Secret loss starts the moving police chase")
	_check(game.community.rearview_panel.visible and game.apex_ui.notification_panel.visible, "Secret loss shows both police mirror and taunt")
	_check(game.progress.bonus_points == 0 and game.progress.reward_boost_remaining == 0.0, "loss grants no win rewards")
	_check(not game.apex_ui.opponent_panel.visible and game.apex_ui.opponent_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "police chase does not retain the rival screen")
	await _save("apex_secret_loss.png")
	_key(false)
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	if failures == 0:
		print("APEX CAPTURE PASS:7s target, live actual rival feed ahead/behind, nearby rival framing, actual7s boosted victory and reward,30s unboosted Secret loss without rival retention")
	quit(1 if failures else 0)


func _start_race(game: Node3D, secret: bool) -> void:
	_key(false)
	game.start_game()
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.run_mode = game.GameMode.SECRET if secret else game.GameMode.FAIR
	game.ui.configure_secret(secret)
	game.ui.configure_mode(game.run_mode)
	game.world.set_secret_level(secret)
	game.progress.reset()
	game.progress.boost_charge = 1.0
	game.distance = 2000.0
	game.progress.distance_points = game.distance * 10.0
	game.speed = 62.0
	game.road.advance(game.distance)
	# Settle the ordinary game camera before freezing automatic presentation.
	for tick in range(120):
		game._process(STEP)
	game.set_process(false)
	var opponent := game.obstacles._take_obstacle() as RoadObstacle
	opponent.activate(Vector3(-5, 0, -13), RoadObstacle.Kind.CAR, game.player.position.x, Models.Model.APEX)
	game._update_apex_race(0.0)
	game.apex_race.required_boost_seconds = 7.0
	game.apex_ui.show_challenge(opponent.position.x, 7.0)
	game._sync_apex_ui()
	game.ui.update_hud(game.get_score(), roundi(game.speed * 3.6), game.progress.multiplier, game.progress.boost_charge)


func _ticks(game: Node3D, count: int) -> void:
	for tick in range(count):
		game._physics_process(STEP)
		game._process(STEP)
		# Match presentation clocks to the manually advanced driving time.
		game.apex_ui._process(STEP)
		if game.ui._feedback_tween and game.ui._feedback_tween.is_valid():
			game.ui._feedback_tween.custom_step(STEP)


func _save(file_name: String) -> void:
	# Let deferred collision flags, viewport cameras and canvas layout settle.
	for frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png("res://tests/" + file_name) == OK, "rendered capture saved: " + file_name)


func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("APEX CAPTURE FAIL: " + label)


func _feed_has_car(view: SubViewport) -> bool:
	var frame := view.get_texture().get_image()
	var brightest := 0.0
	var darkest := 1.0
	for y in range(0, frame.get_height(), 4):
		for x in range(0, frame.get_width(), 4):
			var pixel := frame.get_pixel(x, y)
			brightest = maxf(brightest, maxf(pixel.r, maxf(pixel.g, pixel.b)))
			darkest = minf(darkest, maxf(pixel.r, maxf(pixel.g, pixel.b)))
	return brightest > 0.4 and darkest < 0.2


func _feed_has_road(view: SubViewport) -> bool:
	var frame := view.get_texture().get_image()
	var asphalt_pixels := 0
	var sampled_pixels := 0
	for y in range(frame.get_height() - 24, frame.get_height(), 4):
		for x in range(20, frame.get_width() - 20, 4):
			var pixel := frame.get_pixel(x, y)
			if pixel.b > pixel.r * 1.2 and pixel.g > pixel.r * 0.9:
				asphalt_pixels += 1
			sampled_pixels += 1
	return asphalt_pixels > sampled_pixels / 3
