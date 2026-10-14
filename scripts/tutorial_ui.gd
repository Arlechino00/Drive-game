extends Node
## Learn by driving. Practice outcomes stay out of normal records.
const L = preload("res://scripts/localization.gd")
const STANDARD := ["steer", "brake", "boost", "traffic", "radar", "finish"]
const SECRET := ["steer", "boost", "capture", "escape", "finish"]
const LIVE := ["steer", "brake", "boost", "finish"]
var active := false
var practice := false
var secret_guide := false
var step := 0
var panel: PanelContainer
var caption: Label
var hint: Label
var skip_button: Button
var target_marker: Label
var _game: Node
var _elapsed := 0.0
var _action_time := 0.0
var _origin_x := 0.0
var _left_done := false
var _right_done := false
var _traffic: RoadObstacle
var _retry_pending := false
var _saved_spawning := true

func attach(ui: GameUI, _community: CommunityUI) -> void:
	_game = get_parent()
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "LiveTutorial"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.hud.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 24
	panel.offset_right = 424
	panel.offset_top = 180
	panel.add_theme_stylebox_override("panel", ui._panel_style(Color("#101124"), GameUI.CYAN, 2, 6, 16))
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	caption = ui._make_label("", 27, GameUI.CYAN)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(caption)
	hint = ui._make_label("", 23, GameUI.WHITE)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	skip_button = ui._make_button(L.text("coach.skip"))
	skip_button.pressed.connect(finish)
	column.add_child(skip_button)
	target_marker = ui._make_label("▼", 50, GameUI.CYAN)
	target_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.hud.add_child(target_marker)
	ui.tutorial_pressed.connect(func() -> void: request(ui._mode == 2))
	ui.language_changed.connect(_refresh)
	cancel()

func request(secret: bool = false) -> void:
	_game.request_live_tutorial(secret)

func begin(practice_run: bool = true) -> void:
	practice = practice_run
	secret_guide = _game.run_mode == _game.GameMode.SECRET
	active = true
	step = 0
	_saved_spawning = _game.obstacles.spawning_enabled
	_left_done = false
	_right_done = false
	_origin_x = 0.0
	if practice:
		_game.obstacles.spawning_enabled = false
		for actor in _game.obstacles.obstacle_pool:
			actor.deactivate()
		_game.enforcement.sector_at = INF
		_game.enforcement.radar_at = INF
		_game.enforcement.sector_end = INF
		_game.enforcement.radar_pending = false
		_game.speed = 33.0
	_enter_step()
	var owner := get_viewport().gui_get_focus_owner()
	if owner:
		owner.release_focus()

func cancel() -> void:
	if active and practice:
		_game.obstacles.spawning_enabled = _saved_spawning
	active = false
	practice = false
	_traffic = null
	_retry_pending = false
	panel.visible = false
	target_marker.visible = false

func finish() -> void:
	if not active:
		return
	var was_practice := practice
	var snapshot := capture_handoff() if was_practice else {}
	cancel()
	if was_practice:
		if _game.has_method("complete_tutorial_handoff"):
			_game.complete_tutorial_handoff(snapshot)
		else:
			_game.start_game(false)
			restore_handoff(snapshot)

func capture_handoff() -> Dictionary:
	var wheels: Array[Vector3] = []
	for wheel in _game.player.front_wheels:
		wheels.append(wheel.rotation)
	var road_chunks := []
	for segment in _game.road.segments:
		road_chunks.append([segment.transform, segment.chunk_index])
	return {"car": _game.player.transform, "visual": _game.player.visual.transform,
		"velocity": _game.player.lateral_velocity, "wheels": wheels,
		"camera": _game.camera.transform, "fov": _game.camera.fov, "far": _game.camera.far,
		"follow_x": _game.camera.follow_x, "lean": _game.camera.lean, "elapsed": _game.camera.elapsed,
		"road_phase": _game.road._road_phase, "road_cycles": _game.road._road_cycles, "road_chunks": road_chunks}

func restore_handoff(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_game.player.transform = snapshot.car
	_game.player.visual.transform = snapshot.visual
	_game.player.lateral_velocity = snapshot.velocity
	for index in range(_game.player.front_wheels.size()):
		_game.player.front_wheels[index].rotation = snapshot.wheels[index]
	_game.camera.transform = snapshot.camera
	_game.camera.fov = snapshot.fov
	_game.camera.far = snapshot.far
	_game.camera.follow_x = snapshot.follow_x
	_game.camera.lean = snapshot.lean
	_game.camera.elapsed = snapshot.elapsed
	_game.road._road_phase = snapshot.road_phase
	_game.road._road_cycles = snapshot.road_cycles
	for index in range(_game.road.segments.size()):
		var segment: Node3D = _game.road.segments[index]
		segment.transform = snapshot.road_chunks[index][0]
		segment.configure(snapshot.road_chunks[index][1], _game.road.CHUNKS_PER_SECTION)

func current_step() -> String:
	return (LIVE if not practice else (SECRET if secret_guide else STANDARD))[step]

func retry() -> void:
	if active and practice:
		if secret_guide and current_step() == "escape":
			step = SECRET.find("capture")
		_retry_pending = true

func on_escape() -> void:
	if active and practice and current_step() == "escape":
		_next()

func advance(delta: float) -> void:
	if not active or _game.state != _game.GameState.PLAYING:
		return
	_elapsed += delta
	if _retry_pending:
		_retry_pending = false
		_enter_step()
	var phase := current_step()
	var x: float = _game.player.position.x
	match phase:
		"steer":
			_left_done = _left_done or x < _origin_x - 1.0
			_right_done = _right_done or x > _origin_x + 1.0
			if _left_done and _right_done:
				_next()
		"brake":
			if _game.braking:
				_action_time += delta
			if _action_time >= 0.3 and _game.speed < 25.0:
				_next()
		"boost":
			if _game.progress.boosting:
				_action_time += delta
			if _action_time >= 0.35:
				_next()
		"traffic":
			if not practice:
				if _elapsed >= 3.0:
					_next()
			elif is_instance_valid(_traffic):
				if _traffic.pass_collided:
					retry()
				elif _traffic.position.z > 8.0:
					_next()
		"radar":
			if not practice and _elapsed >= 3.0:
				_next()
		"capture":
			if practice:
				_game.pursuit.capture_fraction = minf(0.6, _game.pursuit.capture_fraction)
			if _elapsed >= 2.0 and absf(x - _origin_x) > 1.0:
				_next()
		"escape":
			if not practice and _elapsed >= 3.0:
				_next()
		"finish":
			if _elapsed >= 0.85:
				finish()
	if active:
		_update_marker()

func radar_checked(event: Dictionary) -> void:
	if not active or not practice or current_step() != "radar" or not event.get("checked", false):
		return
	if int(event.get("fine", 0)) > 0:
		_game.enforcement.fine_points = 0
		retry()
	else:
		_next()

func _next() -> void:
	step += 1
	_enter_step()
	_game.audio.play_cue("ui")

func _enter_step() -> void:
	_elapsed = 0.0
	_action_time = 0.0
	_origin_x = _game.player.position.x
	_traffic = null
	var phase := current_step()
	if phase == "steer":
		_origin_x = 0.0
	if practice:
		for actor in _game.obstacles.obstacle_pool:
			actor.deactivate()
		if phase == "boost":
			_game.progress.boost_charge = 1.0
		if phase == "traffic":
			_traffic = _game.obstacles._take_obstacle()
			var lane := clampf(roundf(_origin_x / 5.0) * 5.0, -5.0, 5.0)
			_traffic.activate(Vector3(lane, 0, -75), RoadObstacle.Kind.CAR, _origin_x)
			_game.obstacles.traffic_speed = 10.0
			_game.obstacles._target_traffic_speed = 10.0
		if phase == "radar":
			_game.enforcement.current_limit = 80
			_game.enforcement.next_limit = 80
			_game.enforcement.radar_at = _game.distance + 110.0
			_game.enforcement.radar_pending = true
		if phase == "capture":
			_game.pursuit.set_heat(0)
			_game.pursuit.begin(_game.player.position)
			_game.pursuit.gap_m = 6.0
			_game.pursuit.units[0].speed = _game.speed
		if phase == "escape":
			_game.pursuit.training_escape = true
	_refresh()

func _refresh() -> void:
	if not active:
		return
	panel.visible = true
	caption.text = L.text("coach." + current_step())
	var control := ""
	if current_step() == "steer":
		control = "steer"
	elif current_step() in ["brake", "radar"]:
		control = "brake"
	elif current_step() == "boost":
		control = "boost"
	if not control.is_empty():
		hint.text = L.text("coach." + control + (".mobile" if _game.mobile_mode else ".controls"))
	elif current_step() == "finish":
		hint.text = L.text("coach.secret_done" if secret_guide else "coach.team")
	else:
		hint.text = L.text("coach." + current_step() + ".hint")
	skip_button.text = L.text("coach.skip_mobile" if _game.mobile_mode else "coach.skip")

func _update_marker() -> void:
	target_marker.visible = false
	if current_step() == "traffic" and is_instance_valid(_traffic) and _traffic.active:
		var world: Vector3 = _traffic.global_position + Vector3(0, 2.5, 0)
		if not _game.camera.is_position_behind(world):
			var point: Vector2 = _game.ui.hud.get_global_transform().affine_inverse() * _game.camera.unproject_position(world)
			target_marker.position = point - Vector2(25, 45)
			target_marker.visible = true

func _unhandled_input(event: InputEvent) -> void:
	var accept := event is InputEventJoypadButton and event.is_action_pressed("ui_accept")
	var enter: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if active and _game.state == _game.GameState.PLAYING and (accept or enter):
		finish()
		get_viewport().set_input_as_handled()
