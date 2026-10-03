extends SceneTree

const Obstacle = preload("res://scripts/obstacle.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	# Close model-review views use the actual car, road, and game lighting.
	# This only changes the test window/camera, never project settings.
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	# Freeze the chase update while inspecting the authored geometry.
	game.set_process(false)
	game.ui.show_playing()
	game.ui.hud.visible = false
	game.camera.fov = 48.0
	game.camera.position = Vector3(5.2, 3.3, 6.6)
	game.camera.look_at(Vector3(0, 0.75, 0))
	await _save_frame("res://tests/car_rear.png", game.camera)
	game.camera.position = Vector3(5.2, 3.3, -6.6)
	game.camera.look_at(Vector3(0, 0.75, 0))
	await _save_frame("res://tests/car_front.png", game.camera)
	game.player.visible = false
	# Hidden Area3D nodes still collide; move the hero clear of the lineup.
	game.player.position.y = -100.0
	var lineup: Array[Node3D] = []
	for kind in [Obstacle.Kind.CAR, Obstacle.Kind.VAN, Obstacle.Kind.WIDE]:
		var traffic := Obstacle.new()
		game.add_child(traffic)
		traffic.activate(Vector3((kind - 2) * 3.5, 0, -2.5), kind)
		lineup.append(traffic)
	var lineup_bounds := AABB(Vector3(-4.52, 0.05, -5.03), Vector3(9.44, 2.03, 5.06))
	game.camera.position = Vector3(8.0, 5.2, 10.0)
	game.camera.look_at(Vector3(0, 0.9, -2.5))
	await _save_frame("res://tests/traffic_rear.png", game.camera, lineup_bounds)
	game.camera.position = Vector3(8.0, 5.2, -15.0)
	game.camera.look_at(Vector3(0, 0.9, -2.5))
	await _save_frame("res://tests/traffic_front.png", game.camera, lineup_bounds)
	for traffic in lineup:
		if not traffic.visible or not traffic.active:
			failures += 1
			push_error("CAR CAPTURE FAIL: traffic missing from lineup")
	game.audio.stop_all()
	await create_timer(0.12).timeout
	game.free()
	await process_frame
	if failures == 0:
		print("CAR CAPTURE PASS: actual hero/logo and three traffic silhouettes, framed front/rear views")
	quit(1 if failures else 0)


func _save_frame(path: String, camera: Camera3D, bounds: AABB = AABB(Vector3(-1.65, 0.15, -3), Vector3(3.3, 1.5, 6))) -> void:
	var review_pose := camera.transform
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	if not camera.transform.is_equal_approx(review_pose):
		failures += 1
		push_error("CAR CAPTURE FAIL: chase update changed the review camera")
	var frame := Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(-32.0)
	for corner in range(8):
		var point := bounds.get_endpoint(corner)
		if camera.is_position_behind(point) or not frame.has_point(camera.unproject_position(point)):
			failures += 1
			push_error("CAR CAPTURE FAIL: model outside review frame")
	var result := root.get_texture().get_image().save_png(path)
	if result != OK:
		failures += 1
		push_error("CAR CAPTURE FAIL: %s (%s)" % [path, result])
