class_name CommunityUI
extends Node

signal name_submitted(name: String)
signal secret_code_submitted(code: String)
signal resume_code_submitted(code: String)
signal leaderboard_requested(mode: int, resumed: bool)

var name_input: LineEdit
var access_input: LineEdit
var bribe_input: LineEdit
var name_dialog: ColorRect
var access_dialog: ColorRect
var bribe_dialog: ColorRect
var leaderboard_dialog: ColorRect
var resume_button: Button
var leaderboard_tabs: Array[Button] = []
var resumed_filter: CheckButton
var leaderboard_rows: VBoxContainer
var leaderboard_empty: Label
var rearview_panel: PanelContainer
var rearview_image: TextureRect
var pursuit_caption: Label

var _ui: GameUI
var _modal: ColorRect
var _return_overlay: ColorRect
var _return_hud: bool = false
var _leaderboard_mode: int = 0
var _leaderboard_resumed: bool = false
var _configuring: bool = false
var _resume_available: bool = false


func attach(base_ui: GameUI) -> void:
	if _ui != null:
		return
	_ui = base_ui
	process_mode = Node.PROCESS_MODE_ALWAYS
	name_dialog = _dialog("DriverNameDialog", "Your driver name", "Up to 24 characters. Your best runs stay on this computer.", GameUI.CYAN)
	name_input = _text_field(name_dialog, "Driver name", false, 24)
	_add_error(name_dialog)
	_actions(name_dialog, "Start driving", _submit_name)
	access_dialog = _dialog("SecretAccessDialog", "Systematic Secret", "Enter the access code from the Systematic Robotics team.", GameUI.MAGENTA)
	access_input = _text_field(access_dialog, "Access code", true)
	_add_error(access_dialog)
	_actions(access_dialog, "Unlock Secret", func() -> void: secret_code_submitted.emit(access_input.text))
	bribe_dialog = _dialog("BribeResumeDialog", "Bribe / resume", "Like a Systematic Robotics post, then ask the team for the resume code.\nOne continuation per run. Resumed runs have their own ranking.", GameUI.ORANGE)
	bribe_input = _text_field(bribe_dialog, "Resume code", true)
	_add_error(bribe_dialog)
	_actions(bribe_dialog, "Resume driving", func() -> void: resume_code_submitted.emit(bribe_input.text))
	_build_leaderboard()
	_build_rearview()
	resume_button = _ui._make_button("Bribe / resume")
	resume_button.name = "BribeResumeOffer"
	resume_button.visible = false
	resume_button.pressed.connect(_request_resume)
	var results: VBoxContainer = _ui._column(_ui.game_over_menu)
	results.add_child(resume_button)
	# Put continuation before the ordinary restart row; keep existing result actions.
	results.move_child(resume_button, results.get_child_count() - 4)
	_ui.leaderboard_pressed.connect(func() -> void: leaderboard_requested.emit(_ui._mode, false))
	_ui.menu.visibility_changed.connect(_hide_stale_offer)
	_ui.hud.visibility_changed.connect(_hide_stale_offer)


func request_name(prefill: String) -> void:
	name_input.text = prefill
	_clear_error(name_dialog)
	_open(name_dialog, name_input)
	name_input.caret_column = name_input.text.length()


func request_access() -> void:
	access_input.clear()
	_clear_error(access_dialog)
	_open(access_dialog, access_input)


func show_name_error(message: String) -> void:
	_error(name_dialog, message, name_input)


func show_access_error(message: String) -> void:
	_error(access_dialog, message, access_input)


func show_resume_error(message: String) -> void:
	_error(bribe_dialog, message, bribe_input)


func set_resume_available(enabled: bool) -> void:
	_resume_available = enabled
	resume_button.visible = enabled
	if not enabled and _modal == bribe_dialog:
		dismiss()


func show_leaderboard(entries: Array[Dictionary], mode: int, resumed: bool = false) -> void:
	_leaderboard_mode = clampi(mode, 0, 2)
	_leaderboard_resumed = resumed and _leaderboard_mode == 2
	_configuring = true
	for index in range(leaderboard_tabs.size()):
		leaderboard_tabs[index].set_pressed_no_signal(index == _leaderboard_mode)
	resumed_filter.visible = _leaderboard_mode == 2
	resumed_filter.set_pressed_no_signal(_leaderboard_resumed)
	_configuring = false
	for row in leaderboard_rows.get_children():
		leaderboard_rows.remove_child(row)
		row.queue_free()
	leaderboard_empty.visible = entries.is_empty()
	for index in range(mini(10, entries.size())):
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 32
		row.add_theme_constant_override("separation", 14)
		leaderboard_rows.add_child(row)
		var rank := _ui._make_label("%d" % (index + 1), 22, GameUI.MUTED)
		rank.custom_minimum_size.x = 32
		row.add_child(rank)
		var driver := _ui._make_label(str(entries[index].get("name", "Driver")), 22, GameUI.WHITE)
		driver.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		driver.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		driver.custom_minimum_size.x = 180
		row.add_child(driver)
		var score := _ui._make_label(_score_text(int(entries[index].get("score", 0))), 22, GameUI.CYAN)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score.custom_minimum_size.x = 210
		row.add_child(score)
		row.set_meta("name_label", driver)
		row.set_meta("score_label", score)
		row.tooltip_text = "%s · %.2f km · %d escapes" % [driver.text, float(entries[index].get("distance", 0.0)) / 1000.0, int(entries[index].get("escapes", 0))]
	_open(leaderboard_dialog, leaderboard_tabs[_leaderboard_mode])


func set_rearview_texture(texture: Texture2D) -> void:
	rearview_image.texture = texture


func update_pursuit(active: bool, gap_m: float, clean_seconds: float) -> void:
	rearview_panel.visible = active and _ui.hud.visible and _modal == null
	pursuit_caption.text = "POLICE %dm  ·  Clean %d/16s" % [roundi(maxf(0.0, gap_m)), floori(clampf(clean_seconds, 0.0, 16.0))]


func dismiss() -> void:
	if _modal == null:
		return
	_modal.visible = false
	_modal = null
	_ui._show_only(_return_overlay)
	_ui.hud.visible = _return_hud
	_return_overlay = null
	if _ui.menu.visible:
		_hide_stale_offer()


func is_modal_open() -> bool:
	return _modal != null and _modal.visible


func _dialog(node_name: String, title: String, detail: String, accent: Color) -> ColorRect:
	var dialog := _ui._make_overlay(_ui.interface, node_name, title, detail, accent)
	var panel: PanelContainer = dialog.get_meta("panel")
	panel.custom_minimum_size.x = 660
	var subtitle: Label = dialog.get_meta("detail")
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.visible = false
	return dialog


func _text_field(dialog: ColorRect, placeholder: String, private_code: bool, max_length: int = 128) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.secret = private_code
	field.max_length = max_length
	field.custom_minimum_size.y = 56
	field.add_theme_font_size_override("font_size", 25)
	field.add_theme_color_override("font_color", GameUI.WHITE)
	field.add_theme_color_override("font_placeholder_color", GameUI.MUTED)
	field.add_theme_stylebox_override("normal", _ui._panel_style(Color("#18192f"), Color("#4e465f"), 1, 4, 12))
	field.add_theme_stylebox_override("focus", _ui._panel_style(Color("#18192f"), GameUI.CYAN, 2, 4, 12))
	_ui._column(dialog).add_child(field)
	return field


func _add_error(dialog: ColorRect) -> void:
	var label := _ui._make_label("", 22, GameUI.ORANGE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.visible = false
	_ui._column(dialog).add_child(label)
	dialog.set_meta("error", label)


func _actions(dialog: ColorRect, primary: String, submit: Callable) -> void:
	_ui._add_button(dialog, primary, submit, true)
	_ui._add_button(dialog, "Cancel", dismiss)
	_ui._add_footer(dialog, "Enter  ·  Confirm       Esc  ·  Cancel")


func _build_leaderboard() -> void:
	leaderboard_dialog = _dialog("LeaderboardDialog", "Leaderboard", "On this computer  ·  Best score per driver", GameUI.CYAN)
	var panel: PanelContainer = leaderboard_dialog.get_meta("panel")
	panel.custom_minimum_size.x = 950
	panel.add_theme_stylebox_override("panel", _ui._panel_style(Color("#101124"), Color(GameUI.CYAN, 0.48), 1, 6, 24))
	var column := _ui._column(leaderboard_dialog)
	column.add_theme_constant_override("separation", 8)
	var heading: Label = leaderboard_dialog.get_meta("heading")
	heading.add_theme_font_size_override("font_size", 34)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	column.add_child(tabs)
	var group := ButtonGroup.new()
	for mode in range(3):
		var button := _ui._make_button(["Fair", "Infinite Boost", "Secret"][mode])
		button.custom_minimum_size.y = 48
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = group
		button.add_theme_stylebox_override("pressed", _ui._panel_style(Color("#12333c"), GameUI.CYAN, 2, 4, 10))
		button.add_theme_color_override("font_pressed_color", GameUI.CYAN)
		button.add_theme_color_override("font_hover_pressed_color", GameUI.WHITE)
		button.pressed.connect(func() -> void: leaderboard_requested.emit(mode, false))
		tabs.add_child(button)
		leaderboard_tabs.append(button)
	resumed_filter = CheckButton.new()
	resumed_filter.text = "Resumed Secret runs"
	resumed_filter.custom_minimum_size.y = 40
	resumed_filter.add_theme_font_size_override("font_size", 22)
	resumed_filter.add_theme_color_override("font_color", GameUI.WHITE)
	resumed_filter.add_theme_icon_override("checked", _ui._toggle_icon(true))
	resumed_filter.add_theme_icon_override("unchecked", _ui._toggle_icon(false))
	resumed_filter.add_theme_stylebox_override("focus", _ui._panel_style(Color(0, 0, 0, 0), GameUI.CYAN, 2, 4))
	resumed_filter.toggled.connect(func(enabled: bool) -> void:
		if not _configuring:
			leaderboard_requested.emit(2, enabled))
	column.add_child(resumed_filter)
	var table_header := HBoxContainer.new()
	column.add_child(table_header)
	var names := _ui._make_label("DRIVER", 20, GameUI.MUTED)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_header.add_child(names)
	table_header.add_child(_ui._make_label("BEST SCORE", 20, GameUI.MUTED))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 340
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(contents)
	leaderboard_empty = _ui._make_label("No runs yet. Start driving to set the first score.", 22, GameUI.MUTED)
	leaderboard_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_child(leaderboard_empty)
	leaderboard_rows = VBoxContainer.new()
	leaderboard_rows.add_theme_constant_override("separation", 2)
	contents.add_child(leaderboard_rows)
	_ui._add_button(leaderboard_dialog, "Back", dismiss)
	leaderboard_dialog.set_meta("first_button", leaderboard_tabs[0])


func _build_rearview() -> void:
	rearview_panel = PanelContainer.new()
	rearview_panel.name = "PursuitRearView"
	rearview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rearview_panel.add_theme_stylebox_override("panel", _ui._panel_style(Color("#101124"), GameUI.ORANGE, 2, 4, 4))
	_ui.hud.add_child(rearview_panel)
	rearview_panel.anchor_left = 0.5
	rearview_panel.anchor_right = 0.5
	rearview_panel.offset_left = -160
	rearview_panel.offset_right = 160
	rearview_panel.offset_top = 20
	rearview_panel.offset_bottom = 150
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 2)
	rearview_panel.add_child(content)
	rearview_image = TextureRect.new()
	rearview_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rearview_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rearview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rearview_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(rearview_image)
	pursuit_caption = _ui._make_label("POLICE", 22, GameUI.ORANGE)
	pursuit_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(pursuit_caption)
	rearview_panel.visible = false


func _submit_name() -> void:
	var value := name_input.text.strip_edges()
	if value.is_empty():
		show_name_error("Enter a driver name to start.")
		return
	name_submitted.emit(value)


func _request_resume() -> void:
	if not _resume_available or not _ui.game_over_menu.visible:
		return
	bribe_input.clear()
	_clear_error(bribe_dialog)
	_open(bribe_dialog, bribe_input)


func _open(dialog: ColorRect, focus: Control) -> void:
	if _modal == null:
		_return_overlay = null
		for overlay in [_ui.menu, _ui.pause_menu, _ui.game_over_menu, _ui.settings_menu]:
			if overlay.visible:
				_return_overlay = overlay
				break
		_return_hud = _ui.hud.visible
	else:
		_modal.visible = false
	_ui._show_only(null)
	_ui.hud.visible = false
	rearview_panel.visible = false
	_modal = dialog
	dialog.visible = true
	focus.grab_focus()


func _clear_error(dialog: ColorRect) -> void:
	var label: Label = dialog.get_meta("error")
	label.text = ""
	label.visible = false


func _error(dialog: ColorRect, message: String, field: LineEdit) -> void:
	var label: Label = dialog.get_meta("error")
	label.text = message
	label.visible = not message.is_empty()
	if dialog.visible:
		field.grab_focus()


func _hide_stale_offer() -> void:
	if _ui.menu.visible or _ui.hud.visible and not _ui.game_over_menu.visible:
		_resume_available = false
		resume_button.visible = false
	if not _ui.hud.visible:
		rearview_panel.visible = false


func _score_text(score: int) -> String:
	var digits := str(maxi(0, score))
	var result := ""
	for index in range(digits.length()):
		if index > 0 and (digits.length() - index) % 3 == 0:
			result += ","
		result += digits[index]
	return result


func _input(event: InputEvent) -> void:
	if not is_modal_open() or not event is InputEventKey:
		return
	if event.keycode == KEY_ESCAPE:
		if event.pressed and not event.echo:
			dismiss()
		get_viewport().set_input_as_handled()
	elif _modal == leaderboard_dialog and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		var tab_index := leaderboard_tabs.find(get_viewport().gui_get_focus_owner())
		if tab_index >= 0:
			if event.pressed:
				var step := 1 if event.keycode == KEY_RIGHT else -1
				leaderboard_tabs[posmod(tab_index + step, leaderboard_tabs.size())].grab_focus()
			get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F8 or (event.keycode == KEY_S and event.ctrl_pressed and event.shift_pressed):
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
		var focused := get_viewport().gui_get_focus_owner()
		if focused in [name_input, access_input, bribe_input]:
			if event.pressed and not event.echo:
				if _modal == name_dialog:
					_submit_name()
				elif _modal == access_dialog:
					secret_code_submitted.emit(access_input.text)
				elif _modal == bribe_dialog:
					resume_code_submitted.emit(bribe_input.text)
			get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	# Text entry receives letters first; anything it leaves unhandled stays in the modal.
	# Leave focus navigation to Godot's viewport after unhandled key input.
	if is_modal_open() and event is InputEventKey and event.keycode not in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_TAB]:
		get_viewport().set_input_as_handled()
