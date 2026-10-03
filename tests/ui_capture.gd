extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.run_seed = 2468
	await process_frame
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = window_size
		game.return_to_menu()
		game.ui.configure_mode(0)
		await _save_frame("menu", window_size)
		game.ui.mode_buttons[1].pressed.emit()
		await _save_frame("menu_infinite", window_size)
		game.start_game()
		await _save_frame("hud", window_size)
		game.pause_game()
		await _save_frame("pause", window_size)
		game.ui._open_settings(game.ui.pause_menu)
		await _save_frame("settings", window_size)
		game.ui._close_settings()
		game.resume_game()
		game._on_player_hit()
		game.ui.show_game_over(12345678, 12345678, 12345.0, 5.0, 128, true)
		await _save_frame("results", window_size)
	game.return_to_menu()
	game.audio.stop_all()
	await create_timer(0.12).timeout
	game.free()
	await process_frame
	if failures == 0:
		print("UI CAPTURE PASS: six native screens at 960x540, 1280x720 and 1920x1080")
	quit(1 if failures > 0 else 0)


func _save_frame(screen: String, window_size: Vector2i) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	var result := capture.save_png("res://tests/ui_%s_%d.png" % [screen, window_size.x])
	# Godot captures the rendered content, excluding bars from the saved 5:4 aspect.
	var content_size := root.get_visible_rect().size
	var content_scale := minf(window_size.x / content_size.x, window_size.y / content_size.y)
	var expected_size := Vector2i((content_size * content_scale).round())
	if result != OK or capture.get_size() != expected_size:
		failures += 1
		push_error("UI CAPTURE FAIL: %s %s, image %s, result %s" % [screen, window_size, capture.get_size(), result])
