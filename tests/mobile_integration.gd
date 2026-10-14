extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists("res://scripts/touch_drive_controls.gd"):
		_check(false, "mobile touch controls exist")
		quit(1)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	game.mobile_mode = true
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	_check(game.ui.mobile_mode and game.touch_controls != null, "phone layout and input are integrated")
	_check(game.settings.quality == game.settings.Quality.LOW and root.msaa_3d == Viewport.MSAA_DISABLED, "mobile starts with lightweight graphics")
	_check(not game.ui.resolution_choice.get_parent().visible and not game.ui.fullscreen_toggle.visible, "desktop window settings are hidden on phones")
	game.request_start_game()
	_check(game.community.is_modal_open(), "touch-accessible start opens driver name")
	game.community.name_input.text = "Mobile test driver"
	game.community.name_input.text_submitted.emit(game.community.name_input.text)
	_check(game.state == game.GameState.PLAYING, "virtual keyboard submission starts the run")
	_clear(game)
	await process_frame
	_touch(game, "left", 0, true)
	_touch(game, "boost", 1, true)
	game.player._physics_process(1.0 / 60.0)
	game._physics_process(1.0 / 60.0)
	_check(game.player.position.x < 0.0 and game.progress.boosting, "two fingers steer and boost simultaneously")
	_touch(game, "brake", 2, true)
	var speed_before: float = game.speed
	var fuel_before: float = game.progress.boost_charge
	for tick in range(60):
		game._physics_process(1.0 / 60.0)
	_check(game.braking and not game.progress.boosting and game.speed <= speed_before - 6.9, "touch brake preserves gradual braking and overrides held boost")
	_check(is_equal_approx(game.progress.boost_charge, fuel_before), "touch brake consumes no boost fuel")
	_touch(game, "boost", 1, false)
	_check(game.touch_controls.get_steering_axis() < 0.0 and game.touch_controls.get_brake_requested(), "releasing one finger preserves other held controls")
	_touch(game, "pause", 3, true)
	_check(game.state == game.GameState.PAUSED and paused, "touch Pause freezes the game")
	_check(game.touch_controls.get_steering_axis() == 0.0 and not game.touch_controls.get_brake_requested(), "pause clears held touch input")
	game.resume_game()
	_check(not game._boost_requested() and not game._brake_requested(), "resume never restores stale fingers")
	_touch(game, "right", 4, true)
	game._notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
	_check(game.state == game.GameState.PAUSED and game.touch_controls.get_steering_axis() == 0.0, "backgrounding pauses and clears controls")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED)
	_check(game.state == game.GameState.PAUSED, "returning to the app awaits deliberate resume")
	game.resume_game()
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(game.state == game.GameState.PAUSED, "Android Back pauses a running game")
	game.ui._open_settings(game.ui.pause_menu)
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not game.ui.is_settings_open() and game.state == game.GameState.PAUSED, "Android Back closes settings before changing run state")
	game.return_to_menu()
	game.community.request_access()
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	_check(not game.community.is_modal_open() and game.state == game.GameState.MENU, "Android Back dismisses a code dialog")
	game.start_game()
	_clear(game)
	game.speed = 300.0 / 3.6
	game.enforcement.next_limit = 30
	game.enforcement.sector_at = -1.0
	game.enforcement.radar_at = game.enforcement.WARNING_DISTANCE
	game.enforcement.sector_end = 800.0
	game.enforcement.radar_pending = true
	_touch(game, "brake", 5, true)
	for tick in range(1200):
		game._physics_process(1.0 / 60.0)
		if not game.enforcement.radar_pending:
			break
	_check(game.enforcement.fine_points > 0 and game.pursuit.active, "mobile immediate braking at 300km/h still gets fined at the fixed320m warning")
	game.return_to_menu()
	_check(not game.touch_controls.visible and not game.touch_controls.get_brake_requested(), "menu hides and resets touch input")
	game.audio.stop_all()
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame
	print("MOBILE INTEGRATION PASS" if failures == 0 else "MOBILE INTEGRATION FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _touch(game, action: String, index: int, pressed: bool) -> void:
	var button: Control = game.touch_controls.buttons[action]
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = button.get_global_transform_with_canvas() * (button.size * 0.5)
	event.pressed = pressed
	root.push_input(event, true)


func _clear(game) -> void:
	game.obstacles.spawning_enabled = false
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()
	game.enforcement.sector_at = INF
	game.enforcement.radar_at = INF
	game.enforcement.sector_end = INF


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
