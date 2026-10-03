extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.start_game()
	await physics_frame
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	for frame in range(3):
		await process_frame
	if not game.quitting or not paused:
		push_error("QUIT FAIL: window close freezes gameplay")
		quit(1)
		return
	for player in game.audio.get_children():
		if player.playing:
			push_error("QUIT FAIL: audio restarts during shutdown")
			quit(1)
			return
	print("QUIT PASS: window close freezes gameplay, stops audio, and exits cleanly")
	# The game's real close handler exits after allowing the mixer to drain.
