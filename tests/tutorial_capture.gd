extends SceneTree

const L = preload("res://scripts/localization.gd")
const WINDOWS := [Vector2i(854, 480), Vector2i(1280, 720)]
const OUTPUT := "res://.godot/validation/live-tutorial-captures"
var failures: int = 0
var views: int = 0
var images: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	for mobile in [false, true]:
		root.content_scale_size = WINDOWS[0]
		root.size = WINDOWS[0]
		var game = load("res://scenes/main.tscn").instantiate()
		game.mobile_mode = mobile
		root.add_child(game)
		await process_frame
		game.tutorial_enabled = true
		game.set_physics_process(false)
		game.set_process(false)
		game.player.set_physics_process(false)
		_configure_access(game)
		for window in WINDOWS:
			root.content_scale_size = window
			root.size = window
			game.ui._resize_interface()
			for language in [0, 1]:
				game.settings.language = language
				game._apply_settings()
				game.return_to_menu()
				await _settle()
				_check(root.get_visible_rect().encloses(game.ui.menu.get_meta("panel").get_global_rect()), "title with Tutorial fits" + _context(mobile, window, language, "title"))
				var tutorial_button := _find_button(game.ui.menu, L.text("tutorial.button"))
				_check(tutorial_button != null, "title exposes Tutorial action")
				if tutorial_button != null:
					tutorial_button.pressed.emit()
					_check(game.community.name_dialog.visible and not game.tutorial.active, "title Tutorial enters normal driver/start flow")
					game._on_name_submitted("Live capture driver")
					_check(game.tutorial.active and game.tutorial.practice and game.ui.hud.visible, "title Tutorial starts live coaching after driver entry")
					game.tutorial.skip_button.pressed.emit()
					_check(not game.tutorial.active and game.state == game.GameState.PLAYING and game.progress.score_valid, "Skip immediately begins normal scoring run")
				if mobile:
					await _exercise_mobile_controls(game)
				for secret in [false, true]:
					game.selected_mode = game.GameMode.SECRET if secret else game.GameMode.FAIR
					game.start_game()
					game.player.set_physics_process(false)
					_check(game.tutorial.active and game.tutorial.practice and game.tutorial.secret_guide == secret, "every new round begins its live intro")
					var steps: Array = game.tutorial.SECRET if secret else game.tutorial.STANDARD
					for index in range(steps.size()):
						game.tutorial.step = index
						game.tutorial._enter_step()
						# Freeze a representative demonstration; exercise the production
						# HUD update without inventing a separate teaching screen.
						if steps[index] == "capture":
							game.pursuit.capture_fraction = 0.55
						elif steps[index] == "escape":
							if not game.pursuit.active:
								game.pursuit.begin(game.player.position)
							for unit in game.pursuit.units:
								unit.z = 130.0
							game.pursuit.capture_fraction = 0.0
							game.pursuit.disengagement_seconds = 2.0
						game._physics_process(0.0)
						game.tutorial._update_marker()
						await _settle()
						var context := _context(mobile, window, language, steps[index])
						_check_live_bounds(game, context, mobile)
						views += 1
						if window.x == 1280 or steps[index] in ["steer", "capture", "escape"]:
							var filename := "%s/%s-%s-%s-%s-%d.png" % [OUTPUT, "secret" if secret else "standard", steps[index], "ro" if language else "en", "mobile" if mobile else "desktop", window.x]
							_check(root.get_texture().get_image().save_png(filename) == OK, "live coaching image saves")
							images += 1
					game.tutorial.skip_button.pressed.emit()
					_check(not game.tutorial.active and game.state == game.GameState.PLAYING, "Skip remains available at end of every intro")
		game.return_to_menu()
		game.audio.stop_all()
		game.queue_free()
		await process_frame
	if failures == 0:
		print("LIVE TUTORIAL CAPTURE PASS: %d EN/RO desktop/mobile coaching views, %d images at854x480/1280x720; each-round intro, title action, Skip, HUD/touch/pursuit bounds" % [views, images])
	else:
		print("LIVE TUTORIAL CAPTURE FAIL: %d issues across%d views; inspect%s" % [failures, views, OUTPUT])
	quit(1 if failures else 0)

func _configure_access(game) -> void:
	var config := ConfigFile.new()
	config.set_value("secret_mode", "access_code", "LIVE-CAPTURE-ACCESS")
	config.set_value("secret_mode", "resume_code", "LIVE-CAPTURE-RESUME")
	_check(config.save("user://live_capture_config.cfg") == OK, "isolated access configuration saves")
	DirAccess.remove_absolute("user://live_capture_access.cfg")
	game.access = load("res://scripts/secret_access.gd").new("user://live_capture_access.cfg", "user://live_capture_config.cfg")
	game.access.load_access()
	_check(game.access.unlock("LIVE-CAPTURE-ACCESS"), "fixture unlocks Secret through normal access service")
	game.ui.configure_secret(true)

func _exercise_mobile_controls(game) -> void:
	game.selected_mode = game.GameMode.FAIR
	game.start_game()
	game.player.set_physics_process(false)
	await _settle()
	var origin: float = game.player.position.x
	_touch(40, _center(game.touch_controls.left_button), true)
	_check(game.touch_controls.get_steering_axis() < 0.0, "live mobile coaching accepts steering touch")
	for tick in range(8):
		game.player._physics_process(1.0 / 60.0)
		game._physics_process(1.0 / 60.0)
	_check(game.player.position.x < origin, "steering touch moves the car during live coaching")
	_touch(40, Vector2.ZERO, false)
	_touch(41, _center(game.touch_controls.brake_button), true)
	game._physics_process(0.2)
	_check(game.braking and game.speed < 33.0, "brake touch slows the practice car")
	_touch(41, Vector2.ZERO, false)
	game.progress.boost_charge = 1.0
	_touch(42, _center(game.touch_controls.boost_button), true)
	game._physics_process(0.1)
	_check(game.progress.boosting, "boost touch works during live coaching")
	_touch(42, Vector2.ZERO, false)
	await _settle()
	var skip_at := _center(game.tutorial.skip_button)
	_touch(43, skip_at, true)
	_touch(43, skip_at, false)
	await process_frame
	_check(not game.tutorial.active and game.state == game.GameState.PLAYING, "touch tap on Skip ends coaching")
	game.touch_controls.clear_inputs()

func _center(control: Control) -> Vector2:
	return root.get_final_transform() * control.get_global_transform_with_canvas() * (control.size * 0.5)

func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _check_live_bounds(game, context: String, mobile: bool) -> void:
	var viewport := root.get_visible_rect()
	var panel: Rect2 = game.tutorial.panel.get_global_rect()
	_check(game.ui.hud.visible and game.tutorial.panel.is_visible_in_tree(), "coaching and normal HUD remain visible" + context)
	_check(not game.community.is_modal_open(), "live coaching does not open a book modal" + context)
	_check(viewport.grow(0.5).encloses(panel), "coaching panel fits viewport" + context)
	for node in [game.tutorial.caption, game.tutorial.hint, game.tutorial.skip_button]:
		_check(panel.grow(0.5).encloses(node.get_global_rect()), "coaching content fits panel" + context)
		_check(not "coach." in str(node.text), "coaching copy is localized" + context)
	if mobile:
		_check(game.touch_controls.is_visible_in_tree(), "touch driving controls remain visible" + context)
		_check(game.tutorial.skip_button.get_global_rect().size.y >= 44.0, "Skip remains a usable touch target" + context)
	var hud_parts: Array = [game.ui.score_label, game.ui.mode_label, game.ui.speed_label, game.ui.combo_label, game.ui.boost_meter.get_parent(), game.radar_display.panel, game.community.rearview_panel]
	for part in hud_parts:
		if part.is_visible_in_tree():
			_check(viewport.grow(0.5).encloses(part.get_global_rect()), "normal HUD remains inside viewport: " + part.name + context)
			_check(not panel.intersects(part.get_global_rect()), "coaching avoids normal HUD: " + part.name + context)
	for button in game.touch_controls.buttons.values():
		if button.is_visible_in_tree():
			_check(not panel.intersects(button.get_global_rect()), "coaching avoids touch control: " + button.name + context)
	if game.tutorial.current_step() in ["capture", "escape"]:
		_check(game.community.rearview_panel.is_visible_in_tree() and game.community.capture_meter.is_visible_in_tree(), "police meter stays visible during lesson" + context)
	if game.tutorial.target_marker.visible:
		_check(viewport.grow(0.5).encloses(game.tutorial.target_marker.get_global_rect()), "traffic marker fits viewport" + context)
		_check(not panel.intersects(game.tutorial.target_marker.get_global_rect()), "coaching leaves traffic demonstration marker readable" + context)

func _find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption:
		return node
	for child in node.get_children():
		var found := _find_button(child, caption)
		if found != null:
			return found
	return null

func _context(mobile: bool, window: Vector2i, language: int, step: String) -> String:
	return " [%s %s %s %s]" % ["mobile" if mobile else "desktop", window, "RO" if language else "EN", step]

func _settle() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("LIVE TUTORIAL CAPTURE: " + label)
