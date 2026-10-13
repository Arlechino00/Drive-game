extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var director := DifficultyDirector.new()
	var previous := 0.0
	for minutes in [0.0, 5.0, 10.0, 15.0, 20.0, 30.0, 60.0, 120.0]:
		var seconds: float = minutes * 60.0
		var actual: float = director.get_base_speed(seconds * 50.0) * 3.6
		_check(actual > previous, "cruise continues increasing at %.0f minutes (%.1f km/h)" % [minutes, actual])
		previous = actual
	_check(director.get_base_speed(900.0 * 50.0) * 3.6 > 240.0, "old 223 km/h plateau is exceeded")
	_check(director.get_base_speed(3600.0 * 50.0) * 3.6 > 400.0, "exceptional runs reach 400+ km/h")
	# Real forward/reverse swept passes at every requested extreme speed.
	var obstacle := RoadObstacle.new()
	root.add_child(obstacle)
	var contacts := [0]
	obstacle.player_hit.connect(func(): contacts[0] += 1)
	for kmh in [250.0, 300.0, 350.0, 400.0, 450.0, 600.0, 800.0, 936.8, 2000.0]:
		var speed: float = kmh / 3.6
		for direction in [-1.0, 1.0]:
			var before: int = contacts[0]
			obstacle.activate(Vector3(0, 0, -direction * 20.0), RoadObstacle.Kind.CAR, 0.0)
			obstacle.advance_pass(direction * speed * 0.5, 0.0)
			_check(contacts[0] == before + 1, "swept contact at %.0f km/h direction %d" % [kmh, direction])
		obstacle.activate(Vector3(0, 0, -20), RoadObstacle.Kind.CAR, 5.0)
		_check(not obstacle.advance_pass(speed * 0.5, 5.0), "visible lane gap is safe at %.0f km/h" % kmh)
	obstacle.free()
	print("STAGE TWO SPEED PASS" if failures == 0 else "STAGE TWO SPEED FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
