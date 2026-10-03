extends SceneTree

const Camera = preload("res://scripts/chase_camera.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var camera := Camera.new()
	root.add_child(camera)
	await process_frame
	_check((camera.cull_mask & (1 << 19)) == 0, "feed scenery is excluded from the main driving view")
	for rival_z in [-25.0, -13.0, 0.0, 12.0, 24.0]:
		camera.reset_camera()
		for tick in range(120):
			camera.follow(1.0 / 60.0, 0.0, 0.0, 80.0, true, rival_z)
		for rival_x in [-5.0, 5.0]:
			for x_offset in [-1.4, 1.4]:
				for z_offset in [-2.4, 2.4]:
					var corner := Vector3(rival_x + x_offset, 0.8, rival_z + z_offset)
					_check(not camera.is_position_behind(corner), "nearby Apex remains in front of the race camera")
					_check(Rect2(Vector2.ZERO, Vector2(root.size)).has_point(camera.unproject_position(corner)), "whole nearby rival fits main view at z %.0f" % rival_z)
		_check(Rect2(Vector2.ZERO, Vector2(root.size)).has_point(camera.unproject_position(Vector3(0, 1, 0))), "race framing keeps the player visible")
	for player_x in [-5.0, 5.0]:
		for rival_z in [-13.0, 0.0, 24.0]:
			camera.reset_camera()
			for tick in range(180):
				camera.follow(1.0 / 60.0, player_x, 0, 27, false, rival_z)
			for rival_x in [-5.0, 5.0]:
				_check(Rect2(Vector2.ZERO, Vector2(root.size)).has_point(camera.unproject_position(Vector3(rival_x, 1, rival_z))), "slowed driver in either outer lane still sees nearby Apex")
	for tick in range(120):
		camera.follow(1.0 / 60.0, 0, 0, 80, true, 200.0)
	_check(camera.position.z < 14.1, "far rival releases main camera for ordinary steering")
	for tick in range(180):
		camera.follow(1.0 / 60.0, 0, 0, 62, false)
	_check(absf(camera.position.z - 12.8) < 0.01, "camera returns to ordinary driving after the race")
	camera.free()
	if failures == 0:
		print("APEX VISIBILITY PASS: complete nearby rival framing ahead/alongside/behind, player readability, bounded far-rival pullback and ordinary camera recovery")
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("APEX VISIBILITY FAIL: " + label)
