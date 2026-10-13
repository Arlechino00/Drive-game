extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var input_path := "res://scripts/drive_input.gd"
	if not ResourceLoader.exists(input_path):
		_check(false, "controller action setup exists")
		quit(1)
		return
	var controls = load(input_path)
	var before := InputMap.action_get_events("ui_accept").size()
	controls.ensure_actions()
	var count := InputMap.action_get_events("ui_accept").size()
	controls.ensure_actions()
	_check(count >= before and InputMap.action_get_events("ui_accept").size() == count, "setup preserves keyboard actions and is idempotent")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.set_process(false)
	game.tutorial_enabled = true
	game.return_to_menu()
	var focused := root.gui_get_focus_owner()
	_button(JOY_BUTTON_DPAD_DOWN)
	await process_frame
	_check(root.gui_get_focus_owner() != focused, "D-pad moves title focus")
	game.ui._open_settings(game.ui.menu)
	_button(JOY_BUTTON_B)
	_check(not game.ui.is_settings_open() and game.state == game.GameState.MENU, "B returns from settings without starting a run")
	game.community.request_access()
	_button(JOY_BUTTON_B)
	_check(not game.community.is_modal_open(), "B dismisses gated access dialog")
	game.community.request_name("Controller driver")
	_button(JOY_BUTTON_A)
	_check(not game.community.is_modal_open() and game.tutorial.active, "A submits the focused name field and starts live coaching")
	var boost_key := InputEventKey.new()
	boost_key.keycode = KEY_SPACE
	boost_key.pressed = true
	Input.parse_input_event(boost_key)
	Input.flush_buffered_events()
	_check(game.tutorial.active, "keyboard Space remains Boost and cannot accidentally Skip")
	var boost_release := InputEventKey.new()
	boost_release.keycode = KEY_SPACE
	boost_release.pressed = false
	Input.parse_input_event(boost_release)
	Input.flush_buffered_events()
	game.start_game()
	_button(JOY_BUTTON_A)
	_check(not game.tutorial.active and game.distance == 0 and game.progress.score_valid, "A skips intro into valid clean run")
	_button(JOY_BUTTON_START)
	_check(game.state == game.GameState.PAUSED, "Start pauses normal driving")
	_button(JOY_BUTTON_A)
	await process_frame
	_check(game.state == game.GameState.PLAYING, "A activates focused Resume")
	_button(JOY_BUTTON_START)
	_button(JOY_BUTTON_START)
	_check(game.state == game.GameState.PLAYING, "Start resumes paused driving")
	game.return_to_menu()
	game.audio.stop_all()
	await create_timer(0.2).timeout
	game.free()
	game = null
	await process_frame
	if failures == 0:
		print("CONTROLLER UI PASS: stable keyboard maps, D-pad menus, A accept/Skip, B back, Start pause/resume")
	quit(1 if failures else 0)

func _button(button: int) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("CONTROLLER UI FAIL: " + label)
