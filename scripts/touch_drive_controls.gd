class_name TouchDriveControls
extends Control

const L = preload("res://scripts/localization.gd")

signal pause_pressed
signal boost_released

var left_button: Button
var right_button: Button
var brake_button: Button
var boost_button: Button
var pause_button: Button
var areas: Dictionary = {}
var buttons: Dictionary = areas

var _enabled: bool = false
var _driving: bool = false
var _touches: Dictionary = {}
var _attached: bool = false


func attach(ui: GameUI) -> void:
	if _attached:
		return
	_attached = true
	name = "TouchDriveControls"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.hud.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	left_button = _button("left", "◀", GameUI.CYAN, false, 24.0)
	right_button = _button("right", "▶", GameUI.CYAN, false, 156.0)
	brake_button = _button("brake", L.text("ui.brake"), GameUI.ORANGE, true, -276.0)
	boost_button = _button("boost", L.text("ui.boost_alt"), GameUI.MAGENTA, true, -144.0)
	pause_button = _button("pause", L.text("ui.pause"), GameUI.CYAN, false, 224.0)
	pause_button.anchor_left = 0.5
	pause_button.anchor_right = 0.5
	pause_button.anchor_top = 0.0
	pause_button.anchor_bottom = 0.0
	pause_button.offset_top = 28.0
	pause_button.offset_bottom = 114.0
	pause_button.add_theme_font_size_override("font_size", 25)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(clear_inputs)
	_sync_visibility()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	_sync_visibility()


func set_driving(driving: bool) -> void:
	_driving = driving
	_sync_visibility()


func clear_inputs() -> void:
	var had_boost := get_boost_requested()
	_touches.clear()
	_sync_buttons()
	if had_boost:
		boost_released.emit()


func get_steering_axis() -> float:
	return float(_held("right")) - float(_held("left"))


func get_boost_requested() -> bool:
	return _held("boost")


func get_brake_requested() -> bool:
	return _held("brake")


func _input(event: InputEvent) -> void:
	if not _enabled or not _driving or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.canceled or not event.pressed:
			var was_control_touch := _touches.has(event.index)
			_release(event.index)
			if was_control_touch:
				get_viewport().set_input_as_handled()
			return
		# The same pointer index may be reused after Android cancels a gesture.
		_release(event.index)
		for action in areas:
			if _contains(areas[action], event.position):
				if action == "pause":
					clear_inputs()
					pause_pressed.emit()
				else:
					_touches[event.index] = action
					_sync_buttons()
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventScreenDrag and _touches.has(event.index):
		var action: String = _touches[event.index]
		if not _contains(areas[action], event.position):
			_release(event.index)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		clear_inputs()


func _button(action: String, caption: String, color: Color, right_side: bool, horizontal: float) -> Button:
	var button := Button.new()
	button.name = action.capitalize() + "Touch"
	L.bind(button, "text", caption)
	button.toggle_mode = true
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.focus_mode = Control.FOCUS_NONE
	button.anchor_left = 1.0 if right_side else 0.0
	button.anchor_right = button.anchor_left
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	button.offset_left = horizontal
	button.offset_right = horizontal + 124.0
	button.offset_top = -152.0
	button.offset_bottom = -28.0
	button.add_theme_font_size_override("font_size", 25 if action in ["brake", "boost"] else 42)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_pressed_color", GameUI.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color("#101126d9"), color))
	button.add_theme_stylebox_override("pressed", _style(Color(color, 0.35), color))
	button.add_theme_stylebox_override("hover", button.get_theme_stylebox("normal"))
	add_child(button)
	areas[action] = button
	return button


func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color(border, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	return style


func _contains(area: Control, position: Vector2) -> bool:
	# Screen events use viewport coordinates; the HUD scales its design space.
	var local := area.get_global_transform_with_canvas().affine_inverse() * position
	return Rect2(Vector2.ZERO, area.size).has_point(local)


func _held(action: String) -> bool:
	for index in _touches:
		if _touches[index] == action:
			return true
	return false


func _release(index: int) -> void:
	if not _touches.has(index):
		return
	var had_boost := get_boost_requested()
	_touches.erase(index)
	_sync_buttons()
	if had_boost and not get_boost_requested():
		boost_released.emit()


func _sync_buttons() -> void:
	for action in areas:
		areas[action].set_pressed_no_signal(_held(action))


func _sync_visibility() -> void:
	if not _enabled or not _driving:
		clear_inputs()
	visible = _enabled and _driving


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		clear_inputs()
