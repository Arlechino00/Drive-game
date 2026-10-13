class_name RadarDisplay
extends Node3D

const L = preload("res://scripts/localization.gd")

# A fixed pair of roadside props follows distance; it never participates in physics.
const PROP_RANGE := DifficultyDirector.Tuning.LOOK_AHEAD_MAX
const PASSED_RANGE := 35.0
const RADAR_WARNING_DISTANCE: float = preload("res://scripts/speed_enforcement.gd").WARNING_DISTANCE

var warning_distance: float = RADAR_WARNING_DISTANCE

var panel: PanelContainer
var limit_label: Label
var radar_label: Label
var upcoming_label: Label
var brake_label: Label
var fine_label: Label
var sector_sign: Node3D
var radar_camera: Node3D
var sign_limit: Label3D
var camera_limit: Label3D

var _ui: GameUI
var _sign_value: int = -1
var _camera_value: int = -1
var _overspeed: bool = false
var _braking: bool = false
var _sign_style: StyleBoxFlat
var _last_display: Array = [0.0, 0, 0, INF, INF, false, 0.0, false, 0]
var _has_display: bool = false


func attach(base_ui: GameUI) -> void:
	if _ui != null:
		return
	_ui = base_ui
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_hud()
	_build_roadside()
	reset_display()
	_ui.language_changed.connect(_refresh_language)


func update_display(distance: float, current_limit: int, next_limit: int, sector_at: float, radar_at: float, radar_pending: bool, speed_kmh: float, braking: bool, fine_points: int) -> void:
	if _ui == null:
		return
	_has_display = true
	_last_display[0] = distance
	_last_display[1] = current_limit
	_last_display[2] = next_limit
	_last_display[3] = sector_at
	_last_display[4] = radar_at
	_last_display[5] = radar_pending
	_last_display[6] = speed_kmh
	_last_display[7] = braking
	_last_display[8] = fine_points
	panel.visible = true
	limit_label.text = str(current_limit) if current_limit > 0 else "∞"
	var overspeed := current_limit > 0 and speed_kmh > float(current_limit)
	if overspeed != _overspeed:
		_overspeed = overspeed
		_sign_style.border_color = GameUI.ORANGE if overspeed else GameUI.MAGENTA
		radar_label.add_theme_color_override("font_color", GameUI.ORANGE if overspeed else GameUI.CYAN)
	if braking != _braking:
		_braking = braking
		brake_label.add_theme_color_override("font_color", GameUI.CYAN if braking else GameUI.MUTED)
	brake_label.text = L.text("ui.braking") if braking else (L.text("ui.hold_brake") if _ui.mobile_mode else L.text("ui.s_lt_brake"))
	fine_label.text = L.text("ui.fines") + str(maxi(0, fine_points)) + L.text("ui.pts")
	var sector_gap := sector_at - distance
	var radar_gap := radar_at - distance
	if radar_pending and is_finite(radar_at) and radar_gap >= 0.0 and radar_gap <= warning_distance:
		radar_label.text = L.text("ui.radar_in") + str(ceili(radar_gap)) + L.text("ui.m")
	elif not is_finite(radar_at) or (radar_pending and radar_gap > warning_distance):
		radar_label.text = L.text("ui.no_radar_reported")
	else:
		radar_label.text = L.text("ui.radar_passed") if current_limit > 0 else L.text("ui.unlimited_road")
	if is_finite(sector_at) and sector_gap > 0.0:
		upcoming_label.text = L.text("ui.next") + _limit_text(next_limit) + L.text("ui.in") + str(ceili(sector_gap)) + L.text("ui.m")
	else:
		upcoming_label.text = L.text("ui.limited_sector") if current_limit > 0 else L.text("ui.no_limit_ahead")
	sector_sign.visible = is_finite(sector_at) and sector_gap >= -PASSED_RANGE and sector_gap <= PROP_RANGE
	# Only inside a limited sector, so it appears shortly after the sign, never on ∞ road.
	radar_camera.visible = current_limit > 0 and is_finite(radar_at) and radar_gap >= -PASSED_RANGE and radar_gap <= warning_distance
	sector_sign.position.z = -sector_gap if is_finite(sector_gap) else -PROP_RANGE
	radar_camera.position.z = -radar_gap if is_finite(radar_gap) else -PROP_RANGE
	if next_limit != _sign_value:
		_sign_value = next_limit
		sign_limit.text = str(next_limit) if next_limit > 0 else "∞"
	# The camera belongs to this restriction, even before the driver enters it.
	if next_limit != _camera_value:
		_camera_value = next_limit
		camera_limit.text = str(next_limit) if next_limit > 0 else "∞"


func reset_display() -> void:
	if _ui == null:
		return
	_has_display = false
	panel.visible = false
	sector_sign.visible = false
	radar_camera.visible = false
	limit_label.text = "∞"
	radar_label.text = ""
	upcoming_label.text = ""
	brake_label.text = L.text("ui.hold_brake") if _ui.mobile_mode else L.text("ui.s_lt_brake")
	fine_label.text = L.text("ui.fines_0_pts")
	_overspeed = false
	_braking = false
	_sign_style.border_color = GameUI.MAGENTA
	radar_label.add_theme_color_override("font_color", GameUI.CYAN)
	brake_label.add_theme_color_override("font_color", GameUI.MUTED)


func _limit_text(limit: int) -> String:
	return str(limit) if limit > 0 else L.text("ui.unlimited")


func _build_hud() -> void:
	panel = PanelContainer.new()
	panel.name = "RadarHUD"
	# Long braking distances and translated captions grow toward the road,
	# preserving the right margin rather than overflowing narrow screens.
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _ui._panel_style(Color("#101124"), Color(GameUI.CYAN, 0.65), 1, 5, 8))
	_ui.hud.add_child(panel)
	# The UI's minimum design width is 1100. This clears the central feedback,
	# the top speed statistics, and the Apex side notices starting at y=292.
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -344.0 if _ui.mobile_mode else -280.0
	panel.offset_right = -24.0
	panel.offset_top = 174.0
	panel.offset_bottom = 322.0 if _ui.mobile_mode else 284.0
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var sign := PanelContainer.new()
	sign.name = "CurrentSpeedLimit"
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.custom_minimum_size = Vector2(66.0, 66.0)
	sign.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sign_style = _ui._panel_style(GameUI.WHITE, GameUI.MAGENTA, 3, 33, 2)
	sign.add_theme_stylebox_override("panel", _sign_style)
	row.add_child(sign)
	var badge_column := VBoxContainer.new()
	badge_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_column.add_theme_constant_override("separation", -4)
	badge_column.alignment = BoxContainer.ALIGNMENT_CENTER
	sign.add_child(badge_column)
	limit_label = _ui._make_label("∞", 34, GameUI.INK)
	limit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	limit_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	badge_column.add_child(limit_label)
	var unit := _ui._make_label("km/h", 12, GameUI.INK)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	badge_column.add_child(unit)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(column)
	var text_size: int = 24 if _ui.mobile_mode else 16
	radar_label = _hud_label(column, "", 24 if _ui.mobile_mode else 20, GameUI.CYAN)
	upcoming_label = _hud_label(column, "", text_size, GameUI.WHITE)
	brake_label = _hud_label(column, L.text("ui.hold_brake") if _ui.mobile_mode else L.text("ui.s_lt_brake"), text_size, GameUI.MUTED)
	fine_label = _hud_label(column, L.text("ui.fines_0_pts"), text_size, GameUI.ORANGE)


func _hud_label(parent: Control, value: String, font_size: int, color: Color) -> Label:
	var label := _ui._make_label(value, font_size, color)
	parent.add_child(label)
	return label


func _build_roadside() -> void:
	var metal := _material(Color("#525577"))
	var white := _material(GameUI.WHITE)
	var pink := _material(GameUI.MAGENTA)
	var dark := _material(GameUI.INK)
	var cyan := _material(GameUI.CYAN)
	sector_sign = Node3D.new()
	sector_sign.name = "SectorSpeedSign"
	sector_sign.position.x = 10.7
	add_child(sector_sign)
	_box(sector_sign, Vector3(0, 1.85, 0), Vector3(0.16, 3.7, 0.16), metal)
	# Signs face +Z toward the approaching player, who remains at the origin.
	_disc(sector_sign, Vector3(0, 3.75, 0), 1.1, 0.14, pink)
	_disc(sector_sign, Vector3(0, 3.75, 0.08), 0.93, 0.06, white)
	sign_limit = _world_label(sector_sign, Vector3(0, 3.75, 0.13), "∞", 110, 0.01, GameUI.INK)
	_world_label(sector_sign, Vector3(0, 2.45, 0.15), L.text("ui.speed_limit"), 40, 0.008, GameUI.WHITE)
	radar_camera = Node3D.new()
	radar_camera.name = "RoadsideRadarCamera"
	radar_camera.position.x = 10.4
	add_child(radar_camera)
	_box(radar_camera, Vector3(0, 1.7, 0), Vector3(0.18, 3.4, 0.18), metal)
	_box(radar_camera, Vector3(0, 3.5, 0), Vector3(1.0, 0.85, 0.6), white)
	_box(radar_camera, Vector3(0, 3.55, 0.32), Vector3(0.7, 0.52, 0.04), dark)
	_disc(radar_camera, Vector3(0.13, 3.55, 0.37), 0.15, 0.06, cyan)
	_box(radar_camera, Vector3(-0.21, 3.55, 0.37), Vector3(0.15, 0.15, 0.03), pink)
	_box(radar_camera, Vector3(0, 2.3, 0.05), Vector3(1.8, 0.9, 0.12), dark)
	_world_label(radar_camera, Vector3(0, 2.53, 0.13), L.text("ui.radar"), 48, 0.007, GameUI.CYAN)
	camera_limit = _world_label(radar_camera, Vector3(0, 2.08, 0.13), "∞", 54, 0.008, GameUI.WHITE)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _box(parent: Node3D, at: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _disc(parent: Node3D, at: Vector3, radius: float, depth: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = 32
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.rotation.x = PI * 0.5
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)


func _world_label(parent: Node3D, at: Vector3, value: String, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.position = at
	L.bind(label, "text", value)
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	parent.add_child(label)
	return label


func _refresh_language() -> void:
	L.refresh(self)
	if _has_display:
		update_display.callv(_last_display)
	else:
		reset_display()
