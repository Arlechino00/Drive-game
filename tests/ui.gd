extends SceneTree

const UIScript = preload("res://scripts/game_ui.gd")

var failures: int = 0
var setting_events: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui = UIScript.new()
	root.add_child(ui)
	await process_frame
	_check(ui.menu.visible and not ui.hud.visible, "initial menu")
	_check(ui.hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD ignores mouse")
	var mode_events: Array[int] = []
	ui.mode_selected.connect(func(mode: int) -> void: mode_events.append(mode))
	ui.configure_mode(1)
	_check(mode_events.is_empty(), "mode configuration emits no selection")
	_check(ui.mode_buttons[1].button_pressed and not ui.mode_buttons[0].button_pressed, "exclusive configured mode")
	ui.show_playing()
	ui.update_hud(0, 180, 1.0, 0.0, false)
	_check("Infinite Boost" in ui.mode_label.text and "Unlimited" in ui.boost_label.text, "unlimited mode identified while idle")
	_check(is_equal_approx(ui.boost_meter.value, 100.0), "unlimited meter stays full with empty supplied charge")
	ui.update_hud(0, 180, 1.0, 0.0, true)
	_check("Unlimited" in ui.boost_label.text and "Boosting" in ui.boost_label.text, "unlimited mode identified while boosting")
	ui.show_game_over(0, 0)
	_check("Infinite Boost" in ui.result_mode_label.text, "result identifies mode")
	ui.show_menu()
	ui.mode_buttons[0].pressed.emit()
	_check(mode_events == [0], "Fair selection signal")
	_check("Fair" in ui.mode_label.text and not "Unlimited" in ui.boost_label.text, "Fair HUD restored")
	ui.mode_buttons[1].pressed.emit()
	_check(mode_events == [0, 1], "Infinite Boost selection signal")
	ui.configure_mode(0)
	_check(mode_events == [0, 1], "mode restore remains silent")
	var action_events: Array[String] = []
	ui.start_pressed.connect(func() -> void: action_events.append("start"))
	ui.resume_pressed.connect(func() -> void: action_events.append("resume"))
	ui.restart_pressed.connect(func() -> void: action_events.append("restart"))
	ui.quit_pressed.connect(func() -> void: action_events.append("quit"))
	_find_button(ui.menu, "Start driving").pressed.emit()
	_find_button(ui.pause_menu, "Resume").pressed.emit()
	_find_button(ui.pause_menu, "Restart").pressed.emit()
	_find_button(ui.game_over_menu, "Quit").pressed.emit()
	_check(action_events == ["start", "resume", "restart", "quit"], "existing action signals preserved")
	ui.settings_changed.connect(func(key: String, _value: float) -> void: setting_events.append(key))
	ui.configure_settings(0.4, 0.25, 0.0, false)
	_check(setting_events.is_empty(), "settings configuration emits no changes")
	ui.show_playing()
	ui.update_hud(1234, 217, 2.5, 0.7, true)
	_check("001234" in ui.score_label.text, "score")
	_check("217" in ui.speed_label.text, "speed")
	_check("2.5" in ui.combo_label.text, "combo")
	_check(is_equal_approx(ui.boost_meter.value, 70.0), "boost")
	var child_count := _node_count(ui)
	ui.set_effects(1.0)
	for index in range(40):
		ui.show_feedback("NEAR MISS +100")
	_check(_node_count(ui) == child_count, "feedback is reused")
	_check(ui.feedback.process_mode == Node.PROCESS_MODE_PAUSABLE, "feedback pausable")
	# Pause during the fade, where an accidentally unpaused tween would change alpha.
	await create_timer(0.88).timeout
	paused = true
	var opacity: float = ui.feedback.modulate.a
	_check(opacity > 0.0 and opacity < 1.0, "feedback fade is active")
	await create_timer(0.2).timeout
	_check(is_equal_approx(ui.feedback.modulate.a, opacity), "pause freezes feedback tween")
	ui.show_paused()
	ui._open_settings(ui.pause_menu)
	_check(ui.settings_menu.visible and not ui.pause_menu.visible, "settings over pause")
	_check(paused, "UI leaves tree pause to game")
	ui.settings_sliders["volume"].value = 0.8
	_check(setting_events == ["volume"], "one normalized setting change")
	ui.fullscreen_toggle.button_pressed = true
	_check(setting_events == ["volume", "fullscreen"], "fullscreen setting change")
	ui._close_settings()
	_check(ui.pause_menu.visible and not ui.settings_menu.visible, "settings back to pause")
	ui._open_settings(ui.pause_menu)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	_check(ui.pause_menu.visible and not ui.settings_menu.visible and paused, "Escape returns to pause without unpausing")
	paused = false
	ui.show_menu()
	ui._open_settings(ui.menu)
	ui._close_settings()
	_check(ui.menu.visible and not ui.hud.visible, "settings back to title")
	ui.show_playing()
	_check(not ui.feedback.visible, "restart clears feedback")
	ui.show_game_over(2468, 2500, 1200.0, 3.5, 8, true)
	_check("002468" in ui.final_score_label.text and "002500" in ui.best_score_label.text, "final scores")
	_check("1.20 km" in ui.run_stats_label.text and "3.5" in ui.run_stats_label.text and "8" in ui.run_stats_label.text, "run statistics")
	var menu_events := [0]
	ui.menu_pressed.connect(func() -> void: menu_events[0] += 1)
	_find_button(ui.game_over_menu, "Main menu").pressed.emit()
	_check(menu_events[0] == 1, "main menu signal")
	ui.set_debug("seed 123", true)
	_check(ui.debug_label.visible and ui.debug_label.text == "seed 123", "debug")
	ui.queue_free()
	await process_frame
	if failures == 0:
		print("UI PASS: mode selection/identification, HUD, menus, normalized settings, pause-safe feedback")
	quit(1 if failures > 0 else 0)


func _find_button(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == caption:
			return child
		var result := _find_button(child, caption)
		if result:
			return result
	return null


func _node_count(node: Node) -> int:
	var count: int = 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("UI FAIL: " + label)
