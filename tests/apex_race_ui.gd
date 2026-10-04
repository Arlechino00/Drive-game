extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ResourceLoader.exists("res://scripts/apex_race_ui.gd"):
		_check(false, "Apex race UI exists")
		quit(1)
		return
	var ui = load("res://scripts/game_ui.gd").new()
	root.add_child(ui)
	await process_frame
	var race = load("res://scripts/apex_race_ui.gd").new()
	root.add_child(race)
	race.attach(ui)
	var arena := Node3D.new()
	root.add_child(arena)
	var actor := RoadObstacle.new()
	arena.add_child(actor)
	actor.activate(Vector3(-5, 0, -12), RoadObstacle.Kind.CAR, 0.0, 8)
	ui.show_playing()
	race.update_race(true, 29.2, -12.0, 1.4, true, 0.0)
	race.show_challenge()
	await process_frame
	_check(race.race_panel.visible and race.notification_panel.visible, "challenge and persistent race status are visible")
	_check("30" in race.countdown_label.text and "APEX" in race.lead_label.text, "countdown rounds up and negative lead describes rival ahead")
	_check("1.4/4.0" in race.requirements_label.text and "CLEAN" in race.requirements_label.text, "boost and pothole requirements remain visible")
	for target in range(4, 8):
		race.update_race(true, 29.2, -12.0, target - 0.1, true, 0.0, float(target))
		race.show_challenge(-5.0, float(target))
		_check("/%.1f" % float(target) in race.requirements_label.text and "TARGET: %ds" % target in race.notification_detail.text, "each4–7s boost target matches in challenge and status")
	_check("3.7s" in race.notification_detail.text and "close passes" in race.notification_detail.text, "challenge explains finite fuel and earned refill")
	race.update_race(true, 30.0, -13.0, 0.0, true, 0.0, 7.0, 2.2)
	_check("GET READY" in race.countdown_label.text and "3" in race.countdown_label.text and "/7.0" in race.requirements_label.text, "countdown and selected boost target are distinct")
	race.update_opponent(actor, arena.get_world_3d())
	if race.get("opponent_road") == null:
		_check(false, "rival feed has bounded road backdrop")
		race.free()
		arena.free()
		ui.free()
		quit(1)
		return
	_check(race.opponent_panel.visible and race.opponent_view.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "active race renders actual rival feed")
	_check(race.opponent_road.visible and race.opponent_road.get_child_count() <= 8, "live feed enables one small bounded backdrop")
	var phase_before: float = race._dash_phase
	race._process(0.1)
	_check(race._dash_phase != phase_before and race._dash_phase >= 0.0 and race._dash_phase < 7.0, "fallback lane dashes advance with real rival speed using bounded phase")
	for visual in race.opponent_road.get_children():
		_check(visual.layers == (1 << 19), "backdrop uses feed-only visibility layer")
	var floor_mesh: MeshInstance3D = race.opponent_road_floor
	_check(floor_mesh.position.y + (floor_mesh.mesh as BoxMesh).size.y * 0.5 < -0.02, "backdrop floor stays below actual asphalt")
	var bounded_count: int = _node_count(race) + _node_count(ui)
	for lead in [-180.0, 280.0]:
		actor.position.z = lead
		race.update_race(true, 20.0, lead, 2.0, true, 0.0, 7.0)
		race.update_opponent(actor, arena.get_world_3d())
		_check(("AHEAD" if lead < 0.0 else "BEHIND") in race.opponent_caption.text and "%dm" % absi(roundi(lead)) in race.opponent_caption.text, "far rival feed describes actual gap and direction")
		_check(actor.position.z == lead and race.opponent_camera.global_position.distance_to(actor.global_position) < 12.0, "feed camera follows without moving the far rival")
		_check(race.opponent_road.position == Vector3(0, 0, lead), "far rival feed road remains centered under actual actor")
		var projected: Vector2 = race.opponent_camera.unproject_position(actor.global_position + Vector3.UP)
		_check(Rect2(Vector2.ZERO, Vector2(race.opponent_view.size)).has_point(projected), "far rival remains framed in feed in either direction")
	for iteration in range(12):
		race.reset_ui()
		race.update_race(true, 20.0, actor.position.z, 2.0, true, 0.0, 7.0)
		race.update_opponent(actor, arena.get_world_3d())
	_check(_node_count(race) + _node_count(ui) == bounded_count, "repeated encounters reuse one viewport, camera and HUD")
	race.show_challenge()
	_check(race.notification_panel.anchor_left == 1.0 and race.notification_panel.offset_right == -24.0, "left-lane rival keeps challenge at right edge")
	race.show_challenge(5.0)
	_check(race.notification_panel.anchor_left == 0.0 and race.notification_panel.offset_left == 24.0, "right-lane rival keeps challenge at left edge")
	race.show_challenge(0.0)
	_check(race.notification_panel.anchor_left == 1.0, "central rival uses right-side challenge")
	var saved: float = race.notification_remaining
	var paused_phase: float = race._dash_phase
	paused = true
	ui.show_paused()
	await process_frame
	_check(not race.notification_panel.visible and not race.race_panel.visible, "pause hides race overlays")
	_check(not race.opponent_panel.visible and race.opponent_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "pause stops rival feed rendering")
	_check(not race.opponent_road.visible, "pause hides feed-only backdrop")
	_check(race._dash_phase == paused_phase, "pause freezes fallback driving cue")
	_check(is_equal_approx(saved, race.notification_remaining), "pause freezes challenge popup timer")
	paused = false
	ui.show_playing()
	await process_frame
	_check(race.notification_panel.visible and race.race_panel.visible, "resume restores active race information")
	_check(race.opponent_panel.visible, "resume restores rival feed")
	race.update_race(true, 2.1, 1.0, 3.1, false, 0.0)
	_check("YOU" in race.lead_label.text and "POTHOLE HIT" in race.requirements_label.text, "lead and pothole failure are explicit")
	race.show_result(false, false)
	_check("APEX" in race.notification_title.text and not "POLICE" in race.notification_detail.text, "ordinary loss taunts without police consequence")
	race.show_result(false, true)
	_check(not race.opponent_panel.visible and race.opponent_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "police consequence stops rival feed")
	_check(not race.opponent_road.visible, "police consequence hides feed-only backdrop")
	_check("POLICE" in race.notification_detail.text and "speeding" in race.notification_detail.text, "Secret loss explains pursuit cause")
	ui.configure_mode(1)
	race.update_race(false, 0.0, 0.0, 0.0, true, 10.0)
	race.show_result(true, false)
	_check("20,000" in race.notification_detail.text and "10s" in race.notification_detail.text, "win states both rewards")
	_check(race.reward_panel.visible and "10.0s" in race.reward_label.text, "reward duration is explicit even in Infinite Boost")
	for window_size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(2560, 2048), Vector2i(3440, 1440)]:
		root.size = window_size
		ui.show_playing()
		race.update_race(true, 12.3, -75.0, 0.5, false, 10.0)
		race.update_opponent(actor, arena.get_world_3d())
		race.show_challenge()
		ui.show_feedback("NEAR MISS +250")
		ui.update_hazard_warning(3.0)
		for index in range(4):
			await process_frame
		var area := root.get_visible_rect()
		for panel in [race.race_panel, race.notification_panel, race.reward_panel, race.opponent_panel]:
			_check(area.encloses(panel.get_global_rect()), "race panels fit %s" % window_size)
			for label in panel.get_child(0).get_children():
				_check(panel.get_global_rect().encloses(label.get_global_rect()), "race text fits its panel at %s" % window_size)
			_check(not panel.get_global_rect().intersects(ui.feedback.get_global_rect()), "race overlays avoid near-miss feedback at %s" % window_size)
			_check(not panel.get_global_rect().intersects(ui.hazard_warning.get_global_rect()), "race overlays avoid pothole warning at %s" % window_size)
		_check(not race.reward_panel.get_global_rect().intersects(ui.boost_meter.get_global_rect()), "reward timer avoids boost meter at %s" % window_size)
		_check(not race.opponent_panel.get_global_rect().intersects(ui.boost_meter.get_global_rect()) and not race.opponent_panel.get_global_rect().intersects(race.reward_panel.get_global_rect()), "rival feed avoids centered boost and reward at %s" % window_size)
		var feed_scale: float = race.opponent_caption.get_global_transform().get_scale().x * root.get_final_transform().get_scale().x
		_check(race.opponent_caption.get_theme_font_size("font_size") * feed_scale >= 13.0, "rival direction and gap remain readable at %s" % window_size)
		for rival_x in [-5.0, 5.0]:
			race.show_challenge(rival_x)
			for index in range(3):
				await process_frame
			_check(area.encloses(race.notification_panel.get_global_rect()), "both notification sides fit at %s" % window_size)
			_check(not race.opponent_panel.get_global_rect().intersects(race.notification_panel.get_global_rect()), "side notification avoids rival feed at %s" % window_size)
			var popup: Rect2 = race.notification_panel.get_global_rect()
			var center_x: float = ui.hud.get_global_rect().get_center().x
			_check(center_x < popup.position.x or center_x > popup.end.x, "notification leaves the central driving lane clear at %s" % window_size)
			race.show_result(false, true)
			for index in range(3):
				await process_frame
			for label in race.notification_panel.get_child(0).get_children():
				_check(race.notification_panel.get_global_rect().encloses(label.get_global_rect()), "wrapped Secret result fits both sides at %s" % window_size)
		race.update_race(true, 12.3, -75.0, 0.5, false, 10.0)
		race.show_challenge()
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tests/apex_ui_%d.png" % window_size.x)
	race.notification_remaining = 0.1
	race._process(0.2)
	_check(not race.notification_panel.visible and race.race_panel.visible, "popup expires independently of race status")
	ui.show_game_over(0, 0)
	await process_frame
	_check(not race.race_panel.visible and not race.reward_panel.visible, "results menu hides all race overlays")
	race.reset_ui()
	ui.show_playing()
	await process_frame
	_check(not race.race_panel.visible and not race.notification_panel.visible and not race.reward_panel.visible, "reset clears stale race and reward notices")
	_check(not race.opponent_panel.visible and race.opponent_view.render_target_update_mode == SubViewport.UPDATE_DISABLED, "reset stops stale rival feed")
	_check(not race.opponent_road.visible, "reset hides stale feed-only backdrop")
	race.free()
	arena.free()
	ui.free()
	if failures == 0:
		print("APEX UI PASS: pausable nonblocking popup, race requirements, mode-specific outcomes, reward duration, responsive HUD")
	quit(1 if failures else 0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("APEX UI FAIL: " + message)


func _node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _node_count(child)
	return count
