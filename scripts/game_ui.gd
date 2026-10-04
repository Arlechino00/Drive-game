class_name GameUI
extends CanvasLayer

signal start_pressed
signal resume_pressed
signal restart_pressed
signal quit_pressed
signal menu_pressed
signal settings_changed(key: String, value: float)
signal mode_selected(mode: int)
signal leaderboard_pressed

const CYAN := Color("#70eaf3")
const MAGENTA := Color("#fa78c1")
const WHITE := Color("#f0eef7")
const MUTED := Color("#b6b1d2")
const ORANGE := Color("#ffc28a")
const INK := Color("#101126")
const UI_REFERENCE := Vector2(1100.0, 800.0)

var interface: Control
var brand_logo: TextureRect
var title_label: Label
var hud: Control
var score_label: Label
var speed_label: Label
var combo_label: Label
var boost_meter: ProgressBar
var boost_label: Label
var boost_value_label: Label
var boost_hint: Label
var mode_label: Label
var result_mode_label: Label
var mode_buttons: Array[Button] = []
var mode_detail: Label
var menu: ColorRect
var pause_menu: ColorRect
var game_over_menu: ColorRect
var settings_menu: ColorRect
var final_score_label: Label
var best_score_label: Label
var run_stats_label: Label
var record_label: Label
var feedback: Label
var hazard_warning: Label
var debug_label: Label
var settings_sliders: Dictionary = {}
var settings_values: Dictionary = {}
var fullscreen_toggle: CheckButton
var quality_choice: OptionButton
var resolution_choice: OptionButton
var _settings_return: ColorRect
var _feedback_tween: Tween
var _effects: float = 1.0
var _configuring: bool = false
var _boost_fill: StyleBoxFlat
var _mode: int = 0
var _boost_amount: float = 0.0
var _boosting: bool = false
var _recovery_remaining: float = 0.0
var _mode_captions: Array[Label] = []
var _secret_unlocked: bool = false
var _resumed: bool = false
var _reward_boost_remaining: float = 0.0


func _ready() -> void:
	# Menus remain interactive during pause; feedback owns its pausable tween.
	process_mode = Node.PROCESS_MODE_ALWAYS
	interface = Control.new()
	interface.name = "Interface"
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	# Signed-distance text stays crisp when the design space scales to high DPI.
	var font := ThemeDB.fallback_font.duplicate() as FontFile
	font.multichannel_signed_distance_field = true
	font.msdf_size = 64
	ui_theme.default_font = font
	interface.theme = ui_theme
	add_child(interface)
	_resize_interface()
	get_viewport().size_changed.connect(_resize_interface)
	_build_hud(interface)
	menu = _make_overlay(interface, "TitleMenu", "SYNTHWAVE\nDRIVE", "An endless highway. One more run.", MAGENTA)
	_build_mode_choice()
	_add_button(menu, "Start driving", func() -> void: start_pressed.emit(), true)
	_add_secondary_actions(menu, [["Leaderboard", func() -> void: leaderboard_pressed.emit()], ["Settings", func() -> void: _open_settings(menu)], ["Quit", func() -> void: quit_pressed.emit()]])
	_add_controls(menu)
	pause_menu = _make_overlay(interface, "PauseMenu", "Paused", "Your run is waiting.", CYAN)
	_add_button(pause_menu, "Resume", func() -> void: resume_pressed.emit(), true)
	_add_secondary_actions(pause_menu, [["Restart", func() -> void: restart_pressed.emit()], ["Settings", func() -> void: _open_settings(pause_menu)]])
	_add_secondary_actions(pause_menu, [["Main menu", func() -> void: menu_pressed.emit()], ["Quit", func() -> void: quit_pressed.emit()]])
	_add_footer(pause_menu, "Esc  ·  Resume       R  ·  Restart")
	game_over_menu = _make_overlay(interface, "GameOverMenu", "Run complete", "The highway is calling again.", MAGENTA)
	result_mode_label = _make_label("Fair", 22, CYAN)
	result_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column(game_over_menu).add_child(result_mode_label)
	final_score_label = _make_label("SCORE 000000", 42, WHITE)
	final_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column(game_over_menu).add_child(final_score_label)
	best_score_label = _make_label("BEST 000000", 22, MUTED)
	best_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column(game_over_menu).add_child(best_score_label)
	record_label = _make_label("New personal best", 22, ORANGE)
	record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column(game_over_menu).add_child(record_label)
	run_stats_label = _make_label("0.00 km   /   Top combo x1.0\n0 near misses", 22, MUTED)
	run_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column(game_over_menu).add_child(run_stats_label)
	_add_button(game_over_menu, "Restart", func() -> void: restart_pressed.emit(), true)
	_add_secondary_actions(game_over_menu, [["Main menu", func() -> void: menu_pressed.emit()], ["Quit", func() -> void: quit_pressed.emit()]])
	_add_footer(game_over_menu, "R  ·  Restart")
	_build_settings(interface)
	configure_mode(0)
	show_menu()


func _resize_interface() -> void:
	# Keep the user's 3D resolution/aspect, but lay out UI in a readable design space.
	var available := get_viewport().get_visible_rect().size
	var factor := minf(available.x / UI_REFERENCE.x, available.y / UI_REFERENCE.y)
	factor = maxf(factor, 0.1)
	interface.scale = Vector2.ONE * factor
	interface.size = available / factor


func _build_hud(parent: Control) -> void:
	hud = Control.new()
	hud.name = "HUD"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var top := MarginContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 30
	top.offset_top = 24
	top.offset_right = -30
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	var score_column := VBoxContainer.new()
	score_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_column.add_theme_constant_override("separation", 0)
	row.add_child(score_column)
	mode_label = _make_label("Score  ·  Fair", 22, MUTED)
	mode_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	score_column.add_child(mode_label)
	score_label = _make_label("000000", 44, WHITE)
	score_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	score_column.add_child(score_label)
	combo_label = _make_label("x1.0 combo", 24, MAGENTA)
	combo_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	score_column.add_child(combo_label)
	var speed_column := VBoxContainer.new()
	speed_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_column.add_theme_constant_override("separation", -8)
	row.add_child(speed_column)
	speed_label = _make_label("000", 76, CYAN)
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_column.add_child(speed_label)
	var unit := _make_label("km/h", 22, MUTED)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_column.add_child(unit)
	var pause_hint := _make_label("Esc  ·  Pause", 22, MUTED)
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_column.add_child(pause_hint)
	var bottom := CenterContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -112
	bottom.offset_bottom = -24
	var boost_column := VBoxContainer.new()
	boost_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boost_column.custom_minimum_size.x = 420
	boost_column.add_theme_constant_override("separation", 8)
	bottom.add_child(boost_column)
	var boost_header := HBoxContainer.new()
	boost_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boost_column.add_child(boost_header)
	boost_label = _make_label("Boost", 22, CYAN)
	boost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boost_header.add_child(boost_label)
	boost_value_label = _make_label("40%", 22, CYAN)
	boost_header.add_child(boost_value_label)
	boost_meter = ProgressBar.new()
	boost_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boost_meter.custom_minimum_size.y = 12
	boost_meter.show_percentage = false
	boost_meter.add_theme_stylebox_override("background", _panel_style(Color("#1c1837"), Color("#51416b"), 1, 4))
	_boost_fill = _panel_style(CYAN, CYAN, 0, 4)
	boost_meter.add_theme_stylebox_override("fill", _boost_fill)
	boost_column.add_child(boost_meter)
	boost_hint = _make_label("Hold Shift / Space", 22, MUTED)
	boost_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boost_column.add_child(boost_hint)
	feedback = _make_label("", 26, CYAN)
	feedback.name = "Feedback"
	feedback.process_mode = Node.PROCESS_MODE_PAUSABLE
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(feedback)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	feedback.offset_left = -220
	feedback.offset_right = 220
	feedback.offset_top = 166
	feedback.offset_bottom = 208
	feedback.visible = false
	hazard_warning = _make_label("", 22, ORANGE)
	hazard_warning.name = "PotholeWarning"
	hazard_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(hazard_warning)
	hazard_warning.anchor_left = 0.5
	hazard_warning.anchor_right = 0.5
	hazard_warning.offset_left = -260
	hazard_warning.offset_right = 260
	hazard_warning.offset_top = 218
	hazard_warning.offset_bottom = 274
	hazard_warning.visible = false
	debug_label = _make_label("", 18, MUTED)
	debug_label.position = Vector2(30, 210)
	hud.add_child(debug_label)
	debug_label.visible = false


func update_hud(score: int, speed_kmh: int, multiplier: float = 1.0, boost: float = 0.0, boosting: bool = false, recovery: float = 0.0) -> void:
	score_label.text = "%06d" % score
	speed_label.text = "%03d" % speed_kmh
	combo_label.text = "x%.1f combo" % multiplier
	combo_label.modulate = WHITE if multiplier > 1.0 else Color(1, 1, 1, 0.8)
	_boost_amount = clampf(boost, 0.0, 1.0)
	_boosting = boosting
	_recovery_remaining = maxf(0.0, recovery)
	_update_boost_display()


func _update_boost_display() -> void:
	var unlimited := _mode == 1 or _reward_boost_remaining > 0.0
	boost_meter.value = 100.0 if unlimited else _boost_amount * 100.0
	if unlimited:
		boost_label.text = "Boosting  ·  Unlimited" if _boosting else "Unlimited boost"
		boost_value_label.text = "∞"
	else:
		boost_label.text = "Boosting" if _boosting else "Boost"
		boost_value_label.text = "%d%%" % roundi(_boost_amount * 100.0)
	if _recovery_remaining > 0.0 and _mode != 2:
		boost_hint.text = "Recovering  ·  boost in %.1fs" % _recovery_remaining
	else:
		boost_hint.text = "Earn boost with near misses" if not unlimited and _boost_amount <= 0.0 else "Hold Shift / Space"
	boost_label.add_theme_color_override("font_color", ORANGE if _boosting else CYAN)
	boost_value_label.add_theme_color_override("font_color", ORANGE if _boosting else CYAN)
	_boost_fill.bg_color = ORANGE if _boosting else CYAN
	_boost_fill.border_color = _boost_fill.bg_color


func set_reward_boost(remaining: float) -> void:
	_reward_boost_remaining = maxf(0.0, remaining)
	_update_boost_display()


func update_hazard_warning(remaining: float) -> void:
	hazard_warning.visible = remaining > 0.0
	var consequence := "Repeat hits bring the police" if _mode == 2 else "Another hole ends your run"
	hazard_warning.text = "POTHOLE DAMAGE  ·  %.1fs\n%s" % [remaining, consequence] if remaining > 0.0 else ""


func _build_mode_choice() -> void:
	var caption := _make_label("Choose your drive", 22, WHITE)
	_column(menu).add_child(caption)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_column(menu).add_child(row)
	var group := ButtonGroup.new()
	for mode in range(3):
		var button := _make_button("")
		button.name = ["FairMode", "InfiniteBoostMode", "SecretMode"][mode]
		button.tooltip_text = ["Fair mode: earn boost with near misses", "Infinite Boost mode: unlimited boost, separate personal best", "sySTEMatic Secret: earned boost and police pursuits"][mode]
		button.custom_minimum_size = Vector2(256, 88)
		button.visible = mode != 2 or _secret_unlocked
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_stylebox_override("pressed", _panel_style(Color("#12333c"), CYAN, 2, 4))
		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 16
		content.offset_right = -16
		content.offset_top = 11
		content.offset_bottom = -11
		content.add_theme_constant_override("separation", 2)
		var title := _make_label(["Fair", "Infinite Boost", "Secret"][mode], 25, WHITE)
		content.add_child(title)
		_mode_captions.append(title)
		var description := _make_label(["Earn your boost", "Stay at full power", "Outrun the police"][mode], 22, MUTED)
		content.add_child(description)
		button.pressed.connect(func() -> void:
			configure_mode(mode)
			mode_selected.emit(_mode))
		row.add_child(button)
		mode_buttons.append(button)
	mode_detail = _make_label("Earn boost with near misses.", 22, MUTED)
	_column(menu).add_child(mode_detail)


func configure_mode(mode: int) -> void:
	_mode = mode if mode == 1 or (mode == 2 and _secret_unlocked) else 0
	for index in range(mode_buttons.size()):
		mode_buttons[index].set_pressed_no_signal(index == _mode)
		_mode_captions[index].text = ("✓  " if index == _mode else "") + ["Fair", "Infinite Boost", "Secret"][index]
		_mode_captions[index].add_theme_color_override("font_color", CYAN if index == _mode else WHITE)
	var caption: String = ["Fair", "Infinite Boost", "sySTEMatic Secret"][_mode]
	mode_label.text = "Score  ·  " + caption
	result_mode_label.text = caption + " mode"
	if _mode == 2 and _resumed:
		mode_label.text = "Score  ·  Secret  ·  Resumed"
		result_mode_label.text = "sySTEMatic Secret  ·  Resumed run"
	mode_detail.text = ["Close passes earn boost and grow your combo.", "Unlimited boost. Separate personal best.", "Earn boost. Escape police with speed or clean driving."][_mode]
	_update_boost_display()


func configure_secret(unlocked: bool) -> void:
	_secret_unlocked = unlocked
	if mode_buttons.size() > 2:
		mode_buttons[2].visible = unlocked
	if not unlocked and _mode == 2:
		configure_mode(0)


func configure_resumed(enabled: bool) -> void:
	_resumed = enabled
	configure_mode(_mode)


func show_menu() -> void:
	_clear_feedback()
	_show_only(menu)
	hud.visible = false


func show_playing() -> void:
	_clear_feedback()
	_show_only(null)
	hud.visible = true
	# Keyboard focus belongs to steering after a menu button starts/resumes a run.
	var owner := get_viewport().gui_get_focus_owner()
	if owner:
		owner.release_focus()


func show_paused() -> void:
	_show_only(pause_menu)
	hud.visible = true


func show_game_over(score: int, best_score: int, distance: float = 0.0, top_combo: float = 1.0, near_misses: int = 0, new_best: bool = false, reason: String = "", invalid: bool = false, police_scene: bool = false) -> void:
	_clear_feedback()
	update_hazard_warning(0.0)
	final_score_label.text = "SCORE INVALID" if invalid else "SCORE %06d" % score
	final_score_label.add_theme_color_override("font_color", ORANGE if invalid else WHITE)
	best_score_label.text = "BEST %06d" % best_score
	record_label.visible = new_best and not invalid
	var heading: Label = game_over_menu.get_meta("heading")
	var detail: Label = game_over_menu.get_meta("detail")
	heading.text = "Police stop" if invalid else "Run complete"
	detail.text = reason if not reason.is_empty() else "The highway is calling again."
	var center: CenterContainer = game_over_menu.get_meta("center")
	center.anchor_left = 0.4 if police_scene else 0.0
	game_over_menu.color.a = 0.18 if police_scene else 0.72
	run_stats_label.text = "%.2f km   /   Top combo x%.1f\n%d near misses" % [distance / 1000.0, top_combo, near_misses]
	_show_only(game_over_menu)
	hud.visible = not police_scene


func configure_settings(volume: float, shake: float, effects: float, fullscreen: bool, quality: int = 1, resolution: int = 0) -> void:
	_configuring = true
	settings_sliders["volume"].value = clampf(volume, 0.0, 1.0)
	settings_sliders["shake"].value = clampf(shake, 0.0, 1.0)
	settings_sliders["effects"].value = clampf(effects, 0.0, 1.0)
	fullscreen_toggle.button_pressed = fullscreen
	quality_choice.select(clampi(quality, 0, 2))
	resolution_choice.select(clampi(resolution, 0, 3))
	for key in settings_sliders:
		_update_setting_value(key, float(settings_sliders[key].value))
	_configuring = false


func set_effects(amount: float) -> void:
	_effects = clampf(amount, 0.0, 1.0)


func set_debug(text: String, enabled: bool) -> void:
	debug_label.text = text
	debug_label.visible = enabled


func show_feedback(text: String, color: Color = CYAN) -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	feedback.text = text
	feedback.add_theme_color_override("font_color", color)
	feedback.modulate.a = 1.0
	feedback.scale = Vector2.ONE
	feedback.visible = true
	feedback.pivot_offset = feedback.size * 0.5
	_feedback_tween = feedback.create_tween()
	_feedback_tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	if _effects > 0.0:
		feedback.scale = Vector2.ONE * (1.0 + 0.06 * _effects)
		_feedback_tween.tween_property(feedback, "scale", Vector2.ONE, 0.16)
	_feedback_tween.tween_interval(0.65)
	_feedback_tween.tween_property(feedback, "modulate:a", 0.0, 0.3)
	_feedback_tween.tween_callback(func() -> void: feedback.visible = false)


func _clear_feedback() -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	feedback.visible = false


func _build_settings(parent: Control) -> void:
	settings_menu = _make_overlay(parent, "SettingsMenu", "Settings", "Find your rhythm.", CYAN)
	_column(settings_menu).add_theme_constant_override("separation", 10)
	var grabber := _slider_icon(WHITE)
	var active_grabber := _slider_icon(CYAN)
	for entry in [["volume", "Master volume"], ["shake", "Camera shake"], ["effects", "Visual effects"]]:
		var key: String = entry[0]
		var caption: String = entry[1]
		var header := HBoxContainer.new()
		_column(settings_menu).add_child(header)
		var title := _make_label(caption, 24, WHITE)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		var value_label := _make_label("100%", 22, CYAN)
		header.add_child(value_label)
		settings_values[key] = value_label
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = 1.0
		slider.custom_minimum_size.y = 36
		slider.add_theme_icon_override("grabber", grabber)
		slider.add_theme_icon_override("grabber_highlight", active_grabber)
		var track := _panel_style(Color("#282244"), Color("#63527b"), 1, 3)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		slider.add_theme_stylebox_override("slider", track)
		var filled_track := _panel_style(CYAN, CYAN, 0, 3)
		filled_track.content_margin_top = 3
		filled_track.content_margin_bottom = 3
		slider.add_theme_stylebox_override("grabber_area", filled_track)
		slider.value_changed.connect(func(value: float) -> void:
			_update_setting_value(key, value)
			if not _configuring:
				settings_changed.emit(key, value))
		settings_sliders[key] = slider
		_column(settings_menu).add_child(slider)
	quality_choice = _setting_choice("quality", "Render quality", ["Low", "Balanced", "High"])
	quality_choice.tooltip_text = "Low reduces glow. High smooths car and road edges."
	resolution_choice = _setting_choice("resolution", "Window size", ["Current window", "1280 × 720", "1920 × 1080", "2560 × 1440"])
	resolution_choice.tooltip_text = "Smaller windows draw faster. Fullscreen uses your display size."
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "Fullscreen"
	fullscreen_toggle.add_theme_font_size_override("font_size", 24)
	fullscreen_toggle.add_theme_color_override("font_color", WHITE)
	fullscreen_toggle.add_theme_color_override("font_hover_color", CYAN)
	fullscreen_toggle.add_theme_color_override("font_pressed_color", CYAN)
	fullscreen_toggle.add_theme_color_override("font_focus_color", WHITE)
	fullscreen_toggle.add_theme_icon_override("checked", _toggle_icon(true))
	fullscreen_toggle.add_theme_icon_override("unchecked", _toggle_icon(false))
	fullscreen_toggle.add_theme_stylebox_override("normal", _panel_style(Color("#18192f"), Color("#4e465f"), 1, 4, 12))
	fullscreen_toggle.add_theme_stylebox_override("hover", _panel_style(Color("#22263b"), CYAN, 1, 4, 12))
	fullscreen_toggle.add_theme_stylebox_override("pressed", _panel_style(Color("#12333c"), CYAN, 1, 4, 12))
	fullscreen_toggle.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), CYAN, 2, 4))
	fullscreen_toggle.custom_minimum_size.y = 56
	fullscreen_toggle.toggled.connect(func(enabled: bool) -> void:
		if not _configuring:
			settings_changed.emit("fullscreen", 1.0 if enabled else 0.0))
	_column(settings_menu).add_child(fullscreen_toggle)
	_add_button(settings_menu, "Back", _close_settings, true)
	_add_footer(settings_menu, "Esc  ·  Back       Changes save automatically")


func _setting_choice(key: String, caption: String, choices: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_column(settings_menu).add_child(row)
	var label := _make_label(caption, 24, WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var choice := OptionButton.new()
	choice.custom_minimum_size = Vector2(245, 48)
	choice.add_theme_font_size_override("font_size", 22)
	for text in choices:
		choice.add_item(text)
	choice.item_selected.connect(func(index: int) -> void:
		if not _configuring:
			settings_changed.emit(key, float(index)))
	row.add_child(choice)
	return choice


func _update_setting_value(key: String, value: float) -> void:
	settings_values[key].text = "%d%%" % roundi(value * 100.0)


func _open_settings(previous: ColorRect) -> void:
	_settings_return = previous
	_show_only(settings_menu)


func _close_settings() -> void:
	_show_only(_settings_return if _settings_return else menu)


func is_settings_open() -> bool:
	return settings_menu.visible


func _input(event: InputEvent) -> void:
	if settings_menu and settings_menu.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_settings()
		get_viewport().set_input_as_handled()


func _unhandled_key_input(_event: InputEvent) -> void:
	# Prevent root start/restart shortcuts from dismissing settings by accident.
	if settings_menu and settings_menu.visible:
		get_viewport().set_input_as_handled()


func _show_only(active_overlay: ColorRect) -> void:
	for overlay in [menu, pause_menu, game_over_menu, settings_menu]:
		if overlay:
			overlay.visible = active_overlay == overlay
	if active_overlay:
		var first: Button = active_overlay.get_meta("first_button", null)
		if first:
			first.grab_focus()


func _make_overlay(parent: Control, node_name: String, title: String, subtitle: String, accent: Color) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.name = node_name
	overlay.color = Color(0.025, 0.015, 0.07, 0.72)
	parent.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 600
	var panel_style := _panel_style(Color("#101124"), Color(accent, 0.48), 1, 6, 30)
	panel_style.border_width_top = 3
	panel_style.shadow_color = Color(0, 0, 0, 0.35)
	panel_style.shadow_size = 16
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	if node_name == "TitleMenu":
		var eyebrow := _make_label("ENDLESS ARCADE DRIVING", 18, CYAN)
		column.add_child(eyebrow)
	var heading := _make_label(title, 52 if node_name == "TitleMenu" else 42, WHITE)
	if node_name == "TitleMenu":
		heading.add_theme_constant_override("line_spacing", -10)
		title_label = heading
		var branding := HBoxContainer.new()
		branding.name = "Branding"
		branding.mouse_filter = Control.MOUSE_FILTER_IGNORE
		branding.add_theme_constant_override("separation", 22)
		column.add_child(branding)
		brand_logo = TextureRect.new()
		brand_logo.name = "sySTEMaticRoboticsLogo"
		brand_logo.texture = load("res://logo.png") as Texture2D
		brand_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		brand_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		brand_logo.custom_minimum_size = Vector2(140, 140)
		brand_logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		brand_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		brand_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		branding.add_child(brand_logo)
		heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		branding.add_child(heading)
	else:
		column.add_child(heading)
	var detail := _make_label(subtitle, 22, MUTED)
	column.add_child(detail)
	overlay.set_meta("column", column)
	overlay.set_meta("panel", panel)
	overlay.set_meta("center", center)
	overlay.set_meta("heading", heading)
	overlay.set_meta("detail", detail)
	return overlay


func _column(overlay: ColorRect) -> VBoxContainer:
	return overlay.get_meta("column")


func _add_button(overlay: ColorRect, title: String, action: Callable, primary: bool = false) -> void:
	var button := _make_button(title, primary)
	button.pressed.connect(action)
	_column(overlay).add_child(button)
	if not overlay.has_meta("first_button"):
		overlay.set_meta("first_button", button)


func _add_secondary_actions(overlay: ColorRect, actions: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_column(overlay).add_child(row)
	for action in actions:
		var button := _make_button(action[0])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(action[1])
		row.add_child(button)


func _add_footer(overlay: ColorRect, text: String) -> void:
	var footer := _make_label(text, 22, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_column(overlay).add_child(footer)


func _add_controls(overlay: ColorRect) -> void:
	var rule := ColorRect.new()
	rule.color = Color(MUTED, 0.22)
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column(overlay).add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_column(overlay).add_child(row)
	for entry in [["A / D  ·  ← / →", "Steer"], ["Shift / Space", "Boost"], ["Esc", "Pause"]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 3)
		row.add_child(column)
		var keys := _make_label(entry[0], 22, WHITE)
		keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(keys)
		var caption := _make_label(entry[1], 22, MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)


func _make_button(title: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 64 if primary else 56)
	button.add_theme_font_size_override("font_size", 25)
	button.add_theme_color_override("font_color", INK if primary else WHITE)
	button.add_theme_color_override("font_hover_color", INK if primary else CYAN)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK if primary else WHITE)
	button.add_theme_stylebox_override("normal", _panel_style(CYAN if primary else Color("#18192f"), CYAN if primary else Color("#4e465f"), 1, 4, 10))
	button.add_theme_stylebox_override("hover", _panel_style(Color("#a5f6fb") if primary else Color("#22263b"), CYAN, 1, 4, 10))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("#49b8c6"), CYAN, 1, 4, 10))
	button.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), WHITE if primary else CYAN, 2, 4))
	return button


func _make_label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.01, 0.005, 0.035, 0.8))
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _panel_style(background: Color, border: Color, border_width: int, radius: int, padding: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _toggle_icon(enabled: bool) -> ImageTexture:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="26"><rect x="1" y="1" width="46" height="24" rx="12" fill="%s" stroke="%s" stroke-width="2"/><circle cx="%d" cy="13" r="8" fill="%s"/></svg>' % ["#70eaf3" if enabled else "#36384f", "#70eaf3" if enabled else "#b6b1d2", 35 if enabled else 13, "#101126" if enabled else "#f0eef7"]
	var icon_image := Image.new()
	icon_image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(icon_image)


func _slider_icon(color: Color) -> ImageTexture:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22"><circle cx="11" cy="11" r="9" fill="#%s" stroke="#101126" stroke-width="2"/></svg>' % color.to_html(false)
	var icon_image := Image.new()
	icon_image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(icon_image)
