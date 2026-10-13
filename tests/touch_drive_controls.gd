extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui = load("res://scripts/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	var path := "res://scripts/touch_drive_controls.gd"
	if not ResourceLoader.exists(path):
		_check(false, "touch controller exists")
		ui.free()
		quit(1)
		return
	var controls = load(path).new()
	controls.attach(ui)
	controls.set_enabled(true)
	controls.set_driving(true)
	ui.show_playing()
	await process_frame
	_check(controls.buttons.size() == 5 and controls.buttons["left"] == controls.left_button, "public touch-area dictionary")
	var releases := [0]
	var pauses := [0]
	controls.boost_released.connect(func() -> void: releases[0] += 1)
	controls.pause_pressed.connect(func() -> void: pauses[0] += 1)
	_touch(1, _center(controls.left_button), true)
	_touch(2, _center(controls.boost_button), true)
	_check(controls.get_steering_axis() == -1.0 and controls.get_boost_requested(), "independent left and boost touches")
	_touch(3, _center(controls.brake_button), true)
	_check(controls.get_brake_requested() and controls.get_boost_requested(), "brake and boost hold independently")
	_touch(1, Vector2.ZERO, false)
	_check(controls.get_steering_axis() == 0.0 and controls.get_boost_requested() and controls.get_brake_requested(), "release anywhere affects only that finger")
	_touch(4, _center(controls.right_button), true)
	_check(controls.get_steering_axis() == 1.0, "right steering")
	_drag(2, Vector2.ZERO)
	_check(not controls.get_boost_requested() and controls.get_brake_requested() and releases[0] == 1, "dragging out releases boost only")
	_drag(2, _center(controls.boost_button))
	_check(not controls.get_boost_requested(), "dragging back does not latch a released touch")
	_touch(3, _center(controls.brake_button), false, true)
	_check(not controls.get_brake_requested() and controls.get_steering_axis() == 1.0, "cancelled touch releases its own control")
	_touch(5, _center(controls.left_button), true)
	_check(controls.get_steering_axis() == 0.0, "opposing steering touches cancel")
	controls.clear_inputs()
	_touch(6, _center(controls.boost_button), true)
	_touch(7, _center(controls.boost_button), true)
	_touch(6, Vector2.ZERO, false)
	_check(controls.get_boost_requested() and releases[0] == 1, "second boost finger keeps boost held")
	_touch(7, Vector2.ZERO, false)
	_check(not controls.get_boost_requested() and releases[0] == 2, "last boost finger emits one release")
	_touch(8, _center(controls.pause_button), true)
	_check(pauses[0] == 1, "touch pause signal")
	_touch(8, _center(controls.pause_button), false)
	_touch(9, _center(controls.left_button), true)
	controls.set_driving(false)
	_check(not controls.visible and controls.get_steering_axis() == 0.0, "pause hides controls and clears held input")
	_touch(10, _center(controls.boost_button), true)
	_check(not controls.get_boost_requested(), "inactive controls ignore touches")
	controls.set_driving(true)
	_touch(11, _center(controls.brake_button), true)
	controls.set_enabled(false)
	_check(not controls.visible and not controls.get_brake_requested(), "disable clears brake")
	controls.set_enabled(true)
	_touch(12, _center(controls.boost_button), true)
	ui.show_menu()
	await process_frame
	_check(not controls.get_boost_requested(), "ancestor visibility clears held input")
	_touch(14, _center(controls.boost_button), true)
	_check(not controls.get_boost_requested(), "hidden HUD ignores new touch input")
	ui.show_playing()
	_touch(13, _center(controls.brake_button), true)
	controls.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not controls.get_brake_requested(), "focus loss clears input")
	var count: int = controls.get_child_count()
	for screen_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2400, 1080)]:
		root.size = screen_size
		await process_frame
		await process_frame
		for button in [controls.left_button, controls.right_button, controls.brake_button, controls.boost_button, controls.pause_button]:
			var bounds: Rect2 = button.get_global_rect()
			_check(root.get_visible_rect().encloses(bounds), "touch area fits %s" % screen_size)
			var pixels: Vector2 = button.size * button.get_global_transform().get_scale() * root.get_final_transform().get_scale()
			_check(pixels.x >= 72.0 and pixels.y >= 48.0, "large scaled touch target at %s: %s" % [screen_size, pixels])
			_touch(20, _center(button), true)
			if button == controls.left_button:
				_check(controls.get_steering_axis() == -1.0, "scaled event coordinates hit left button")
			_touch(20, Vector2.ZERO, false)
		_check(not controls.left_button.get_global_rect().intersects(ui.boost_meter.get_global_rect()), "left control avoids boost meter")
		_check(not controls.boost_button.get_global_rect().intersects(ui.boost_meter.get_global_rect()), "boost control avoids boost meter")
	for tick in range(100):
		controls.set_driving(false)
		controls.set_driving(true)
	_check(controls.get_child_count() == count, "controls reuse bounded nodes across runs")
	ui.free()
	await process_frame
	if failures == 0:
		print("TOUCH DRIVE CONTROLS PASS: multitouch, releases, pause/focus, scaling, bounded nodes")
	quit(0 if failures == 0 else 1)


func _center(control: Control) -> Vector2:
	# Input.parse_input_event accepts window coordinates; Godot transforms these
	# into viewport coordinates before dispatching _input.
	return root.get_final_transform() * control.get_global_transform_with_canvas() * (control.size * 0.5)


func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	event.canceled = canceled
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
