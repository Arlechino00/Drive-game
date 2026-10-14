extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.set_process(false)
	game.tutorial_enabled = true
	game.start_game()
	game.player.position.x = 4.0
	game.player.visual.rotation = Vector3(0, -0.08, -0.06)
	game.camera.follow(0.3, 4.0, 4.0, game.speed, false)
	game.road.advance(133.0)
	var road_poses := []
	for segment in game.road.segments:
		road_poses.append(segment.transform)
	var pose: Transform3D = game.player.transform
	var visual_pose: Transform3D = game.player.visual.transform
	var camera_pose: Transform3D = game.camera.transform
	var camera_fov: float = game.camera.fov
	game.tutorial.finish()
	_check(game.player.transform == pose and game.player.visual.transform == visual_pose, "Skip preserves visible car pose")
	_check(game.camera.transform == camera_pose and game.camera.fov == camera_fov, "Skip preserves camera view")
	for index in range(game.road.segments.size()):
		_check(game.road.segments[index].transform == road_poses[index], "Skip preserves visible road segments")
	game.road.advance(0.1)
	_check(is_equal_approx(game.road._road_phase, 133.1), "road continues from its preserved phase on the following frame")
	_check(game.distance == 0 and game.get_score() == 0 and game.run_seconds == 0 and game.progress.score_valid and game.obstacles.spawning_enabled, "handoff preserves clean normal state")
	game.start_game()
	game.tutorial.step = game.tutorial.STANDARD.find("finish")
	game.tutorial._enter_step()
	game.tutorial.advance(1.0)
	_check(not game.tutorial.active, "completion hands off within one second")
	_check(game.ui.has_method("configure_ranked"), "HUD exposes persistent ranking eligibility")
	if game.ui.has_method("configure_ranked"):
		game.ui.configure_ranked(false)
		_check(game.ui.rank_label.visible, "unranked badge stays visible beyond transient feedback")
		game.ui.configure_language(1)
		_check(game.ui.rank_label.text == "În afara clasamentului", "unranked badge switches Romanian live")
		game.ui.configure_ranked(true)
		_check(not game.ui.rank_label.visible, "clean new ranked round clears the badge")
		game.ui.configure_language(0)
	var priority_available := false
	for method in game.ui.get_method_list():
		if method.name == "show_feedback":
			priority_available = method.args.size() >= 3
	_check(priority_available, "feedback supports importance")
	if priority_available:
		game.ui.show_feedback("Critical capture", game.ui.MAGENTA, 2)
		game.ui.show_feedback("Routine bonus", game.ui.CYAN, 0)
		_check(game.ui.feedback.text == "Critical capture", "routine bonuses cannot replace active critical feedback")
		game.ui._feedback_tween.custom_step(2.0)
		game.ui.show_feedback("Routine bonus", game.ui.CYAN, 0)
		_check(game.ui.feedback.text == "Routine bonus", "expired critical feedback releases priority for future bonuses")
		game.ui._clear_feedback()
		game.ui.show_feedback("Routine bonus", game.ui.CYAN, 0)
		_check(game.ui.feedback.text == "Routine bonus", "cleared priority allows later routine feedback")
	_check(game.audio.music.stream.get_length() >= 30.0, "music arrangement is longer than thirty seconds")
	var music_data: PackedByteArray = game.audio.music.stream.data
	var phrase_samples := roundi(8.0 * 60.0 / 110.0 * game.audio.SAMPLE_RATE) * 2
	_check(music_data.size() >= phrase_samples * 2 and music_data.slice(0, phrase_samples) != music_data.slice(phrase_samples, phrase_samples * 2), "successive complete music phrases vary")
	_check(game.audio.has_method("set_tension"), "music accepts bounded gameplay tension")
	if game.audio.has_method("set_tension"):
		game.audio.set_driving(false, 0.0, false)
		game.audio.set_police(false)
		game.audio.set_tension(0.0)
		game.audio._process(10.0)
		var calm: float = game.audio.music_tension.volume_db
		game.audio.set_tension(99.0)
		game.audio._process(10.0)
		_check(game.audio.music_tension.volume_db > calm and game.audio.music_tension.volume_db <= -25.0, "clamped tension changes the existing mix safely")
		game.audio.stop_transients()
		game.audio._process(10.0)
		_check(game.audio.music_tension.volume_db == calm, "transient reset clears event tension")
	var node_count: int = game.audio.get_child_count()
	for cycle in range(40):
		game.audio.set_driving(true, 150.0, true)
		game.audio.set_police(true)
		game.audio.stop_transients()
	_check(game.audio.get_child_count() == node_count, "adaptive music and cue transitions keep audio bounded")
	game.ui._clear_feedback()
	game.audio.stop_all()
	await create_timer(0.2).timeout
	game.free()
	game = null
	await process_frame
	if failures == 0:
		print("UI AUDIO PASS: smooth clean handoff, short finish, critical feedback, varied bounded arrangement")
	quit(1 if failures else 0)

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error("UI AUDIO FAIL: " + label)
