class_name ApexRaceUI
extends Node

const NOTIFICATION_SECONDS := 5.0
const FEED_ROAD_LAYER := 1 << 19

var race_panel: PanelContainer
var countdown_label: Label
var lead_label: Label
var requirements_label: Label
var notification_panel: PanelContainer
var notification_title: Label
var notification_detail: Label
var reward_panel: PanelContainer
var reward_label: Label
var notification_remaining: float = 0.0
var opponent_panel: PanelContainer
var opponent_image: TextureRect
var opponent_caption: Label
var opponent_view: SubViewport
var opponent_camera: Camera3D
var opponent_road: Node3D
var opponent_road_floor: MeshInstance3D

var _ui: GameUI
var _race_active: bool = false
var _reward_remaining: float = 0.0
var _opponent: Node3D
var _lead_m: float = 0.0
var _road_marking: MultiMeshInstance3D
var _road_cyan_edges: Array[MeshInstance3D] = []
var _road_pink_edges: Array[MeshInstance3D] = []
var _dash_phase: float = 0.0


func attach(base_ui: GameUI) -> void:
	if _ui != null:
		return
	_ui = base_ui
	# HUD menus process during pause. Keep visibility responsive, but advance the
	# notification clock only while the run and its scene tree are unpaused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	race_panel = _panel("ApexRaceStatus", 420.0, 24.0, 150.0, GameUI.CYAN)
	countdown_label = _label(race_panel, "APEX RACE", 26, GameUI.WHITE)
	lead_label = _label(race_panel, "SIDE BY SIDE", 22, GameUI.CYAN)
	requirements_label = _label(race_panel, "BOOST 0.0/4.0s  ·  CLEAN", 20, GameUI.MUTED)
	notification_panel = _panel("ApexNotification", 460.0, 292.0, 500.0, GameUI.MAGENTA)
	notification_title = _label(notification_panel, "", 28, GameUI.MAGENTA)
	notification_detail = _label(notification_panel, "", 22, GameUI.WHITE)
	notification_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_place_notification(-5.0)
	reward_panel = _panel("ApexBoostReward", 420.0, -172.0, -124.0, GameUI.ORANGE)
	reward_panel.anchor_top = 1.0
	reward_panel.anchor_bottom = 1.0
	reward_label = _label(reward_panel, "", 22, GameUI.ORANGE)
	_build_opponent_feed()
	_ui.hud.visibility_changed.connect(_sync_visibility)
	for overlay in [_ui.menu, _ui.pause_menu, _ui.game_over_menu, _ui.settings_menu]:
		overlay.visibility_changed.connect(_sync_visibility)
	reset_ui()


func update_race(active: bool, remaining: float, lead_m: float, boost_seconds: float, clean: bool, reward_remaining: float, required_boost_seconds: float = 4.0, countdown_remaining: float = 0.0) -> void:
	_race_active = active
	_lead_m = lead_m
	_reward_remaining = maxf(0.0, reward_remaining)
	countdown_label.text = "APEX RACE  ·  %ds" % ceili(maxf(0.0, remaining))
	if countdown_remaining > 0.0:
		countdown_label.text = "GET READY  ·  %d" % ceili(countdown_remaining)
	if absf(lead_m) < 0.5:
		lead_label.text = "SIDE BY SIDE"
	else:
		lead_label.text = "%s AHEAD  %dm" % ["YOU" if lead_m > 0.0 else "APEX", roundi(absf(lead_m))]
	lead_label.add_theme_color_override("font_color", GameUI.CYAN if lead_m >= 0.0 else GameUI.ORANGE)
	# Truncate tenths so a nearly completed target does not promise completion.
	var target := maxf(0.0, required_boost_seconds)
	var shown_boost := floorf(clampf(boost_seconds, 0.0, target) * 10.0) / 10.0
	requirements_label.text = "BOOST %.1f/%.1fs  ·  %s" % [shown_boost, target, "CLEAN" if clean else "POTHOLE HIT"]
	requirements_label.add_theme_color_override("font_color", GameUI.MUTED if clean else GameUI.ORANGE)
	reward_label.text = "APEX REWARD  ·  UNLIMITED %.1fs" % _reward_remaining
	_update_opponent_caption()
	_sync_visibility()


func show_challenge(opponent_x: float = -5.0, required_boost_seconds: float = 4.0) -> void:
	_place_notification(opponent_x)
	_notify("APEX CHALLENGES YOU", "3s countdown, then race for 30s. Finish ahead.\nBOOST TARGET: %ds during the race. Avoid potholes.\nFull tank: 3.7s. Earn close passes to refill.\nAfter countdown, hold Shift / Space to boost." % roundi(required_boost_seconds), GameUI.MAGENTA)


func update_opponent(actor: Node3D, world: World3D, road_materials: Dictionary = {}) -> void:
	_opponent = actor if is_instance_valid(actor) else null
	if _opponent != null and world != null:
		if opponent_view.world_3d != world:
			opponent_view.world_3d = world
		_bind_road_materials(road_materials)
		_update_opponent_camera()
	_sync_visibility()


func show_result(won: bool, secret: bool) -> void:
	_race_active = false
	if won:
		_notify("APEX DEFEATED", "+20,000 points  ·  10s unlimited boost\nApex: \"You earned that one.\"", GameUI.CYAN)
	elif secret:
		_notify("APEX WINS", "Apex: \"Come back when you can keep up.\"\nPOLICE CHASE  ·  Public-road racing and speeding", GameUI.ORANGE)
	else:
		_notify("APEX WINS", "Apex: \"Come back when you can keep up.\"", GameUI.MAGENTA)


func reset_ui() -> void:
	_race_active = false
	_reward_remaining = 0.0
	notification_remaining = 0.0
	_opponent = null
	_lead_m = 0.0
	_dash_phase = 0.0
	_sync_visibility()


func _process(delta: float) -> void:
	if _ui == null:
		return
	if not get_tree().paused and _playing_ui():
		notification_remaining = maxf(0.0, notification_remaining - delta)
		if _race_active and is_instance_valid(_opponent):
			_update_opponent_camera()
			if opponent_road.visible:
				_advance_feed_dashes(delta)
	_sync_visibility()


func _playing_ui() -> bool:
	return _ui.hud.visible and not (_ui.menu.visible or _ui.pause_menu.visible or _ui.game_over_menu.visible or _ui.settings_menu.visible)


func _sync_visibility() -> void:
	if _ui == null:
		return
	var playing := _playing_ui()
	race_panel.visible = playing and _race_active
	notification_panel.visible = playing and notification_remaining > 0.0
	reward_panel.visible = playing and _reward_remaining > 0.0
	opponent_panel.visible = playing and _race_active and is_instance_valid(_opponent) and _opponent.is_visible_in_tree()
	opponent_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS if opponent_panel.visible and not get_tree().paused else SubViewport.UPDATE_DISABLED
	opponent_road.visible = opponent_panel.visible and not get_tree().paused


func _build_opponent_feed() -> void:
	# One shared-world viewport watches the actual pooled actor. Encounters reuse
	# these nodes; the actor and gameplay camera are never moved by the feed.
	opponent_view = SubViewport.new()
	opponent_view.name = "ApexOpponentViewport"
	opponent_view.size = Vector2i(320, 128)
	opponent_view.own_world_3d = false
	opponent_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(opponent_view)
	opponent_camera = Camera3D.new()
	opponent_camera.name = "ApexOpponentCamera"
	opponent_camera.fov = 34.0
	opponent_camera.near = 0.1
	opponent_camera.far = 80.0
	opponent_view.add_child(opponent_camera)
	opponent_camera.current = true
	_build_feed_road()
	opponent_panel = _panel("ApexOpponentFeed", 300.0, -214.0, -24.0, GameUI.CYAN)
	opponent_panel.anchor_left = 0.0
	opponent_panel.anchor_right = 0.0
	opponent_panel.anchor_top = 1.0
	opponent_panel.anchor_bottom = 1.0
	opponent_panel.offset_left = 24.0
	opponent_panel.offset_right = 324.0
	_label(opponent_panel, "APEX  ·  LIVE", 20, GameUI.CYAN)
	opponent_image = TextureRect.new()
	opponent_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opponent_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	opponent_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	opponent_image.custom_minimum_size.y = 100.0
	opponent_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	opponent_image.texture = opponent_view.get_texture()
	opponent_panel.get_child(0).add_child(opponent_image)
	opponent_caption = _label(opponent_panel, "SIDE BY SIDE", 22, GameUI.WHITE)


func _update_opponent_caption() -> void:
	if absf(_lead_m) < 0.5:
		opponent_caption.text = "SIDE BY SIDE"
	else:
		opponent_caption.text = "%dm %s" % [roundi(absf(_lead_m)), "AHEAD" if _lead_m < 0.0 else "BEHIND"]
	opponent_caption.add_theme_color_override("font_color", GameUI.ORANGE if _lead_m < 0.0 else GameUI.CYAN)


func _update_opponent_camera() -> void:
	var at := _opponent.global_position
	opponent_road.position = Vector3(0.0, 0.0, at.z)
	opponent_camera.global_position = at + Vector3(4.2, 2.7, 8.0)
	opponent_camera.look_at(at + Vector3(0.0, 0.7, 0.0), Vector3.UP)


func _build_feed_road() -> void:
	# The actual road ring can end before a distant rival. This small visual
	# backdrop uses a feed-only layer; all its surfaces sit below real asphalt.
	# The real pooled Apex and its gap remain in the shared world unchanged.
	opponent_road = Node3D.new()
	opponent_road.name = "ApexFeedRoadBackdrop"
	opponent_view.add_child(opponent_road)
	var asphalt := _feed_material(Color("#202a40"))
	var marking := _feed_material(Color("#c7b6dd"))
	var cyan := _feed_material(Color("#2bdbe9"))
	var pink := _feed_material(Color("#e833a2"))
	opponent_road_floor = _feed_box(Vector3(0.0, -0.14, 0.0), Vector3(16.0, 0.2, 60.0), asphalt)
	for side in [-1.0, 1.0]:
		_road_cyan_edges.append(_feed_box(Vector3(side * 7.75, -0.038, 0.0), Vector3(0.13, 0.016, 60.0), cyan))
		_road_pink_edges.append(_feed_box(Vector3(side * 7.95, -0.038, 0.0), Vector3(0.10, 0.016, 60.0), pink))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.105, 0.012, 3.5)
	var dashes := MultiMesh.new()
	dashes.transform_format = MultiMesh.TRANSFORM_3D
	dashes.mesh = mesh
	dashes.instance_count = 16
	for lane in range(2):
		for dash in range(8):
			dashes.set_instance_transform(lane * 8 + dash, Transform3D(Basis.IDENTITY, Vector3(-2.5 + lane * 5.0, -0.033, -26.0 + dash * 7.0)))
	_road_marking = MultiMeshInstance3D.new()
	_road_marking.multimesh = dashes
	_road_marking.material_override = marking
	_road_marking.layers = FEED_ROAD_LAYER
	_road_marking.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	opponent_road.add_child(_road_marking)


func _advance_feed_dashes(delta: float) -> void:
	var speed := (_opponent as RoadObstacle).cruise_speed if _opponent is RoadObstacle else 0.0
	_dash_phase = fposmod(_dash_phase + maxf(0.0, speed * delta), 7.0)
	# Existing road covers these below-asphalt dashes while the rival is near.
	# Beyond the ring, their phase gives the feed a continuous driving cue.
	for lane in range(2):
		for dash in range(8):
			_road_marking.multimesh.set_instance_transform(lane * 8 + dash, Transform3D(Basis.IDENTITY, Vector3(-2.5 + lane * 5.0, -0.033, -26.0 + dash * 7.0 + _dash_phase)))


func _bind_road_materials(materials: Dictionary) -> void:
	if not materials.has("road") or opponent_road_floor.material_override == materials.road:
		return
	opponent_road_floor.material_override = materials.road
	_road_marking.material_override = materials.get("marking", _road_marking.material_override)
	for edge in _road_cyan_edges:
		edge.material_override = materials.get("cyan", edge.material_override)
	for edge in _road_pink_edges:
		edge.material_override = materials.get("pink", edge.material_override)


func _feed_box(center: Vector3, dimensions: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = center
	instance.material_override = material
	instance.layers = FEED_ROAD_LAYER
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	opponent_road.add_child(instance)
	return instance


func _feed_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _notify(title: String, detail: String, accent: Color) -> void:
	notification_title.text = title
	notification_title.add_theme_color_override("font_color", accent)
	notification_detail.text = detail
	notification_panel.add_theme_stylebox_override("panel", _ui._panel_style(Color("#101124"), Color(accent, 0.7), 1, 5, 12))
	notification_remaining = NOTIFICATION_SECONDS
	_sync_visibility()


func _place_notification(opponent_x: float) -> void:
	# Keep the rival's approach and the player's central lane unobscured.
	# Result notices retain the side chosen at the start of this encounter.
	var right_side := opponent_x <= 0.0
	notification_panel.anchor_left = 1.0 if right_side else 0.0
	notification_panel.anchor_right = notification_panel.anchor_left
	notification_panel.offset_left = -484.0 if right_side else 24.0
	notification_panel.offset_right = -24.0 if right_side else 484.0


func _panel(node_name: String, width: float, top: float, bottom: float, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _ui._panel_style(Color("#101124"), Color(accent, 0.7), 1, 5, 12))
	_ui.hud.add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -width * 0.5
	panel.offset_right = width * 0.5
	panel.offset_top = top
	panel.offset_bottom = bottom
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	return panel


func _label(panel: PanelContainer, text: String, font_size: int, color: Color) -> Label:
	var label := _ui._make_label(text, font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.get_child(0).add_child(label)
	return label
