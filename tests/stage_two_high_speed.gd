extends SceneTree
## The finite preview must keep generating real encounters at rising speeds.

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var road := RoadManager.new()
	root.add_child(road)
	var road_nodes := road.get_child_count()
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	var camera := ChaseCamera.new()
	root.add_child(camera)
	# 936.8 is 800 km/h cruise plus the real 38 m/s Boost gain. The final
	# case exceeds the old minimum-spawn-distance budget of a 2400 m preview.
	for kmh in [450.0, 600.0, 800.0, 936.8, 2000.0, 7100.0, 8000.0]:
		var speed: float = kmh / 3.6
		var distance := 0.0
		var active_final_half := 0
		spawner.reset_spawner(771)
		road.reset_road()
		for tick in range(600):
			distance += speed * 0.1
			spawner.configure_progression(speed, 2400.0 + tick * 0.1)
			spawner.set_speed_limit(200)
			spawner.advance(speed * 0.1, distance, 0.7, 0.1, 20.0)
			road.advance(speed * 0.1)
			if tick >= 300 and spawner.get_active_count() > 0:
				active_final_half += 1
			_check(spawner.obstacle_pool.size() <= 20, "finite traffic pool at %.1f km/h" % kmh)
			if tick % 30 == 0:
				var endpoints: Array[float] = []
				for segment in road.segments:
					endpoints.append(segment.position.z)
				endpoints.sort()
				_check(endpoints[0] - 40.0 < -spawner.spawn_ahead - 96.0, "road under full traffic preview at %.1f km/h" % kmh)
				for index in range(1, endpoints.size()):
					_check(absf(endpoints[index] - endpoints[index - 1] - 40.0) < 0.001, "continuous road at %.1f km/h" % kmh)
		_check(active_final_half > 0, "traffic continues after startup at %.1f km/h" % kmh)
		_check(road.get_child_count() == road_nodes, "finite road nodes at %.1f km/h" % kmh)
		camera.follow(0.1, 0.0, 0.0, speed, false)
		_check(camera.far >= spawner.spawn_ahead + 40.0, "camera shows actual traffic preview at %.1f km/h" % kmh)
		print("HIGH SPEED %.1f km/h preview %.1f m active final-half ticks %d pool %d" % [kmh, spawner.spawn_ahead, active_final_half, spawner.obstacle_pool.size()])
	camera.free()
	spawner.free()
	road.free()
	print("STAGE TWO HIGH SPEED PASS" if failures == 0 else "STAGE TWO HIGH SPEED FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		if failures <= 12:
			push_error(label)
