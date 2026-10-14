extends SceneTree

const UIScript = preload("res://scripts/game_ui.gd")
const SIZES := [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 2048), Vector2i(3440, 1440)]

class ShortcutProbe:
	extends Node
	var keys: Array[int] = []
	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			keys.append(event.keycode)

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var probe := ShortcutProbe.new()
	root.add_child(probe)
	var ui = UIScript.new()
	root.add_child(ui)
	await process_frame
	_check(ui.has_method("configure_secret"), "secret configuration API exists")
	_check(ResourceLoader.exists("res://scripts/community_ui.gd"), "community UI exists")
	if not ui.has_method("configure_secret") or not ResourceLoader.exists("res://scripts/community_ui.gd"):
		quit(1)
		return
	ui.configure_secret(false)
	_check(ui.mode_buttons.size() == 3 and not ui.mode_buttons[2].visible, "locked Secret card is hidden")
	ui.configure_mode(2)
	_check("Fair" in ui.mode_label.text, "locked Secret cannot be configured")
	ui.configure_secret(true)
	ui.mode_buttons[2].pressed.emit()
	_check(ui.mode_buttons[2].visible and "Secret" in ui.mode_label.text, "unlocked Secret selects distinct caption")
	ui.update_hud(123, 180, 1.0, 0.27, false, 2.0)
	_check(is_equal_approx(ui.boost_meter.value, 27.0) and ui.boost_value_label.text == "27%", "Secret displays finite earned fuel")
	_check(not "boost in" in ui.boost_hint.text, "Secret recovery permits boost")
	_check(ui.has_method("configure_resumed"), "assisted-run caption API exists")
	if not ui.has_method("configure_resumed"):
		quit(1)
		return
	ui.configure_resumed(true)
	_check("Resumed" in ui.mode_label.text and "Resumed" in ui.result_mode_label.text, "assisted Secret run is labeled in HUD and results")
	ui.configure_resumed(false)
	_check(not "Resumed" in ui.mode_label.text and not "Resumed" in ui.result_mode_label.text, "new ordinary run clears assistance caption")
	ui.update_hazard_warning(4.0)
	_check("police" in ui.hazard_warning.text and not "ends your run" in ui.hazard_warning.text, "Secret pothole warning describes pursuit consequences")
	ui.configure_secret(false)
	_check("Fair" in ui.mode_label.text and not ui.mode_buttons[2].visible, "revocation removes selected Secret")
	ui.configure_secret(true)
	ui.configure_mode(2)
	var community = load("res://scripts/community_ui.gd").new()
	root.add_child(community)
	community.attach(ui)
	var names: Array[String] = []
	var access_codes: Array[String] = []
	var resume_codes: Array[String] = []
	var requests: Array[Vector2i] = []
	community.name_submitted.connect(func(value: String) -> void: names.append(value))
	community.secret_code_submitted.connect(func(value: String) -> void: access_codes.append(value))
	community.resume_code_submitted.connect(func(value: String) -> void: resume_codes.append(value))
	community.leaderboard_requested.connect(func(mode: int, resumed: bool) -> void: requests.append(Vector2i(mode, int(resumed))))
	community.request_name("Last driver")
	await process_frame
	_check(community.name_dialog.visible and community.name_input.text == "Last driver", "name prompt prefills last driver")
	_check(root.gui_get_focus_owner() == community.name_input, "name prompt focuses input")
	community.name_input.text = "   "
	_key(KEY_ENTER)
	await process_frame
	_check(names.is_empty() and community.name_dialog.get_meta("error").visible, "blank name remains in prompt with error")
	community.name_input.text = "Ștefan 🚗 山田"
	_key(KEY_ENTER)
	await process_frame
	_check(names == ["Ștefan 🚗 山田"], "Unicode name submits without replacing visible characters")
	community.show_name_error("Name could not be saved")
	_check(community.name_dialog.visible and community.name_dialog.get_meta("error").text == "Name could not be saved", "name storage error stays visible")
	_key(KEY_R, 114)
	await process_frame
	_check("r" in community.name_input.text and probe.keys.is_empty(), "R types into name without leaking restart")
	_key(KEY_F8)
	await process_frame
	_check(community.name_dialog.visible and probe.keys.is_empty(), "F8 cannot replace an active modal")
	community.name_input.text = "山".repeat(24)
	community.name_input.caret_column = 24
	_key(KEY_R, 114)
	await process_frame
	_check(community.name_input.text == "山".repeat(24), "name entry bounds 24 visible Unicode characters")
	_key(KEY_ESCAPE)
	await process_frame
	_check(ui.menu.visible and not community.name_dialog.visible and probe.keys.is_empty(), "Escape cancels name back to title")
	community.request_access()
	await process_frame
	_check(root.gui_get_focus_owner() == community.access_input, "access input receives focus")
	community.access_input.text = "private access"
	_key(KEY_ENTER)
	await process_frame
	_check(access_codes == ["private access"] and probe.keys.is_empty(), "access code submits without Start shortcut")
	community.show_access_error("Wrong code")
	_check(community.access_dialog.get_meta("error").text == "Wrong code", "access error is readable")
	_key(KEY_R, 114)
	_key(KEY_F8)
	await process_frame
	_check(community.access_dialog.visible and "r" in community.access_input.text and probe.keys.is_empty(), "access text traps restart and hidden-entry keys")
	_key(KEY_ESCAPE)
	await process_frame
	_check(ui.menu.visible and not community.access_dialog.visible and probe.keys.is_empty(), "access Escape returns to title")
	ui.show_game_over(999999999, 999999999, 100000.0, 5.0, 99, true, "Police have arrived.", false, true)
	community.set_resume_available(false)
	_check(not community.resume_button.visible, "resume offer remains hidden before eligibility")
	community.set_resume_available(true)
	_check(community.resume_button.visible, "eligible caught run exposes resume offer")
	community.resume_button.pressed.emit()
	await process_frame
	_check(community.bribe_dialog.visible and root.gui_get_focus_owner() == community.bribe_input, "resume offer opens focused code input")
	community.bribe_input.text = "resume-code"
	_key(KEY_ENTER)
	await process_frame
	_check(resume_codes == ["resume-code"], "resume code submits")
	community.show_resume_error("Code has already been used")
	_check(community.bribe_dialog.get_meta("error").visible, "invalid resume code stays in modal")
	_key(KEY_R, 114)
	_key(KEY_F8)
	await process_frame
	_check(community.bribe_dialog.visible and probe.keys.is_empty(), "bribe text traps restart and hidden-entry keys")
	_key(KEY_ESCAPE)
	await process_frame
	_check(ui.game_over_menu.visible and not community.bribe_dialog.visible and probe.keys.is_empty(), "Escape returns from bribe to results without restart")
	community.set_resume_available(false)
	_check(not community.resume_button.visible, "used/ineligible offer hides again")
	ui.show_menu()
	ui.leaderboard_pressed.emit()
	_check(requests.back() == Vector2i(2, 0), "title leaderboard requests selected mode")
	var entries: Array[Dictionary] = []
	var empty_entries: Array[Dictionary] = []
	for index in range(10):
		entries.append({"name": "MMMMMMMMMMMMMMMMMMMMMMMM", "score": 999999999999 - index, "distance": 9999999.0, "mode": 2, "resumed": false, "escapes": 99})
	community.show_leaderboard(entries, 2)
	await process_frame
	_check("On this computer" in community.leaderboard_dialog.get_meta("detail").text, "ranking scope explicitly local")
	_check(community.leaderboard_rows.get_child_count() == 10, "leaderboard shows ten best entries")
	community.leaderboard_tabs[0].pressed.emit()
	_check(requests.back() == Vector2i(0, 0), "Fair tab requests ordinary Fair rankings")
	community.show_leaderboard(empty_entries, 0)
	_check(community.leaderboard_empty.visible and not community.resumed_filter.visible, "empty Fair rankings have guidance and no assisted filter")
	community.leaderboard_tabs[1].pressed.emit()
	_check(requests.back() == Vector2i(1, 0), "Infinite tab requests its ranking")
	community.show_leaderboard(entries, 2, true)
	_check(community.resumed_filter.visible and community.resumed_filter.button_pressed, "assisted Secret partition selected")
	community.resumed_filter.button_pressed = false
	_check(requests.back() == Vector2i(2, 0), "resumed filter requests separate Secret partition")
	community.leaderboard_tabs[0].grab_focus()
	_key(KEY_RIGHT)
	await process_frame
	_check(root.gui_get_focus_owner() == community.leaderboard_tabs[1], "keyboard Right visits next ranking tab")
	_key(KEY_ENTER)
	await process_frame
	_check(requests.back() == Vector2i(1, 0) and probe.keys.is_empty(), "focused ranking tab uses Enter without Start shortcut")
	community.dismiss()
	ui.show_playing()
	community.update_pursuit(true, 37.0, 8.0)
	_check(community.rearview_panel.visible and "37" in community.pursuit_caption.text, "active pursuit displays measurable gap")
	community.update_pursuit(true, 137.0, 4.9)
	_check("4/5s" in community.pursuit_caption.text, "disengagement progress does not claim escape before five seconds")
	community.update_pursuit(false, 0.0, 0.0)
	_check(not community.rearview_panel.visible, "inactive pursuit hides mirror")
	for window_size in SIZES:
		root.size = window_size
		await _settle()
		var visible_area := root.get_visible_rect()
		ui.show_menu()
		await _settle()
		_check_panel(ui.menu, visible_area, window_size)
		_check(ui.mode_buttons[2].get_global_rect().encloses(ui._mode_captions[2].get_global_rect()), "Secret caption fits card at %s" % window_size)
		community.request_name("Ștefan 🚗 山田")
		await _settle()
		_check_panel(community.name_dialog, visible_area, window_size)
		community.dismiss()
		community.request_access()
		await _settle()
		_check_panel(community.access_dialog, visible_area, window_size)
		community.dismiss()
		ui.show_game_over(999999999, 999999999, 100000.0, 5.0, 99, true, "Police have arrived.", false, true)
		community.set_resume_available(true)
		await _settle()
		_check_panel(ui.game_over_menu, visible_area, window_size)
		community.resume_button.pressed.emit()
		await _settle()
		_check_panel(community.bribe_dialog, visible_area, window_size)
		community.dismiss()
		ui.show_menu()
		community.show_leaderboard(entries, 2)
		await _settle()
		_check_panel(community.leaderboard_dialog, visible_area, window_size)
		for row in community.leaderboard_rows.get_children():
			var name_label: Label = row.get_meta("name_label")
			var score: Label = row.get_meta("score_label")
			_check(not name_label.get_global_rect().intersects(score.get_global_rect()), "long name does not overlap score at %s" % window_size)
			_check(score.size.x >= score.get_minimum_size().x, "large score remains complete at %s" % window_size)
			var scroll: ScrollContainer = community.leaderboard_rows.get_parent().get_parent()
			_check(scroll.get_global_rect().encloses(row.get_global_rect()), "all ten long-name rows fit ranking body at %s" % window_size)
		community.dismiss()
		ui.show_playing()
		ui.update_hazard_warning(4.0)
		ui.show_feedback("PURSUIT STARTED")
		community.update_pursuit(true, 37.0, 8.0)
		await _settle()
		var mirror: Rect2 = community.rearview_panel.get_global_rect()
		_check(visible_area.encloses(mirror) and not mirror.intersects(ui.feedback.get_global_rect()) and not mirror.intersects(ui.hazard_warning.get_global_rect()), "mirror fits above feedback/warning at %s" % window_size)
		_check(not mirror.intersects(ui.score_label.get_global_rect()) and not mirror.intersects(ui.mode_label.get_global_rect()) and not mirror.intersects(ui.speed_label.get_global_rect()), "mirror avoids score and speed at %s" % window_size)
		var caption_scale: float = community.pursuit_caption.get_global_transform().get_scale().x * root.get_final_transform().get_scale().x
		_check(community.pursuit_caption.get_theme_font_size("font_size") * caption_scale >= 13.0, "pursuit gap/progress readable at %s" % window_size)
		community.update_pursuit(false, 0.0, 0.0)
	community.dismiss()
	ui.show_menu()
	community.show_leaderboard(empty_entries, 0)
	var back := _find_button(community.leaderboard_dialog, "Back")
	back.grab_focus()
	_key(KEY_ENTER)
	await process_frame
	_check(ui.menu.visible and not community.leaderboard_dialog.visible and probe.keys.is_empty(), "keyboard Back returns leaderboard to title")
	community.show_leaderboard(empty_entries, 0)
	_key(KEY_ESCAPE)
	await process_frame
	_check(ui.menu.visible and not community.leaderboard_dialog.visible, "leaderboard Escape returns to title")
	community.queue_free()
	ui.queue_free()
	probe.queue_free()
	await process_frame
	if failures == 0:
		print("COMMUNITY UI PASS: names/access/resume modal input, finite Secret HUD, local ranking partitions, 10 long names, six responsive sizes")
	quit(1 if failures > 0 else 0)


func _settle() -> void:
	for index in range(3):
		await process_frame


func _check_panel(overlay: ColorRect, visible_area: Rect2, window_size: Vector2i) -> void:
	var panel: PanelContainer = overlay.get_meta("panel")
	_check(visible_area.grow(-12.0).encloses(panel.get_global_rect()), "%s panel fits %s: %s" % [overlay.name, window_size, panel.get_global_rect()])
	var first: Control = overlay.get_meta("first_button", null)
	if first:
		var screen_scale: float = root.get_final_transform().get_scale().x
		var factor: float = first.get_global_transform().get_scale().x * screen_scale
		_check(first.get_theme_font_size("font_size") * factor >= 15.0, "%s text readable at %s" % [overlay.name, window_size])


func _key(code: Key, character: int = 0) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.unicode = character
		event.pressed = pressed
		Input.parse_input_event(event)


func _find_button(node: Node, caption: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == caption:
			return child
		var result := _find_button(child, caption)
		if result:
			return result
	return null


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("COMMUNITY UI FAIL: " + label)
