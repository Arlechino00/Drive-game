extends SceneTree

const UIScript = preload("res://scripts/game_ui.gd")
const SIZES := [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 2048), Vector2i(3440, 1440)]

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui = UIScript.new()
	root.add_child(ui)
	_check(ui.brand_logo.texture != null, "original logo loaded")
	_check(ui.brand_logo.texture.get_size() == Vector2(1645, 1619), "original logo dimensions")
	_check(ui.brand_logo.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "logo preserves complete aspect ratio")
	_check(ui.brand_logo.modulate == Color.WHITE and ui.brand_logo.self_modulate == Color.WHITE, "logo preserves original colors")
	_check(ui.brand_logo.mouse_filter == Control.MOUSE_FILTER_IGNORE, "logo does not consume menu input")
	var started := [0]
	var selected: Array[int] = []
	ui.start_pressed.connect(func() -> void: started[0] += 1)
	ui.mode_selected.connect(func(mode: int) -> void: selected.append(mode))
	ui.configure_mode(1)
	ui.show_game_over(99999999, 99999999, 1234567.0, 5.0, 1000, true)
	ui.update_hud(99999999, 288, 5.0, 1.0, true)
	for window_size in SIZES:
		root.size = window_size
		await process_frame
		await process_frame
		await process_frame
		var visible_area := root.get_visible_rect()
		var canvas_to_screen := root.get_final_transform()
		var screen_scale := canvas_to_screen.get_scale().x
		print("UI SIZE %s: canvas %s, screen scale %.3f" % [window_size, visible_area.size, screen_scale])
		for overlay in [ui.menu, ui.pause_menu, ui.game_over_menu, ui.settings_menu]:
			ui._show_only(overlay)
			await process_frame
			await process_frame
			var panel: PanelContainer = overlay.get_meta("panel")
			var bounds := panel.get_global_rect()
			_check(visible_area.grow(-12.0 / screen_scale).encloses(bounds), "%s panel fits %s: %s" % [overlay.name, window_size, bounds])
			var first: Button = overlay.get_meta("first_button")
			var effective_scale := first.get_global_transform().get_scale().x * screen_scale
			_check(first.size.y * effective_scale >= 36.0, "%s usable button at %s" % [overlay.name, window_size])
			_check(first.get_theme_font_size("font_size") * effective_scale >= 15.0, "%s readable caption at %s" % [overlay.name, window_size])
			if window_size.x >= 1920:
				_check(first.get_theme_font_size("font_size") * effective_scale >= 28.0, "%s scales text for large screen %s" % [overlay.name, window_size])
		ui.show_playing()
		ui.update_hud(99999999, 288, 5.0, 1.0, false, 4.0)
		ui.update_hazard_warning(9.9)
		await process_frame
		for label in [ui.score_label, ui.speed_label, ui.mode_label, ui.boost_label, ui.boost_value_label, ui.boost_hint, ui.hazard_warning]:
			_check(visible_area.encloses(label.get_global_rect()), "HUD %s fits %s" % [label.text, window_size])
			var font_pixels: float = label.get_theme_font_size("font_size") * label.get_global_transform().get_scale().x * screen_scale
			_check(font_pixels >= 13.0, "HUD %s readable at %s: %.1f px" % [label.text, window_size, font_pixels])
		for invalid in [false, true]:
			var reason := "You entered a closed work lane.\nThis run does not count." if invalid else "Traffic collision.\nPolice are responding."
			ui.show_game_over(0 if invalid else 99999999, 99999999, 1234567.0, 5.0, 1000, false, reason, invalid, true)
			await process_frame
			await process_frame
			var police_panel: PanelContainer = ui.game_over_menu.get_meta("panel")
			_check(visible_area.grow(-12.0 / screen_scale).encloses(police_panel.get_global_rect()), "police result fits %s (invalid %s)" % [window_size, invalid])
			_check(police_panel.get_global_rect().position.x >= visible_area.size.x * 0.39, "police scene stays visible beside results")
		ui.show_game_over(99999999, 99999999, 1234567.0, 5.0, 1000, true)
		ui.show_menu()
		await process_frame
		var title_panel: PanelContainer = ui.menu.get_meta("panel")
		_check(title_panel.get_global_rect().encloses(ui.brand_logo.get_global_rect()), "branding fits title panel at %s" % window_size)
		_check(ui.brand_logo.size.x >= 130.0 and ui.brand_logo.size.x <= 150.0, "logo design slot size at %s" % window_size)
		_check(not ui.brand_logo.get_global_rect().intersects(ui.title_label.get_global_rect()), "logo/title do not overlap at %s" % window_size)
		if "--branding-capture" in OS.get_cmdline_user_args() and window_size in [Vector2i(960, 540), Vector2i(2560, 2048)]:
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			_check(capture.save_png("res://.godot/validation/branding_%d.png" % window_size.x) == OK, "branding capture saved")
		var before: int = started[0]
		_click(ui.menu.get_meta("first_button"))
		await process_frame
		_check(started[0] == before + 1, "scaled Start button accepts mouse at %s" % window_size)
		_click(ui.mode_buttons[0])
		await process_frame
		_check(ui.mode_buttons[0].button_pressed and selected.back() == 0, "scaled mode card accepts mouse at %s" % window_size)
		ui.mode_buttons[0].grab_focus()
		_key(KEY_RIGHT)
		await process_frame
		_check(root.gui_get_focus_owner() == ui.mode_buttons[1], "right arrow focuses next mode at %s" % window_size)
		_key(KEY_ENTER)
		await process_frame
		_check(ui.mode_buttons[1].button_pressed and selected.back() == 1, "Enter selects focused mode at %s" % window_size)
	ui._open_settings(ui.menu)
	await process_frame
	var volume_before: float = ui.settings_sliders["volume"].value
	ui.settings_sliders["volume"].grab_focus()
	_key(KEY_LEFT)
	await process_frame
	_check(ui.settings_sliders["volume"].value < volume_before, "slider changes with keyboard")
	ui.fullscreen_toggle.grab_focus()
	_key(KEY_SPACE)
	await process_frame
	_check(ui.fullscreen_toggle.button_pressed, "Space toggles fullscreen control")
	ui._close_settings()
	ui.show_playing()
	_check(root.gui_get_focus_owner() == null, "gameplay releases keyboard focus")
	ui.queue_free()
	await process_frame
	if failures == 0:
		print("RESPONSIVE UI PASS: six window sizes, visible bounds, readable text, mouse hits, keyboard mode/settings controls")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("RESPONSIVE UI FAIL: " + label)


func _click(button: Button) -> void:
	var position: Vector2 = button.get_global_transform_with_canvas() * (button.size * 0.5)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		root.push_input(event, true)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
