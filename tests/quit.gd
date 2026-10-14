extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	var records_path := "user://quit_test_records.cfg"
	DirAccess.remove_absolute(records_path)
	game.records = load("res://scripts/player_records.gd").new(records_path)
	game.player_name = "Quit regression"
	game.start_game(false)
	game.progress.bonus_points = 1000
	await physics_frame
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	for frame in range(3):
		await process_frame
	if not game.quitting or not paused:
		push_error("QUIT FAIL: window close freezes gameplay")
		quit(1)
		return
	var saved_records = load("res://scripts/player_records.gd").new(records_path)
	if saved_records.load_records() != OK or saved_records.top_entries(0).size() != 1 or saved_records.top_entries(0)[0].score < 1000:
		push_error("QUIT FAIL: window close must persist the valid round before exiting")
		quit(1)
		return
	DirAccess.remove_absolute(records_path)
	for player in game.audio.get_children():
		if player.playing:
			push_error("QUIT FAIL: audio restarts during shutdown")
			quit(1)
			return
	print("QUIT PASS: window close saves the valid round, freezes gameplay, stops audio, and exits cleanly")
	# The game's real close handler exits after allowing the mixer to drain.
