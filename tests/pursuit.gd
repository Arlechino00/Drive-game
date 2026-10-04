extends SceneTree

var failures: int = 0
var caught_count: int = 0
var escaped_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists("res://scripts/police_pursuit.gd"):
		_check(false, "pursuit subsystem exists")
		quit(1)
		return
	var script = load("res://scripts/police_pursuit.gd")
	if script == null:
		quit(1)
		return
	var pursuit = script.new()
	root.add_child(pursuit)
	await process_frame
	pursuit.caught.connect(func(): caught_count += 1)
	pursuit.escaped.connect(func(): escaped_count += 1)
	var viewport: SubViewport = pursuit.get_node("RearView")
	var camera: Camera3D = viewport.get_camera_3d()
	var visual: Node3D = pursuit.get_node("PoliceVisual/PoliceCar")
	var initial_count := _node_count(pursuit)
	var texture: Texture2D = pursuit.get_rearview_texture()
	_check(not pursuit.active and not pursuit.visible, "inactive pursuit starts hidden")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "inactive rear view consumes no rendered frames")
	_check(_physics_node_count(pursuit) == 0, "pursuit police cannot collide with gameplay")
	_check(texture != null and texture.get_width() == 384 and texture.get_height() == 160, "rear view has a usable bounded texture")
	_check(not pursuit.is_processing() and not pursuit.is_physics_processing(), "game owns pursuit timing explicitly")

	# A lost grace cap would make the first strong collision unavoidable.
	for base_speed in [45.0, 62.0]:
		for loss in [18.0, 30.0]:
			pursuit.begin(Vector3.ZERO)
			var previous_catches := caught_count
			var minimum_gap: float = pursuit.gap_m
			for frame in range(4 * 60):
				var recover_time := float(frame) / 60.0
				var speed: float = base_speed - loss * (1.0 - recover_time / 4.0)
				pursuit.advance(1.0 / 60.0, Vector3.ZERO, speed, base_speed)
				minimum_gap = minf(minimum_gap, pursuit.gap_m)
			_check(pursuit.active and caught_count == previous_catches, "clean first-hit recovery survives %.0f m/s loss at %.0f m/s cruise" % [loss, base_speed])
			_check(minimum_gap >= 35.0, "initial recovery retains steering time at %.0f/%.0f" % [base_speed, loss])
			var before_escape := escaped_count
			for frame in range(14 * 60):
				pursuit.advance(1.0 / 60.0, Vector3.ZERO, base_speed, base_speed)
			await process_frame
			_check(not pursuit.active and escaped_count == before_escape + 1, "clean recovery eventually escapes at %.0f/%.0f" % [base_speed, loss])

	# Modest damaged speed holds the gap below the distance escape boundary,
	# proving that clean driving itself releases the player after sixteen seconds.
	pursuit.begin(Vector3.ZERO)
	var clean_escape_before := escaped_count
	for frame in range(15 * 60):
		pursuit.advance(1.0 / 60.0, Vector3.ZERO, 42.0, 45.0)
	_check(pursuit.active and pursuit.gap_m < 100.0, "clean-time route waits before sixteen seconds")
	for frame in range(61):
		pursuit.advance(1.0 / 60.0, Vector3.ZERO, 42.0, 45.0)
	await process_frame
	_check(not pursuit.active and escaped_count == clean_escape_before + 1 and pursuit.clean_seconds >= 16.0, "sixteen clean seconds escape without reaching distance boundary")
	pursuit.advance(10.0, Vector3.ZERO, 90.0, 45.0)
	_check(escaped_count == clean_escape_before + 1, "escaped signal only emits once")

	# Earned, finite charge with the game's +18 m/s boost gain can buy distance
	# after surviving initial damage; normal speed alone cannot do that as early.
	var Progress = load("res://scripts/run_progress.gd")
	for base_speed in [45.0, 62.0]:
		pursuit.begin(Vector3.ZERO)
		for frame in range(4 * 60):
			pursuit.advance(1.0 / 60.0, Vector3.ZERO, base_speed - 30.0 * (1.0 - float(frame) / 240.0), base_speed)
		var fuel = Progress.new()
		fuel.reset(false)
		fuel.boost_charge = 0.8
		var boosted_escape_before := escaped_count
		for frame in range(5 * 60):
			if not pursuit.active:
				break
			var boosting: bool = fuel.update_boost(true, 1.0 / 60.0)
			var boosted_speed: float = minf(80.0, base_speed + (18.0 if boosting else 0.0))
			pursuit.advance(1.0 / 60.0, Vector3.ZERO, boosted_speed, base_speed)
		await process_frame
		_check(not pursuit.active and escaped_count == boosted_escape_before + 1 and pursuit.clean_seconds < 10.0 and pursuit.gap_m >= 100.0, "finite boost escapes through measured gap at %.0f m/s cruise" % base_speed)
		_check(fuel.boost_charge >= 0.0 and fuel.boost_charge < 0.8 and not fuel.infinite_boost, "distance escape consumes only finite available fuel")

	# Sustained damage without a clean interval loses; grace cannot renew on hits.
	for base_speed in [45.0, 62.0]:
		pursuit.begin(Vector3.ZERO)
		for frame in range(4 * 60):
			pursuit.advance(1.0 / 60.0, Vector3.ZERO, base_speed - 30.0 * (1.0 - float(frame) / 240.0), base_speed)
		var catch_before := caught_count
		var gap_before: float = pursuit.gap_m
		pursuit.register_mistake()
		_check(pursuit.clean_seconds == 0.0 and pursuit.gap_m < gap_before, "repeat impact resets clean progress and closes gap")
		for frame in range(4 * 60):
			pursuit.advance(1.0 / 60.0, Vector3.ZERO, base_speed - 30.0 * (1.0 - float(frame) / 240.0), base_speed)
		_check(not pursuit.active and caught_count == catch_before + 1, "second strong hit can be caught at %.0f m/s cruise" % base_speed)
		pursuit.register_mistake()
		pursuit.register_close_call()
		pursuit.advance(5.0, Vector3.ZERO, 0.0, base_speed)
		_check(caught_count == catch_before + 1, "caught signal only emits once")

	pursuit.begin(Vector3.ZERO)
	pursuit.advance(5.0, Vector3.ZERO, 45.0, 45.0)
	var close_gap: float = pursuit.gap_m
	pursuit.register_close_call()
	_check(pursuit.active and pursuit.clean_seconds == 0.0 and pursuit.gap_m < close_gap, "a close pass resets the clean escape route and costs distance")
	for frame in range(15 * 60):
		pursuit.advance(1.0 / 60.0, Vector3.ZERO, 42.0, 45.0)
	_check(pursuit.active and pursuit.clean_seconds < 16.0, "close pass requires a new full clean interval")

	# Exact public thresholds, including a capture caused by an immediate hit.
	pursuit.begin(Vector3.ZERO)
	pursuit.gap_m = 7.0
	var boundary_catches := caught_count
	pursuit.advance(0.01, Vector3.ZERO, 45.0, 45.0)
	_check(not pursuit.active and caught_count == boundary_catches + 1, "seven metre boundary catches")
	pursuit.begin(Vector3.ZERO)
	pursuit.gap_m = 12.0
	pursuit.register_mistake()
	_check(not pursuit.active and caught_count == boundary_catches + 2, "repeat hit below capture boundary catches immediately")
	pursuit.begin(Vector3.ZERO)
	pursuit.gap_m = 100.0
	var boundary_escapes := escaped_count
	pursuit.advance(0.01, Vector3.ZERO, 45.0, 45.0)
	await process_frame
	_check(not pursuit.active and escaped_count == boundary_escapes + 1, "hundred metre boundary escapes")

	# Shared-world rear view follows actual coordinates and looks at the police.
	var player_at := Vector3(6.2, 0.0, -12.0)
	pursuit.begin(player_at)
	_check(viewport.world_3d == pursuit.get_world_3d(), "rear view shares the actual road world")
	_check(viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED, "active chase enables rear view rendering")
	_check(visual.visible and visual.global_position.z > player_at.z + 50.0, "police visual begins behind the player")
	_check(-camera.global_basis.z.dot(Vector3.BACK) > 0.9, "rear camera faces behind the forward-driving player")
	_check(not camera.is_position_behind(visual.global_position + Vector3.UP), "actual police is in front of rear camera")
	var projected := camera.unproject_position(visual.global_position + Vector3.UP) / Vector2(viewport.size)
	_check(projected.x > 0.0 and projected.x < 1.0 and projected.y > 0.0 and projected.y < 1.0, "actual police is inside rear display")
	var front_left := camera.unproject_position(visual.global_position + Vector3(-1.5, 1.0, -3.0))
	var front_right := camera.unproject_position(visual.global_position + Vector3(1.5, 1.0, -3.0))
	_check(absf(front_right.x - front_left.x) >= 65.0, "zoom keeps distant police readable in the small mirror")
	_check(not pursuit.get_node("PoliceVisual/StoppedTraffic").visible, "pursuit never shows aftermath wreck traffic")
	var still_gap: float = pursuit.gap_m
	var still_clean: float = pursuit.clean_seconds
	var still_position := visual.global_position
	for frame in range(10):
		await process_frame
	_check(pursuit.gap_m == still_gap and pursuit.clean_seconds == still_clean and visual.global_position == still_position, "pause is deterministic when root does not advance")
	pursuit.advance(-1.0, player_at, 0.0, 45.0)
	_check(pursuit.gap_m == still_gap and pursuit.clean_seconds == still_clean, "negative delta cannot advance time")
	pursuit.advance(0.13, player_at, 45.0, 45.0, 0.0)
	var blue_material := (visual.get_node("BlueBeacon") as MeshInstance3D).material_override as StandardMaterial3D
	var red_material := (visual.get_node("RedBeacon") as MeshInstance3D).material_override as StandardMaterial3D
	var steady_blue := blue_material.emission_energy_multiplier
	var steady_red := red_material.emission_energy_multiplier
	pursuit.advance(0.16, player_at, 45.0, 45.0, 0.0)
	_check(blue_material.emission_energy_multiplier == steady_blue and red_material.emission_energy_multiplier == steady_red, "effects off leaves steady police beacons")
	_check((visual.get_node("BlueLight") as OmniLight3D).light_energy == 0.0 and (visual.get_node("RedLight") as OmniLight3D).light_energy == 0.0, "effects off disables flashing light sources")
	pursuit.reset_pursuit()
	_check(not pursuit.active and pursuit.gap_m == 0.0 and pursuit.clean_seconds == 0.0 and not pursuit.visible, "reset clears all pursuit state")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and not visual.visible, "reset disables rendering and police")

	for cycle in range(200):
		player_at = Vector3(-6.2 if cycle % 2 == 0 else 6.2, 0.0, float(cycle))
		pursuit.begin(player_at)
		_check(pursuit.gap_m >= 55.0 and pursuit.gap_m <= 70.0 and pursuit.clean_seconds == 0.0, "restart restores safe initial gap and clean progress")
		pursuit.advance(0.5, player_at, 15.0, 45.0)
		_check(pursuit.active and absf(visual.global_position.x) <= 6.15, "reused police stays on the road and initial grace survives")
		pursuit.reset_pursuit()
		pursuit.advance(1.0, player_at, 0.0, 45.0)
		_check(not pursuit.active and pursuit.gap_m == 0.0, "inactive advance cannot restart pursuit")
	_check(_node_count(pursuit) == initial_count and initial_count <= 160, "two hundred reuses retain fixed bounded nodes")
	_check(pursuit.get_rearview_texture() == texture, "restarts retain the same rear view texture")
	_check(_physics_node_count(pursuit) == 0, "repeated starts never create physics actors")
	await _test_deferred_contacts(pursuit)
	pursuit.free()
	await process_frame
	if failures == 0:
		print("PURSUIT PASS: first-hit recovery at 45/62 m/s, clean/gap escapes, repeat-hit capture, close-call reset, thresholds, pause, effects-off, actual rear camera and 200 bounded reuses (%s nodes)" % initial_count)
	quit(1 if failures else 0)


func _test_deferred_contacts(pursuit: PolicePursuit) -> void:
	var pass_actor := RoadObstacle.new()
	root.add_child(pass_actor)
	pass_actor.near_miss.connect(func(_points: int, _clearance: float): pursuit.register_close_call())
	for route in ["clean", "distance"]:
		for contact in ["close", "mistake"]:
			pursuit.begin(Vector3.ZERO)
			pursuit.gap_m = 60.0 if route == "clean" else 99.99
			pursuit.clean_seconds = 15.999 if route == "clean" else 4.0
			var before := escaped_count
			# The pass completion is queued before pursuit advancement, exactly
			# as game -> spawner -> obstacle ordering does on the contact frame.
			if contact == "close":
				pass_actor.activate(Vector3(2.85, 0, -4), RoadObstacle.Kind.CAR, 0.0)
				pass_actor.advance_pass(10.0, 0.0)
			else:
				pursuit.register_mistake.call_deferred()
			pursuit.advance(1.0 / 60.0, Vector3.ZERO, 80.0, 62.0)
			_check(pursuit.active and escaped_count == before, "escape remains provisional until %s %s result" % [route, contact])
			await process_frame
			_check(pursuit.active and escaped_count == before and pursuit.clean_seconds == 0.0 and pursuit.gap_m < 100.0, "%s %s prevents premature escape" % [route, contact])
			_check(contact != "close" or pass_actor.pass_awarded, "near pass is resolved through the real deferred obstacle path")
	# Real Area contact cancels its queued near pass and still captures immediately.
	pursuit.begin(Vector3.ZERO)
	pursuit.gap_m = 12.0
	var catches := caught_count
	pass_actor.activate(Vector3(2.85, 0, -4), RoadObstacle.Kind.CAR, 0.0)
	pass_actor.advance_pass(10.0, 0.0)
	pass_actor.player_hit.connect(pursuit.register_mistake)
	pass_actor._resolve_player_contact()
	_check(not pursuit.active and caught_count == catches + 1, "capture remains synchronous")
	await process_frame
	_check(not pass_actor.pass_awarded, "queued Area contact cancels near-pass award")
	for restart in [false, true]:
		pursuit.begin(Vector3.ZERO)
		pursuit.gap_m = 100.0
		var escapes := escaped_count
		pursuit.advance(0.01, Vector3.ZERO, 62.0, 62.0)
		pursuit.reset_pursuit()
		if restart:
			pursuit.begin(Vector3.ZERO)
			# Even if the new chase also meets a boundary, only its own queued
			# callback may resolve it. The old generation cannot touch it.
			pursuit.clean_seconds = 16.0
		await process_frame
		_check(escaped_count == escapes and pursuit.active == restart, "stale escape callback cannot resolve reset or restarted chase")
	pass_actor.free()
	pursuit.reset_pursuit()


func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func _physics_node_count(node: Node) -> int:
	var count := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		count += _physics_node_count(child)
	return count


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("PURSUIT FAIL: " + label)
