extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	_check(ResourceLoader.exists("res://scripts/localization.gd"), "keyed localization service exists")
	if failures > 0:
		quit(1)
		return
	var l = load("res://scripts/localization.gd")
	var en: Dictionary = l.dictionary("en")
	var ro: Dictionary = l.dictionary("ro")
	_check(en.size() > 100 and en.size() == ro.size(), "complete dictionary key parity")
	for key in en:
		_check(ro.has(key) and not String(ro.get(key, "")).is_empty(), "Romanian translation: " + str(key))
		var placeholders := RegEx.new()
		placeholders.compile("%(?:[0-9]+)?(?:\\.[0-9]+)?[dfs]")
		var en_formats: Array[String] = []
		var ro_formats: Array[String] = []
		for found in placeholders.search_all(en[key]):
			en_formats.append(found.get_string())
		for found in placeholders.search_all(ro[key]):
			ro_formats.append(found.get_string())
		_check(en_formats == ro_formats, "format placeholders match: " + str(key))
	l.set_language("en")
	var settings = load("res://scripts/game_settings.gd").new()
	_check(settings.language == 0, "old preferences default English")
	settings.set_value("language", 1.0)
	_check(settings.save_settings("user://localization-settings.cfg") == OK, "language saves")
	var loaded = load("res://scripts/game_settings.gd").new()
	loaded.load_settings("user://localization-settings.cfg")
	_check(loaded.language == 1, "language persists")
	var legacy := ConfigFile.new()
	legacy.set_value("settings", "volume", 0.23)
	legacy.save("user://localization-settings.cfg")
	loaded.load_settings("user://localization-settings.cfg")
	_check(loaded.language == 0 and is_equal_approx(loaded.volume, 0.23), "old save migration preserves existing settings")
	var ui = load("res://scripts/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	var community = load("res://scripts/community_ui.gd").new()
	root.add_child(community)
	community.attach(ui)
	var radar = load("res://scripts/radar_display.gd").new()
	root.add_child(radar)
	radar.attach(ui)
	radar.warning_distance = 1300.0
	radar.update_display(100.0, 80, 120, 1200.0, 1100.0, true, 350.0, true, 500)
	_check("−500" in radar.fine_label.text, "fine HUD shows deducted points")
	var apex = load("res://scripts/apex_race_ui.gd").new()
	root.add_child(apex)
	apex.attach(ui)
	apex.show_challenge(-5.0, 7.0)
	apex.notification_remaining = 2.0
	apex.update_race(true, 22.0, -12.0, 2.3, false, 1.4, 7.0)
	ui.show_playing()
	community.update_pursuit(true, 15.0, 0.0)
	_check("Escape 0/5s" in community.pursuit_caption.text, "pursuit labels actual disengagement progress")
	community.update_capture(3, 0.6)
	_check(community.capture_meter.visible and is_equal_approx(community.capture_meter.value, 60.0), "capture pressure shown as percent")
	community.request_name("Ștefan")
	ui.configure_language(1)
	_check(community.name_input.text == "Ștefan" and community.name_dialog.visible, "live language preserves modal and typed name")
	_check(community.name_input.placeholder_text == "Numele șoferului", "live Romanian text field")
	_check("calculator" in community.name_dialog.get_meta("detail").text, "complete composed dialog localization")
	_check("FRÂNEZI" == radar.brake_label.text and "1000" in radar.radar_label.text, "live radar braking and dynamic look-ahead")
	_check("CURSĂ APEX" in apex.countdown_label.text and "GROAPĂ" in apex.requirements_label.text, "live Apex state text")
	_check(is_equal_approx(apex.notification_remaining, 2.0) and "PROVOACĂ" in apex.notification_title.text, "live challenge preserves notification time")
	_check(ui.language_choice.selected == 1 and ui.menu_language_choice.selected == 1, "both selectors synchronize")
	_check(ui.boost_label.text == "Boost", "Romanian boost caption is familiar")
	ui.configure_language(0)
	_check(community.name_input.placeholder_text == "Driver name", "live English restores text")
	community.dismiss()
	var names: Array[Dictionary] = [{"name": "Fair", "score": 42, "distance": 1200.0, "escapes": 2}]
	community.show_leaderboard(names, 0)
	ui.configure_language(1)
	_check(community.leaderboard_rows.get_child(0).get_meta("name_label").text == "Fair", "player names never translate")
	_check("evadări" in community.leaderboard_rows.get_child(0).tooltip_text, "leaderboard details switch live")
	community.dismiss()
	ui.show_game_over(456, 789, 1230.0, 1.7, 3, false, l.text("game.busted"), false, true, l.text("game.records_unsaved"))
	ui.configure_language(0)
	_check("Police caught" in ui.game_over_menu.get_meta("detail").text and "Records could not" in ui.game_over_menu.get_meta("detail").text, "result reason and save notice switch live")
	_check("SCORE 000456" == ui.final_score_label.text, "live result preserves score")
	community.update_capture(4, 0.86)
	_check("CRITICAL" in community.capture_label.text and "86%" in community.capture_label.text, "critical capture is explicitly labeled")
	var language_events: Array[int] = []
	ui.settings_changed.connect(func(key: String, value: float) -> void:
		if key == "language":
			language_events.append(roundi(value)))
	ui.menu_language_choice.item_selected.emit(1)
	_check(language_events == [1] and l.language_index() == 1, "main-menu selector emits persistent language choice")
	ui.language_choice.item_selected.emit(0)
	_check(language_events == [1, 0] and l.language_index() == 0, "settings selector emits persistent language choice")
	DirAccess.remove_absolute("user://localization-settings.cfg")
	community.queue_free()
	radar.queue_free()
	apex.queue_free()
	ui.queue_free()
	await process_frame
	if failures == 0:
		print("STAGE TWO LOCALIZATION PASS: complete dictionaries, persistence, live modal switching, selectors, capture")
	quit(1 if failures > 0 else 0)
func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
