extends SceneTree

const Car = preload("res://scripts/player_car.gd")
const Traffic = preload("res://scripts/obstacle.gd")
const Models = preload("res://scripts/traffic_models.gd")
var failures: int = 0
var hits: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Parking exactly on either divider must not fit beside an occupied lane.
	for divider in [-2.5, 2.5]:
		for lane in ([ -5.0, 0.0 ] if divider < 0.0 else [ 0.0, 5.0 ]):
			# A narrow motorcycle legitimately leaves room at a divider.
			for model in range(Models.Model.MOTO):
				await _contact_case(divider, lane, Models.kind_for_model(model), true, model)
	# Centered driving in an open lane must remain safe, even beside wide traffic.
	for lane in [-5.0, 0.0, 5.0]:
		var occupied_lane := 0.0 if lane != 0.0 else 5.0
		for model in range(Models.COUNT):
			await _contact_case(lane, occupied_lane, Models.kind_for_model(model), false, model)
	await _alternating_escape_lanes()
	if failures == 0:
		print("HANDLING PASS: all ten widths collide at dividers and preserve open lanes; 12 alternating wide-pickup escape rows at 80 m/s with real steering")
	quit(1 if failures else 0)


func _contact_case(player_x: float, traffic_x: float, kind: int, expect_hit: bool, model: int = -1) -> void:
	var player := Car.new()
	root.add_child(player)
	player.position.x = player_x
	var traffic := Traffic.new()
	root.add_child(traffic)
	traffic.player_hit.connect(func() -> void: hits += 1)
	var before := hits
	traffic.activate(Vector3(traffic_x, 0.0, 0.0), kind, player_x, model)
	for frame in range(4):
		await physics_frame
	var collided := hits > before
	_check(collided == expect_hit, "x=%.1f beside traffic x=%.1f model=%d: collision=%s" % [player_x, traffic_x, model, expect_hit])
	player.free()
	traffic.free()
	await physics_frame


func _alternating_escape_lanes() -> void:
	var player := Car.new()
	root.add_child(player)
	player.position.x = -5.0
	player.active = true
	var rows: Array[Array] = []
	var before := hits
	for row_index in range(12):
		var safe_x := -5.0 if row_index % 2 == 0 else 0.0
		var row: Array = []
		for lane in [-5.0, 0.0, 5.0]:
			if lane == safe_x:
				continue
			var traffic := Traffic.new()
			root.add_child(traffic)
			traffic.player_hit.connect(func() -> void: hits += 1)
			traffic.activate(Vector3(lane, 0.0, -90.0 - row_index * 64.0), Models.kind_for_model(Models.Model.HAULER), player.position.x, Models.Model.HAULER)
			row.append(traffic)
		rows.append(row)
	var next_row := 0
	for frame in range(900):
		while next_row < rows.size() and rows[next_row][0].position.z > 5.5:
			next_row += 1
		var target_x := player.position.x
		if next_row < rows.size():
			target_x = -5.0 if next_row % 2 == 0 else 0.0
		var difference: float = target_x - player.position.x
		var velocity: float = player.lateral_velocity
		var braking := velocity * velocity / (2.0 * player.steering_release)
		var direction := 0
		if absf(difference) > braking + 0.07 or velocity * difference < 0.0:
			direction = 1 if difference > 0.0 else -1
		_key(KEY_A, direction < 0)
		_key(KEY_D, direction > 0)
		await physics_frame
		await process_frame
		for row in rows:
			for traffic in row:
				traffic.advance_pass(66.0 / 60.0, player.position.x)
		if hits != before:
			break
	_key(KEY_A, false)
	_key(KEY_D, false)
	_check(hits == before and next_row == rows.size(), "alternating paired wide pickups remain avoidable at maximum boost")
	for row in rows:
		for traffic in row:
			traffic.free()
	player.free()
	await physics_frame


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("HANDLING FAIL: " + label)
