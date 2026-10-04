extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(not OS.has_feature("editor"), "running the actual exported executable")
	_check(FileAccess.file_exists("res://config/secret_mode.cfg"), "non-resource configuration is bundled")
	var arguments := OS.get_cmdline_user_args()
	var invalid := arguments.has("--invalid-external")
	var fallback := arguments.has("--bundled-fallback")
	var bundled := ConfigFile.new()
	_check(bundled.load("res://config/secret_mode.cfg") == OK, "bundled configuration parses")
	var bundled_access: String = bundled.get_value("secret_mode", "access_code", "")
	var bundled_resume: String = bundled.get_value("secret_mode", "resume_code", "")
	var access_code := bundled_access if fallback else "RELEASE-ACCESS"
	var resume_code := bundled_resume if fallback else "RELEASE-RESUME"
	var game = get_parent()
	# Keep the verifier alive while explicitly closing the actual game tree.
	reparent(get_tree().root)
	await get_tree().process_frame
	game.obstacles.spawning_enabled = false
	game.community.request_access()
	game._on_secret_code_submitted("wrong")
	_check(not game.access.secret_unlocked, "incorrect access stays locked")
	if invalid:
		game._on_secret_code_submitted(bundled_access)
		_check(not game.access.secret_unlocked, "invalid loose configuration cannot fall back to bundled access")
		_check(not game.access.validate_resume_code(bundled_resume), "invalid loose configuration disables bundled resume")
	else:
		game._on_secret_code_submitted(access_code)
		_check(game.access.secret_unlocked and game.selected_mode == 2, "exported title unlock selects Secret")
		_check(not game.access.validate_resume_code("wrong"), "incorrect resume rejected")
		game._on_name_submitted("Release Test")
		_check(game.state == game.GameState.PLAYING and game.run_mode == 2, "exported Secret driving starts")
		for hit in range(6):
			if game.state != game.GameState.PLAYING:
				break
			game._on_player_hit()
		_check(game.state == game.GameState.GAME_OVER, "exported police capture ends driving")
		game.aftermath.advance(4.0)
		await get_tree().process_frame
		game._on_resume_code_submitted(resume_code)
		_check(game.state == game.GameState.PLAYING and game.run_resumed, "configured exported resume continues captured run")
		_check(game.access.validate_resume_code(resume_code), "exported resume remains reusable")
	game.return_to_menu()
	game.audio.stop_all()
	var until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	game.free()
	await get_tree().process_frame
	if failures == 0:
		print("EXPORTED RELEASE PASS: bundled config, title access and captured-run continuation (%s)" % ("invalid external" if invalid else "bundled fallback" if fallback else "editable external"))
	get_tree().quit(1 if failures else 0)

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("EXPORTED RELEASE FAIL: " + label)
