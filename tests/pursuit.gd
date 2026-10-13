extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var pursuit = load("res://scripts/police_pursuit.gd").new()
	root.add_child(pursuit)
	await process_frame
	var viewport: SubViewport = pursuit.get_node("RearView")
	var camera: Camera3D = viewport.get_camera_3d()
	var visual: Node3D = pursuit.get_node("PoliceVisual/PoliceCar")
	var texture: Texture2D = pursuit.get_rearview_texture()
	_check(not pursuit.active and not pursuit.visible, "inactive pursuit starts hidden")
	_check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "inactive mirror rendering disabled")
	_check(_physics_count(pursuit) == 0, "police uses controlled contact without instant Area arrests")
	_check(texture != null and texture.get_width() == 384 and texture.get_height() == 160, "bounded mirror texture")
	var at := Vector3(6.2, 0.0, -12.0)
	pursuit.begin(at)
	_check(viewport.world_3d == pursuit.get_world_3d(), "mirror shares real road world")
	_check(visual.visible and visual.global_position.z > at.z + 50.0, "police begins behind driver")
	_check(-camera.global_basis.z.dot(Vector3.BACK) > 0.9, "mirror faces behind driver")
	_check(not camera.is_position_behind(visual.global_position + Vector3.UP), "actual police is visible to rear camera")
	var projected := camera.unproject_position(visual.global_position + Vector3.UP) / Vector2(viewport.size)
	_check(projected.x > 0.0 and projected.x < 1.0 and projected.y > 0.0 and projected.y < 1.0, "police projects inside mirror")
	_check(not pursuit.get_node("PoliceVisual/StoppedTraffic").visible, "aftermath traffic stays hidden")
	var gap: float = pursuit.gap_m
	var position := visual.global_position
	await process_frame
	_check(pursuit.gap_m == gap and visual.global_position == position, "pause does not advance police")
	pursuit.advance(-1.0, at, 0.0, 45.0)
	_check(pursuit.gap_m == gap, "negative delta cannot advance chase")
	pursuit.advance(0.13, at, 45.0, 45.0, 0.0)
	var blue := (visual.get_node("BlueBeacon") as MeshInstance3D).material_override as StandardMaterial3D
	var red := (visual.get_node("RedBeacon") as MeshInstance3D).material_override as StandardMaterial3D
	var energies := Vector2(blue.emission_energy_multiplier, red.emission_energy_multiplier)
	pursuit.advance(0.16, at, 45.0, 45.0, 0.0)
	_check(energies == Vector2(blue.emission_energy_multiplier, red.emission_energy_multiplier), "effects off keeps steady beacon material")
	_check((visual.get_node("BlueLight") as OmniLight3D).light_energy == 0.0, "effects off disables beacon lights")
	pursuit.reset_pursuit()
	_check(not visual.visible and viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "reset disables police and mirror")
	var count := _count(pursuit)
	for cycle in range(200):
		pursuit.set_heat(cycle % 7)
		pursuit.begin(at)
		pursuit.advance(0.5, at, 15.0, 45.0)
		_check(pursuit.active and pursuit.gap_m > 40.0, "initial grace protects damaged driver")
		pursuit.reset_pursuit()
		pursuit.advance(1.0, at, 0.0, 45.0)
		_check(not pursuit.active and pursuit.gap_m == 0.0, "inactive advance stays inactive")
	_check(_count(pursuit) == count and count < 500, "two hundred starts keep bounded visual pool")
	_check(pursuit.get_rearview_texture() == texture, "mirror texture reused across restart")
	_check(_physics_count(pursuit) == 0, "reuse never introduces collision actors")
	# Deferred traffic contact cancels the provisional disengagement result.
	var escapes := [0]
	pursuit.escaped.connect(func(): escapes[0] += 1)
	for contact in ["close", "mistake"]:
		pursuit.set_heat(0)
		pursuit.begin(Vector3.ZERO)
		pursuit.gap_m = 110.0
		pursuit.disengagement_seconds = 4.999
		if contact == "close":
			pursuit.register_close_call.call_deferred()
		else:
			pursuit.register_mistake.call_deferred()
		pursuit.advance(1.0 / 60.0, Vector3.ZERO, 45.0, 45.0)
		await process_frame
		_check(pursuit.active and escapes[0] == 0 and pursuit.disengagement_seconds == 0.0, "deferred %s prevents premature release" % contact)
	pursuit.free()
	print("PURSUIT PASS: rear view, pause, effects, 200 bounded reuses, deferred contacts" if failures == 0 else "PURSUIT FAIL: %d" % failures)
	quit(1 if failures else 0)

func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total

func _physics_count(node: Node) -> int:
	var total := 1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child in node.get_children():
		total += _physics_count(child)
	return total

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("PURSUIT FAIL: " + label)
