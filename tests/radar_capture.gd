extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.obstacles.spawning_enabled = false
	game.run_seed = 42
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = window_size
		game.start_game()
		_clear(game)
		game.enforcement.next_limit = 30
		game.enforcement.sector_at = 60.0
		game.enforcement.radar_at = 140.0
		game.enforcement.radar_pending = true
		game.enforcement.sector_end = 400.0
		game.speed = 80.0
		game.ui.update_hud(2500, 288)
		game.radar_display.update_display(0.0, 0, 30, 60.0, 140.0, true, 288.0, false, 0)
		await _save(game, "warning", window_size)
		game.radar_display.update_display(110.0, 30, 30, 60.0, 140.0, true, 28.8, true, 0)
		game.speed = 8.0
		game.ui.update_hud(2500, 29)
		await _save(game, "braking", window_size)
		game.speed = 200.0 / 3.6
		game.ui.update_hud(2500, 200)
		game.radar_display.update_display(110.0, 200, 200, 60.0, 140.0, true, 200.0, false, 0)
		await _save(game, "sector200", window_size)
		game.radar_display.update_display(110.0, 50, 50, 60.0, INF, false, 200.0, false, 0)
		await _save(game, "speeding_no_radar", window_size)
		game.start_game()
		_clear(game)
		game.enforcement.next_limit = 80
		game.enforcement.sector_at = 1.0
		game.enforcement.radar_at = 2.0
		game.enforcement.radar_pending = true
		game.enforcement.sector_end = 400.0
		game.speed = 62.0
		game._physics_process(0.1)
		_check(game.pursuit.active and game.enforcement.fine_points > 0, "real radar crossing produces fine and police")
		await _save(game, "police", window_size)
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	print("RADAR CAPTURE PASS" if failures == 0 else "RADAR CAPTURE FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _save(game, state_name: String, window_size: Vector2i) -> void:
	for frame in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	var hud: RadarDisplay = game.radar_display
	var rect: Rect2 = hud.panel.get_global_rect()
	_check(rect.end.x <= game.ui.interface.size.x * game.ui.interface.scale.x + 1.0, "radar panel stays inside scaled UI")
	for label in [hud.radar_label, hud.upcoming_label, hud.brake_label, hud.fine_label]:
		_check(rect.encloses(label.get_global_rect()), "radar text fits panel at %d" % window_size.x)
	_check(hud.limit_label.get_parent().get_global_rect().encloses(hud.limit_label.get_global_rect()), "three-digit limit fits its badge")
	_check(not rect.intersects(game.ui.feedback.get_global_rect()), "radar clears central feedback")
	_check(not rect.intersects(game.ui.hazard_warning.get_global_rect()), "radar clears pothole warning")
	_check(root.get_texture().get_image().save_png("res://tests/radar_%s_%d.png" % [state_name, window_size.x]) == OK, "capture saved")


func _clear(game) -> void:
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.player.active = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
