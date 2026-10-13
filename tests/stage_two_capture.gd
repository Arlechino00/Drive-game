extends SceneTree

const L = preload("res://scripts/localization.gd")
var failures: int = 0
var captures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")
	for mobile in [false, true]:
		var game = load("res://scenes/main.tscn").instantiate()
		game.mobile_mode = mobile
		root.add_child(game)
		await process_frame
		game.set_process(false)
		game.set_physics_process(false)
		game.player.set_physics_process(false)
		game.audio.stop_all()
		game.ui.configure_secret(true)
		for language in [0, 1]:
			game.ui.configure_language(language)
			var suffix := ("en" if language == 0 else "ro") + ("-mobile" if mobile else "")
			game.ui.show_menu()
			await _save(game, "menu-" + suffix)
			game.ui._open_settings(game.ui.menu)
			await _save(game, "settings-" + suffix)
			game.ui._close_settings()
			game.community.request_name("Ștefan")
			await _save(game, "driver-" + suffix)
			game.community.dismiss()
			game.ui.show_playing()
			game.ui.configure_mode(2)
			game.ui.update_hud(184520, 328, 3.2, 0.43)
			game.community.update_pursuit(true, 12.0, 0.0, 5.0, false)
			game.community.update_capture(4, 0.86)
			game.pursuit._rear_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			game.radar_display.warning_distance = 1300.0
			game.radar_display.update_display(100.0, 120, 80, 250.0, 460.0, true, 328.0, false, 1500)
			game.touch_controls.set_enabled(mobile)
			game.touch_controls.set_driving(true)
			await _save(game, "capture-" + suffix)
			game.touch_controls.set_driving(false)
			game.community.update_pursuit(false, 0.0, 0.0)
			game.ui.show_game_over(184520, 230000, 25000.0, 3.2, 65, false, L.text("game.busted"))
			await _save(game, "results-" + suffix)
		game.queue_free()
		await process_frame
	if failures == 0:
		print("STAGE TWO CAPTURE PASS: %d English/Romanian desktop/mobile menu, settings, name, capture HUD and result views at1280x720" % captures)
	quit(1 if failures > 0 else 0)

func _save(game, screen: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var visible := root.get_visible_rect()
	for overlay in [game.ui.menu, game.ui.pause_menu, game.ui.game_over_menu, game.ui.settings_menu, game.community.name_dialog]:
		if overlay.visible:
			var panel: Control = overlay.get_meta("panel")
			_check(visible.encloses(panel.get_global_rect()), screen + " panel fits viewport")
			for node in game.ui._column(overlay).get_children():
				_check(panel.get_global_rect().encloses(node.get_global_rect()), screen + " content fits panel")
	if game.community.rearview_panel.visible:
		_check(not game.community.rearview_panel.get_global_rect().intersects(game.ui.feedback.get_global_rect()), screen + " capture clears feedback")
	var image := root.get_texture().get_image()
	_check(image.save_png("res://docs/screenshots/stage-two-" + screen + ".png") == OK, screen + " image saves")
	captures += 1

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("STAGE TWO CAPTURE: " + message)
