extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.settings.effects = 0.7
	game.settings.quality = game.settings.Quality.LOW
	game._apply_settings()
	_check(root.msaa_3d == Viewport.MSAA_DISABLED and not game.world.environment.glow_enabled, "Low removes glow and edge smoothing")
	var hazard: RoadObstacle = game.obstacles._take_obstacle()
	hazard.activate(Vector3(5, 0, -70), RoadObstacle.Kind.POTHOLE)
	var collision_shape: Shape3D = hazard._collision.shape
	var world_nodes: int = game.world.get_child_count()
	for index in range(50):
		game.settings.quality = index % 3
		game._apply_settings()
		_check(game.world.get_child_count() == world_nodes and hazard.active, "quality changes retain scenery and hazards")
		_check(hazard._collision.shape == collision_shape, "quality preserves hazard collision")
	game.settings.quality = game.settings.Quality.HIGH
	game._apply_settings()
	_check(root.msaa_3d == Viewport.MSAA_2X and game.world.environment.glow_enabled, "High adds edge smoothing and retains glow")
	game.settings.effects = 0.0
	game._apply_settings()
	_check(not game.world.environment.glow_enabled, "effects off applies in High")
	game.settings.quality = game.settings.Quality.LOW
	game.settings.effects = 1.0
	game._apply_settings()
	_check(not game.world.environment.glow_enabled, "effects changes preserve Low choice")
	game.settings = load("res://scripts/game_settings.gd").new()
	game._apply_settings()
	game.return_to_menu()
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await process_frame
	game.free()
	if failures == 0:
		print("RENDER SETTINGS PASS: Low/Balanced/High, effect interactions and stable scenery/hazards")
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("RENDER SETTINGS FAIL: " + label)
