extends SceneTree

const Models = preload("res://scripts/traffic_models.gd")
var failures: int = 0
var captures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(960, 540)
	root.size = Vector2i(960, 540)
	var game = load("res://scenes/main.tscn").instantiate()
	game.mobile_mode = true
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.run_seed = 42
	_configure_test_access(game)
	for screen in [Vector2i(854, 480), Vector2i(960, 540), Vector2i(2400, 1080)]:
		root.content_scale_size = screen
		root.size = screen
		await _settle()
		game.ui._resize_interface()
		game.return_to_menu()
		game.select_mode(game.GameMode.FAIR)
		await _save(game, "menu", screen)
		game.community.request_name("Android driver")
		await _save(game, "name", screen)
		_check(game.community.name_input.virtual_keyboard_enabled, "name field supports Android keyboard")
		game.community.dismiss()
		game.community.request_access()
		await _save(game, "access", screen)
		game.community.access_input.text = "MOBILE-CAPTURE-ACCESS"
		game.community.access_input.text_submitted.emit(game.community.access_input.text)
		_check(game.access.secret_unlocked and not game.community.is_modal_open(), "access keyboard submission unlocks the configured test mode")
		game.select_mode(game.GameMode.FAIR)
		var entries: Array[Dictionary] = []
		for index in range(10):
			entries.append({"name": "Driver with long name %02d" % index, "score": 1234567890 - index * 10000, "distance": 12000.0, "escapes": 3})
		game.community.show_leaderboard(entries, 0)
		await _save(game, "leaderboard", screen)
		_check(game.community.leaderboard_rows.get_child_count() == 10, "phone ranking displays all ten fixture entries")
		game.community.dismiss()
		game.community.show_leaderboard(entries, 2, true)
		await _save(game, "resumed_leaderboard", screen)
		_check(game.community.resumed_filter.visible and game.community.resumed_filter.button_pressed, "phone Secret ranking displays the resumed filter")
		game.community.dismiss()
		game.ui._open_settings(game.ui.menu)
		await _save(game, "settings", screen)
		game.ui.set_settings_save_notice("Changes could not be saved. Check writable storage.")
		await _save(game, "settings_save_failure", screen)
		game.ui.set_settings_save_notice("")
		game.ui._close_settings()
		_start(game)
		game.speed = 300.0 / 3.6
		game.ui.update_hud(23500, 300, 2.0, 0.65)
		game.radar_display.update_display(game.distance, 0, 30, game.distance + 60.0, game.distance + 140.0, true, 300.0, false, 0)
		await _save(game, "driving", screen)
		game.enforcement.sector_at = game.distance + 1.0
		game.enforcement.radar_at = game.distance + 2.0
		game.enforcement.radar_pending = true
		game.enforcement.next_limit = 30
		game.enforcement.sector_end = game.distance + 400.0
		game._physics_process(0.1)
		_check(game.pursuit.active and game.community.rearview_panel.visible, "capture exercises actual radar pursuit")
		await _save(game, "pursuit", screen)
		game.pause_game()
		await _save(game, "paused", screen)
		_check(not game.touch_controls.is_visible_in_tree(), "pause hides driving touch controls")
		_start(game)
		var rival: RoadObstacle = game.obstacles._take_obstacle()
		rival.activate(Vector3(-5.0, 0.0, -13.0), RoadObstacle.Kind.CAR, game.player.position.x, Models.Model.APEX)
		game._update_apex_race(0.0)
		await _save(game, "apex_challenge", screen)
		_check("BOOST" in game.apex_ui.notification_detail.text and not "Shift" in game.apex_ui.notification_detail.text, "mobile Apex challenge names the touch boost control")
		game.apex_ui.notification_remaining = 0.0
		game.apex_ui._process(0.0)
		_check(game.apex_ui.race_panel.visible and game.apex_ui.opponent_panel.visible, "capture exercises actual Apex status and live feed")
		await _save(game, "apex", screen)
		var viewport := root.get_visible_rect()
		var safe := Rect2(viewport.position + Vector2(40, 0), viewport.size - Vector2(80, 24))
		game.ui._resize_interface(safe)
		await _save(game, "notch", screen, safe)
		game.return_to_menu()
		await _settle()
		_check_menu(game.ui.menu, safe, screen)
		game.community.request_name("Android driver")
		await _settle()
		_check_menu(game.community.name_dialog, safe, screen)
		game.community.dismiss()
		game.ui._open_settings(game.ui.menu)
		await _settle()
		_check_menu(game.ui.settings_menu, safe, screen)
		game.ui._close_settings()
		game.ui._resize_interface()
		await _capture_secret_results(game, screen)
	# Small 854x480 phones get the same full bounds and hit-target checks.
	root.content_scale_size = Vector2i(854, 480)
	root.size = Vector2i(854, 480)
	await _settle()
	game.ui._resize_interface()
	game.return_to_menu()
	await _settle()
	_check_menu(game.ui.menu, root.get_visible_rect(), Vector2i(854, 480))
	_start(game)
	await _settle()
	_check_driving(game, root.get_visible_rect(), Vector2i(854, 480))
	game.return_to_menu()
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	print("MOBILE CAPTURE PASS: %d images, 3 phone sizes, safe-area bounds and HUD separation" % captures if failures == 0 else "MOBILE CAPTURE FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _configure_test_access(game) -> void:
	var config := ConfigFile.new()
	config.set_value("secret_mode", "access_code", "MOBILE-CAPTURE-ACCESS")
	config.set_value("secret_mode", "resume_code", "MOBILE-CAPTURE-RESUME")
	_check(config.save("user://mobile_capture_config.cfg") == OK, "save isolated mobile access configuration")
	DirAccess.remove_absolute("user://mobile_capture_access.cfg")
	game.access = load("res://scripts/secret_access.gd").new("user://mobile_capture_access.cfg", "user://mobile_capture_config.cfg")
	game.access.load_access()
	game.player_name = "Android driver"


func _capture_secret_results(game, screen: Vector2i) -> void:
	game.return_to_menu()
	game.select_mode(game.GameMode.SECRET)
	_start(game)
	game._secret_impact("CAPTURE IMPACT", 1000, 30.0)
	game._physics_process(0.0)
	await _save(game, "secret_pursuit", screen)
	for unit in game.pursuit.units:
		unit.z = 240.0
		unit.speed = 62.0
	game.pursuit.advance(game.pursuit.clean_escape_seconds + 0.2, game.player.position, 62.0, 62.0)
	await _settle()
	_check(game.secret_escapes == 1 and game.state == game.GameState.PLAYING, "phone Secret pursuit reaches the real escape outcome")
	await _save(game, "secret_escape", screen)
	_start(game)
	game._secret_impact("CAPTURE IMPACT", 1000, 30.0)
	game._physics_process(0.0)
	for unit in game.pursuit.units:
		unit.z = 4.0
		unit.x = game.player.position.x
		unit.speed = 0.0
	game.pursuit.advance(game.pursuit.capture_seconds + 1.0, game.player.position, 0.0, 62.0)
	game._process(game.aftermath.arrival_seconds + 0.1)
	_check(game.state == game.GameState.GAME_OVER and game.aftermath.arrived and game.community.resume_button.visible, "phone police arrival reveals the continuation action")
	await _save(game, "secret_caught", screen)
	var save_notice := "Records could not be saved. Close other game windows and check writable storage.\nLeaderboard could not be saved."
	game.ui.show_game_over(game.get_score(), game.best_score, game.distance, game.progress.top_combo, game.progress.near_misses, false, game.end_reason, false, true, save_notice)
	await _save(game, "results_save_failure", screen)
	_check(save_notice in str(game.ui.game_over_menu.get_meta("detail").text), "phone result displays its record-save failure")
	var recovered_notice := "Damaged records were backed up. This run was saved.\nLeaderboard could not be saved."
	game.ui.show_game_over(game.get_score(), game.get_score(), game.distance, game.progress.top_combo, game.progress.near_misses, true, "Your run is complete.", false, false, recovered_notice)
	await _settle()
	_check_menu(game.ui.game_over_menu, root.get_visible_rect(), screen)
	var result_panel: Control = game.ui.game_over_menu.get_meta("panel")
	_check(game.ui.record_label.visible and result_panel.get_global_rect().encloses(game.ui.record_label.get_global_rect()), "new-best recovered result stays inside the phone panel")
	_check(recovered_notice in str(game.ui.game_over_menu.get_meta("detail").text), "new-best phone result displays recovery and leaderboard notices")
	game.ui.show_game_over(game.get_score(), game.best_score, game.distance, game.progress.top_combo, game.progress.near_misses, false, game.end_reason, false, true, save_notice)
	game.community.set_resume_available(true)
	game.community.resume_button.pressed.emit()
	_check(game.community.bribe_dialog.is_visible_in_tree(), "phone continuation button opens its resume-code dialog")
	await _save(game, "resume_code", screen)
	game.community.bribe_input.text = "MOBILE-CAPTURE-RESUME"
	game.community.bribe_input.text_submitted.emit(game.community.bribe_input.text)
	_check(game.run_resumed and game.state == game.GameState.PLAYING, "resume keyboard submission continues the captured phone run")
	await _save(game, "secret_resumed", screen)
	game.return_to_menu()
	game.select_mode(game.GameMode.FAIR)


func _start(game) -> void:
	game.start_game()
	game.obstacles.spawning_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.enforcement.sector_at = INF
	game.enforcement.radar_at = INF
	game.enforcement.sector_end = INF
	game.distance = 2000.0
	game.speed = game.director.get_base_speed(game.distance)
	game.progress.distance_points = game.distance * 10.0
	game.road.advance(game.distance)
	game.ui.update_hud(game.get_score(), roundi(game.speed * 3.6), 1.0, 0.75)
	for tick in range(120):
		game._process(1.0 / 60.0)


func _save(game, state: String, screen: Vector2i, safe: Rect2 = Rect2()) -> void:
	await _settle()
	await RenderingServer.frame_post_draw
	var area := safe if safe.has_area() else root.get_visible_rect()
	for overlay in [game.ui.menu, game.ui.pause_menu, game.ui.game_over_menu, game.ui.settings_menu, game.community.name_dialog, game.community.access_dialog, game.community.bribe_dialog, game.community.leaderboard_dialog]:
		if overlay.is_visible_in_tree():
			_check_menu(overlay, area, screen)
	for field in [game.community.name_input, game.community.access_input, game.community.bribe_input]:
		if field.is_visible_in_tree():
			_check(area.grow(0.5).encloses(field.get_global_rect()), "keyboard field remains inside phone safe area at %s" % screen)
			_check(field.virtual_keyboard_enabled, "phone text field enables native keyboard entry")
			_check(field.get_parent().get_global_rect().encloses(field.get_global_rect()), "phone text field remains inside its dialog content")
	if game.touch_controls.is_visible_in_tree():
		_check_driving(game, area, screen)
	_check(root.get_texture().get_image().save_png("res://tests/mobile_%s_%d.png" % [state, screen.x]) == OK, "save phone %s capture" % state)
	captures += 1


func _settle() -> void:
	for frame in range(12):
		await process_frame


func _check_menu(overlay: ColorRect, safe: Rect2, screen: Vector2i) -> void:
	var panel: Control = overlay.get_meta("panel")
	_check(safe.grow(0.5).encloses(panel.get_global_rect()), "%s panel fits safe area at %s" % [overlay.name, screen])
	var first: Button = overlay.get_meta("first_button")
	var scale: Vector2 = first.get_global_transform().get_scale() * root.get_final_transform().get_scale()
	_check(first.size.y * scale.y >= 42.0, "%s main button remains large at %s" % [overlay.name, screen])
	_check(first.get_theme_font_size("font_size") * scale.y >= 14.0, "%s main caption is readable at %s" % [overlay.name, screen])
	_check(panel.get_global_rect().encloses(first.get_global_rect()), "%s primary button stays inside panel" % overlay.name)
	var detail: Label = overlay.get_meta("detail")
	if detail.is_visible_in_tree():
		_check(panel.get_global_rect().grow(0.5).encloses(detail.get_global_rect()), "%s detail stays inside its phone panel" % overlay.name)
	if overlay.has_meta("footer"):
		var footer: Label = overlay.get_meta("footer")
		_check(panel.get_global_rect().grow(0.5).encloses(footer.get_global_rect()), "%s footer stays inside its phone panel" % overlay.name)


func _check_driving(game, safe: Rect2, screen: Vector2i) -> void:
	var critical: Array = [game.ui.speed_label, game.ui.score_label, game.ui.boost_meter.get_parent(), game.radar_display.panel, game.community.rearview_panel, game.apex_ui.race_panel, game.apex_ui.opponent_panel, game.apex_ui.reward_panel, game.apex_ui.notification_panel]
	for panel in critical:
		if panel.is_visible_in_tree():
			_check(safe.grow(0.5).encloses(panel.get_global_rect()), "%s remains inside safe phone area at %s" % [panel.name, screen])
	for first_index in range(critical.size()):
		var first: Control = critical[first_index]
		if not first.is_visible_in_tree():
			continue
		for second_index in range(first_index + 1, critical.size()):
			var second: Control = critical[second_index]
			if second.is_visible_in_tree():
				_check(not first.get_global_rect().intersects(second.get_global_rect()), "%s does not obscure %s at %s" % [first.name, second.name, screen])
	if game.radar_display.panel.is_visible_in_tree():
		for label in [game.radar_display.limit_label, game.radar_display.radar_label, game.radar_display.upcoming_label, game.radar_display.brake_label, game.radar_display.fine_label]:
			_check(game.radar_display.panel.get_global_rect().encloses(label.get_global_rect()), "radar caption %s fits phone panel at %s" % [label.text, screen])
	for button in game.touch_controls.buttons.values():
		var bounds: Rect2 = button.get_global_rect()
		_check(safe.grow(0.5).encloses(bounds), "%s stays within safe phone area at %s" % [button.name, screen])
		var scale: Vector2 = button.get_global_transform().get_scale() * root.get_final_transform().get_scale()
		_check(button.size.x * scale.x >= 70.0 and button.size.y * scale.y >= 48.0, "%s is a large phone touch target at %s" % [button.name, screen])
		_check(button.get_theme_font_size("font_size") * scale.y >= 14.0, "%s readable touch caption at %s" % [button.name, screen])
		for panel in critical:
			if panel.is_visible_in_tree():
				_check(not bounds.intersects(panel.get_global_rect()), "%s does not overlap %s at %s" % [button.name, panel.name, screen])
	for label in [game.ui.boost_hint, game.radar_display.radar_label, game.radar_display.upcoming_label, game.radar_display.brake_label, game.radar_display.fine_label, game.apex_ui.countdown_label, game.community.pursuit_caption]:
		if label.is_visible_in_tree():
			var pixels: float = label.get_theme_font_size("font_size") * label.get_global_transform().get_scale().y * root.get_final_transform().get_scale().y
			_check(pixels >= 13.0, "%s HUD caption remains readable at %s: %.1fpx" % [label.text, screen, pixels])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
