extends Node3D

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }
enum GameMode { FAIR, INFINITE_BOOST, SECRET }

const ProgressScript = preload("res://scripts/run_progress.gd")
const DirectorScript = preload("res://scripts/difficulty_director.gd")
const INITIAL_SPEED: float = DirectorScript.INITIAL_SPEED
const MAX_SPEED: float = DirectorScript.MAX_BOOST_SPEED
const SettingsScript = preload("res://scripts/game_settings.gd")
const CameraScript = preload("res://scripts/chase_camera.gd")
const AudioScript = preload("res://scripts/drive_audio.gd")
const CrashScript = preload("res://scripts/crash_effect.gd")
const AftermathScript = preload("res://scripts/police_aftermath.gd")
const RecordsScript = preload("res://scripts/player_records.gd")
const AccessScript = preload("res://scripts/secret_access.gd")
const PursuitScript = preload("res://scripts/police_pursuit.gd")
const CommunityScript = preload("res://scripts/community_ui.gd")
const RaceScript = preload("res://scripts/apex_race.gd")
const RaceUIScript = preload("res://scripts/apex_race_ui.gd")
const TrafficModels = preload("res://scripts/traffic_models.gd")

var state: GameState = GameState.MENU
var distance: float = 0.0
var speed: float = INITIAL_SPEED
var best_score: int = 0
var player: PlayerCar
var road: RoadManager
var obstacles: ObstacleSpawner
var camera: CameraScript
var ui: GameUI
var world: VisualWorld
var progress := ProgressScript.new()
var director := DirectorScript.new()
var settings := SettingsScript.new()
var audio: AudioScript
var best_distance: float = 0.0
var best_combo: float = 1.0
var best_speed: float = 0.0
var debug_visible: bool = false
var run_seed: int = -1
var debug_refresh: float = 0.0
var crash_effect: CrashScript
var quitting: bool = false
var selected_mode: GameMode = GameMode.FAIR
var run_mode: GameMode = GameMode.FAIR
var aftermath: Node3D
var end_reason: String = ""
var records = RecordsScript.new()
var access = AccessScript.new()
var pursuit: Node3D
var community: Node
var player_name: String = ""
var run_resumed: bool = false
var secret_escapes: int = 0
var apex_race := RaceScript.new()
var apex_ui: Node
var race_random := RandomNumberGenerator.new()
var records_recovered: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	run_seed = parse_run_seed(OS.get_cmdline_user_args())
	var records_error: Error = records.load_records()
	if records_error in [ERR_PARSE_ERROR, ERR_FILE_CORRUPT]:
		records_recovered = records.recover_records() == OK
	access.load_access()
	player_name = records.player_name
	_load_best_score()
	settings.load_settings()
	world = VisualWorld.new()
	add_child(world)
	road = RoadManager.new()
	add_child(road)
	obstacles = ObstacleSpawner.new()
	add_child(obstacles)
	obstacles.player_hit.connect(_on_player_hit)
	obstacles.near_miss.connect(_on_near_miss)
	obstacles.pothole_hit.connect(_on_pothole_hit)
	obstacles.roadworks_entered.connect(_on_roadworks_entered)
	player = PlayerCar.new()
	add_child(player)
	aftermath = AftermathScript.new()
	add_child(aftermath)
	pursuit = PursuitScript.new()
	add_child(pursuit)
	pursuit.caught.connect(_on_pursuit_caught)
	pursuit.escaped.connect(_on_pursuit_escaped)
	crash_effect = CrashScript.new()
	add_child(crash_effect)
	camera = CameraScript.new()
	add_child(camera)
	audio = AudioScript.new()
	add_child(audio)
	ui = GameUI.new()
	add_child(ui)
	ui.start_pressed.connect(request_start_game)
	ui.resume_pressed.connect(resume_game)
	ui.restart_pressed.connect(start_game)
	ui.menu_pressed.connect(return_to_menu)
	ui.mode_selected.connect(select_mode)
	ui.settings_changed.connect(_on_settings_changed)
	ui.quit_pressed.connect(_quit_game)
	ui.configure_secret(access.secret_unlocked)
	community = CommunityScript.new()
	add_child(community)
	community.attach(ui)
	community.name_submitted.connect(_on_name_submitted)
	community.secret_code_submitted.connect(_on_secret_code_submitted)
	community.resume_code_submitted.connect(_on_resume_code_submitted)
	community.leaderboard_requested.connect(_on_leaderboard_requested)
	community.set_rearview_texture(pursuit.get_rearview_texture())
	apex_ui = RaceUIScript.new()
	add_child(apex_ui)
	apex_ui.attach(ui)
	ui.update_hud(0, roundi(speed * 3.6))
	ui.show_menu()
	ui.configure_mode(selected_mode)
	ui.configure_settings(settings.volume, settings.shake, settings.effects, settings.fullscreen, settings.quality, settings.resolution)
	_apply_settings()
	# Official release templates disable editor script/path overrides. Package
	# checks enter explicitly through the same shipped main scene instead.
	if OS.get_cmdline_user_args().has("--verify-release"):
		var verification = load("res://tests/exported_release.gd")
		if verification == null:
			get_tree().quit(1)
		else:
			add_child(verification.new())


func _physics_process(delta: float) -> void:
	if state != GameState.PLAYING or quitting:
		return
	var was_boosting := progress.boosting
	progress.update_boost(_boost_requested(), delta, run_mode == GameMode.SECRET)
	if progress.boosting and not was_boosting:
		ui.show_feedback("BOOST ENGAGED", Color("#54edff"))
	var target_speed := director.get_base_speed(distance)
	if progress.damage_remaining > 0.0:
		target_speed = maxf(27.0, target_speed - progress.damage_speed_loss * progress.damage_remaining / progress.POTHOLE_RECOVERY)
	if progress.boosting:
		target_speed = minf(MAX_SPEED, target_speed + director.BOOST_SPEED_GAIN)
	speed = move_toward(speed, target_speed, (16.0 if progress.boosting else 12.0) * delta)
	var distance_delta := speed * delta
	if apex_race.active:
		apex_race.prepare_opponent(delta, director.get_base_speed(distance), player.position.x, obstacles.obstacle_pool, speed)
	distance += distance_delta
	progress.advance(delta, distance_delta, speed)
	road.advance(distance_delta)
	obstacles.advance(distance_delta, distance, director.get_density(distance), delta, player.position.x)
	# Swept road contacts can end the run during encounter advancement.
	if state != GameState.PLAYING:
		return
	_update_apex_race(delta)
	if pursuit.active:
		pursuit.advance(delta, player.position, speed, director.get_base_speed(distance), settings.effects)
		if state != GameState.PLAYING:
			return
	community.update_pursuit(pursuit.active, pursuit.gap_m, pursuit.clean_seconds)
	audio.set_police(pursuit.active)
	player.set_boost(progress.boosting, settings.effects)
	audio.set_driving(true, speed, progress.boosting)
	ui.update_hud(get_score(), roundi(speed * 3.6), progress.multiplier, progress.boost_charge, progress.boosting, 0.0 if run_mode == GameMode.SECRET else progress.damage_remaining)
	ui.update_hazard_warning(progress.pothole_remaining)
	ui.set_reward_boost(progress.reward_boost_remaining)
	debug_refresh += delta
	if debug_refresh >= 0.25:
		debug_refresh = 0.0
		_update_debug()


func _process(delta: float) -> void:
	if not player or not camera:
		return
	if state == GameState.PAUSED:
		return
	if state == GameState.GAME_OVER and aftermath.active:
		aftermath.advance(delta, settings.effects)
		aftermath.frame_camera(camera, delta)
		audio.set_police(not aftermath.arrived)
		community.set_resume_available(run_mode == GameMode.SECRET and aftermath.arrived and not run_resumed)
		return
	if state == GameState.MENU:
		road.advance(delta * 12.0)
	var rival_z: float = apex_race.actor.position.z if apex_race.active and is_instance_valid(apex_race.actor) else NAN
	camera.follow(delta, player.position.x, player.lateral_velocity, speed, progress.boosting, rival_z)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if community and community.is_modal_open():
		return
	if event.keycode == KEY_ESCAPE:
		if state == GameState.PLAYING:
			pause_game()
		elif state == GameState.PAUSED:
			resume_game()
	elif event.keycode == KEY_R and (state == GameState.GAME_OVER or state == GameState.PAUSED):
		start_game()
	elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and state == GameState.MENU:
		request_start_game()
	elif (event.keycode == KEY_F8 or (event.keycode == KEY_S and event.ctrl_pressed and event.shift_pressed)) and state == GameState.MENU:
		community.request_access()
	elif event.keycode == KEY_F3:
		debug_visible = not debug_visible
		_update_debug()


func _input(event: InputEvent) -> void:
	# Releasing boost during pause is still a new input gesture on resume.
	var released_key: bool = event is InputEventKey and not event.pressed and (event.keycode == KEY_SHIFT or event.keycode == KEY_SPACE)
	var released_trigger: bool = event is InputEventJoypadMotion and event.axis == JOY_AXIS_TRIGGER_RIGHT and event.axis_value <= 0.25
	if (released_key or released_trigger) and not _boost_requested():
		progress.boost_empty_lock = false


func request_start_game() -> void:
	if state == GameState.MENU:
		community.request_name(player_name)


func _on_name_submitted(raw: String) -> void:
	if state != GameState.MENU:
		return
	var normalized: String = records.display_player_name(raw)
	if normalized.is_empty():
		community.show_name_error("Enter a name with 1–24 visible characters.")
		return
	var saved: Error = records.save_player_name(raw)
	if saved in [ERR_PARSE_ERROR, ERR_FILE_CORRUPT] and records.recover_records() == OK:
		records_recovered = true
		saved = records.save_player_name(normalized)
	# A damaged or temporarily unwritable save must never lock the driver out.
	player_name = normalized
	start_game()
	if saved != OK:
		ui.show_feedback("DRIVING NOW  /  NAME COULD NOT BE SAVED", GameUI.ORANGE)
	elif records_recovered:
		ui.show_feedback("RECORDS RECOVERED  /  ORIGINAL KEPT AS BACKUP", GameUI.CYAN)
		records_recovered = false


func _on_secret_code_submitted(code: String) -> void:
	if state != GameState.MENU:
		return
	if not access.unlock(code):
		community.show_access_error(access.configuration_error if not access.configuration_error.is_empty() else "That access code is not valid.")
		return
	ui.configure_secret(true)
	community.dismiss()
	ui.show_menu()
	select_mode(GameMode.SECRET)


func _on_leaderboard_requested(mode: int, resumed: bool) -> void:
	if state == GameState.MENU:
		# Atomic reload keeps the last valid cache if another writer is busy or
		# its file is unreadable, and exposes scores from other open instances.
		records.load_records()
		community.show_leaderboard(records.top_entries(mode, resumed), mode, resumed)


func start_game() -> void:
	if selected_mode == GameMode.SECRET:
		access.load_access()
		ui.configure_secret(access.secret_unlocked)
		if not access.secret_unlocked:
			selected_mode = GameMode.FAIR
			return_to_menu()
			community.request_access()
			return
	get_tree().paused = false
	_reset_apex_race()
	state = GameState.PLAYING
	end_reason = ""
	obstacles.motion_enabled = true
	community.dismiss()
	community.set_resume_available(false)
	pursuit.reset_pursuit()
	community.update_pursuit(false, 0.0, 0.0)
	run_resumed = false
	ui.configure_resumed(false)
	secret_escapes = 0
	aftermath.reset_scene()
	distance = 0.0
	speed = INITIAL_SPEED
	run_mode = selected_mode
	_load_best_score()
	progress.reset(run_mode == GameMode.INFINITE_BOOST)
	world.set_secret_level(run_mode == GameMode.SECRET)
	ui.configure_mode(run_mode)
	camera.reset_camera()
	crash_effect.reset_effect()
	audio.stop_transients()
	player.reset_car()
	player.active = true
	road.reset_road()
	obstacles.reset_spawner(run_seed)
	# A separate seeded stream keeps race requirements replayable without
	# changing the traffic layouts when another challenge is encountered.
	race_random.seed = obstacles.active_seed ^ 0x41504558
	ui.update_hud(0, roundi(speed * 3.6), progress.multiplier, progress.boost_charge)
	ui.show_playing()
	ui.update_hazard_warning(0.0)
	audio.play_cue("ui")
	audio.set_driving(true, speed, false)
	_update_debug()


func return_to_menu() -> void:
	get_tree().paused = false
	_reset_apex_race()
	state = GameState.MENU
	end_reason = ""
	community.dismiss()
	community.set_resume_available(false)
	pursuit.reset_pursuit()
	community.update_pursuit(false, 0.0, 0.0)
	run_resumed = false
	ui.configure_resumed(false)
	world.set_secret_level(false)
	aftermath.reset_scene()
	player.reset_car()
	crash_effect.reset_effect()
	audio.stop_transients()
	for obstacle in obstacles.obstacle_pool:
		obstacle.deactivate()
	progress.reset(selected_mode == GameMode.INFINITE_BOOST)
	speed = INITIAL_SPEED
	distance = 0.0
	road.reset_road()
	camera.reset_camera()
	audio.set_driving(false, speed, false)
	audio.play_cue("ui")
	ui.show_menu()
	ui.update_hazard_warning(0.0)
	ui.configure_mode(selected_mode)


func select_mode(mode: int) -> void:
	if state != GameState.MENU:
		return
	if mode == GameMode.SECRET:
		access.load_access()
		ui.configure_secret(access.secret_unlocked)
		if not access.secret_unlocked:
			selected_mode = GameMode.FAIR
			return
	selected_mode = GameMode.SECRET if mode == GameMode.SECRET else (GameMode.INFINITE_BOOST if mode == GameMode.INFINITE_BOOST else GameMode.FAIR)
	ui.configure_mode(selected_mode)
	_load_best_score()


func pause_game() -> void:
	if state != GameState.PLAYING:
		return
	state = GameState.PAUSED
	audio.set_driving(false, speed, false)
	audio.set_police(false)
	ui.show_paused()
	get_tree().paused = true


func resume_game() -> void:
	if state != GameState.PAUSED:
		return
	get_tree().paused = false
	state = GameState.PLAYING
	ui.show_playing()
	audio.set_driving(true, speed, progress.boosting)
	audio.set_police(pursuit.active)


func get_score() -> int:
	return progress.get_score()


func _on_player_hit() -> void:
	var struck: RoadObstacle = obstacles.last_hit_obstacle
	if run_mode == GameMode.SECRET and state == GameState.PLAYING:
		_secret_impact("TRAFFIC IMPACT", 1000, 30.0)
		return
	var traffic_collision := struck == null or struck.kind in [RoadObstacle.Kind.CAR, RoadObstacle.Kind.VAN, RoadObstacle.Kind.WIDE]
	_finish_run("Traffic collision.\nPolice are responding." if traffic_collision else "You hit a road barrier.", false, traffic_collision, struck)


func _on_pothole_hit() -> void:
	if state != GameState.PLAYING:
		return
	apex_race.hit_pothole()
	var before := get_score()
	if progress.hit_pothole():
		if run_mode == GameMode.SECRET:
			progress.pothole_remaining = progress.POTHOLE_WINDOW
			_secret_impact("REPEAT POTHOLE", 500, progress.POTHOLE_SPEED_LOSS)
			return
		_finish_run("Two potholes within 10 seconds.\nYour car cannot continue.")
		return
	speed = maxf(27.0, speed - progress.POTHOLE_SPEED_LOSS)
	player.set_boost(false, settings.effects)
	camera.impact()
	audio.play_cue("pothole")
	audio.set_driving(true, speed, false)
	ui.show_feedback("POTHOLE  −%d  /  SPEED LOST" % (before - get_score()), GameUI.ORANGE)
	ui.update_hud(get_score(), roundi(speed * 3.6), progress.multiplier, progress.boost_charge, false, 0.0 if run_mode == GameMode.SECRET else progress.damage_remaining)
	ui.update_hazard_warning(progress.pothole_remaining)
	if pursuit.active:
		pursuit.register_mistake()


func _on_roadworks_entered() -> void:
	if run_mode == GameMode.SECRET and state == GameState.PLAYING:
		_secret_impact("WORKSITE VIOLATION", 750, 26.0)
		return
	_finish_run("You entered a closed work lane.\nThis run does not count.", true, true)


func _secret_impact(caption: String, points: int, speed_loss: float) -> void:
	var was_pursuing: bool = pursuit.active
	if apex_race.active:
		_resolve_apex_race(false)
	progress.apply_damage(points, speed_loss)
	speed = maxf(27.0, speed - speed_loss)
	player.set_boost(false, settings.effects)
	camera.impact()
	audio.play_cue("pothole")
	ui.show_feedback(caption + "  /  POLICE PURSUIT", GameUI.ORANGE)
	if was_pursuing and pursuit.active:
		pursuit.register_mistake()
	elif not pursuit.active:
		pursuit.begin(player.position)
	if state == GameState.PLAYING:
		audio.set_police(true)
		community.update_pursuit(pursuit.active, pursuit.gap_m, pursuit.clean_seconds)


func _on_pursuit_caught() -> void:
	if state == GameState.PLAYING:
		_finish_run("Police caught you.\nThe chase is over.", false, true)


func _on_pursuit_escaped() -> void:
	if state != GameState.PLAYING:
		return
	secret_escapes += 1
	progress.bonus_points += 1000
	audio.set_police(false)
	ui.show_feedback("POLICE LOST  +1000", GameUI.CYAN)
	community.update_pursuit(false, 0.0, 0.0)


func _on_resume_code_submitted(code: String) -> void:
	if state != GameState.GAME_OVER or run_mode != GameMode.SECRET or run_resumed or not aftermath.active or not aftermath.arrived:
		community.show_resume_error("Resume is available once police have stopped beside you.")
		return
	if not access.validate_resume_code(code):
		community.show_resume_error(access.resume_configuration_error if not access.resume_configuration_error.is_empty() else "Code not accepted. Ask the team for the resume code.")
		return
	run_resumed = true
	ui.configure_resumed(true)
	_load_best_score(true)
	state = GameState.PLAYING
	end_reason = ""
	obstacles.motion_enabled = true
	community.dismiss()
	community.set_resume_available(false)
	aftermath.reset_scene()
	pursuit.reset_pursuit()
	community.update_pursuit(false, 0.0, 0.0)
	for obstacle in obstacles.obstacle_pool:
		obstacle.deactivate()
	progress.pothole_remaining = 0.0
	progress.damage_remaining = 0.0
	progress.crash()
	player.reset_car()
	player.active = true
	speed = director.get_base_speed(distance)
	camera.reset_camera()
	crash_effect.reset_effect()
	audio.stop_transients()
	audio.set_driving(true, speed, false)
	ui.show_playing()
	ui.update_hud(get_score(), roundi(speed * 3.6), progress.multiplier, progress.boost_charge)
	ui.update_hazard_warning(0.0)
	ui.show_feedback("BACK ON THE ROAD  /  RESUMED RUN", GameUI.CYAN)


func _finish_run(reason: String, invalid: bool = false, police_scene: bool = false, struck: RoadObstacle = null) -> void:
	if state != GameState.PLAYING:
		return
	_reset_apex_race()
	state = GameState.GAME_OVER
	obstacles.motion_enabled = false
	end_reason = reason
	pursuit.reset_pursuit()
	community.update_pursuit(false, 0.0, 0.0)
	community.set_resume_available(false)
	player.active = false
	player.set_boost(false, settings.effects)
	progress.crash()
	if invalid:
		progress.invalidate_score()
	camera.impact()
	if not invalid:
		crash_effect.trigger(player.position, settings.effects)
	audio.set_driving(false, speed, false)
	if not invalid:
		audio.play_cue("crash")
	if police_scene:
		if invalid or run_mode == GameMode.SECRET:
			aftermath.start_roadworks(player.position)
		else:
			var kind: int = struck.kind if struck else RoadObstacle.Kind.CAR
			var at: Vector3 = struck.position if struck else player.position + Vector3(0, 0, -6.3)
			aftermath.start_crash(player.position, kind, at, struck.model_id if struck else -1)
		audio.set_police(true)
	var score := get_score()
	var new_best := progress.score_valid and score > best_score
	if new_best:
		best_score = score
	if progress.score_valid:
		best_distance = maxf(best_distance, distance)
		best_combo = maxf(best_combo, progress.top_combo)
		best_speed = maxf(best_speed, progress.top_speed)
		var saved := _save_best_score()
		new_best = new_best and saved.error == OK and score > saved.previous_best
		if saved.error != OK:
			push_warning("Could not save this run's records.")
		if not player_name.is_empty():
			if records.record_run(player_name, run_mode, score, distance, run_resumed, secret_escapes) != OK:
				push_warning("Could not save the local leaderboard.")
	ui.show_game_over(score, best_score, distance, progress.top_combo, progress.near_misses, new_best, reason, invalid, police_scene)


func _update_apex_race(delta: float) -> void:
	if apex_race.active:
		if not is_instance_valid(apex_race.actor) or not apex_race.actor.active:
			_resolve_apex_race(false)
		else:
			var result := apex_race.advance(delta, progress.boosting)
			if result != 0:
				_resolve_apex_race(result > 0)
	elif not pursuit.active:
		for obstacle in obstacles.obstacle_pool:
			if obstacle.active and obstacle.model_id == TrafficModels.Model.APEX and not obstacle.pass_collided and obstacle.position.z >= -RaceScript.ENCOUNTER_DISTANCE and obstacle.position.z <= -8.0:
				apex_race.begin(obstacle, director.get_base_speed(distance), race_random.randi_range(4, 7))
				obstacles.begin_race(obstacle)
				apex_ui.show_challenge(obstacle.position.x, apex_race.required_boost_seconds)
				audio.play_cue("ui")
				break
	_sync_apex_ui()


func _resolve_apex_race(won: bool) -> void:
	apex_race.active = false
	obstacles.finish_race()
	apex_race.reset()
	if won:
		progress.bonus_points += RaceScript.POINTS
		progress.grant_race_reward(RaceScript.REWARD_SECONDS)
		audio.play_cue("near_miss")
	elif run_mode == GameMode.SECRET and state == GameState.PLAYING:
		# Losing the race triggers the existing moving chase, without inventing
		# a collision penalty or changing the driver's fuel or speed.
		if not pursuit.active:
			pursuit.begin(player.position)
		audio.set_police(true)
		community.update_pursuit(true, pursuit.gap_m, pursuit.clean_seconds)
	apex_ui.show_result(won, run_mode == GameMode.SECRET)
	_sync_apex_ui()


func _sync_apex_ui() -> void:
	apex_ui.update_race(apex_race.active, apex_race.remaining(), apex_race.lead_m, apex_race.boost_seconds, apex_race.clean, progress.reward_boost_remaining, apex_race.required_boost_seconds, apex_race.countdown_remaining)
	apex_ui.update_opponent(apex_race.actor if apex_race.active else null, get_world_3d(), road.materials)


func _reset_apex_race() -> void:
	obstacles.finish_race()
	apex_race.reset()
	if apex_ui:
		apex_ui.reset_ui()
		ui.set_reward_boost(0.0)


func _on_near_miss(points: int, clearance: float) -> void:
	if state != GameState.PLAYING:
		return
	var awarded := progress.reward_near_miss(points, clearance)
	var title := "VERY CLOSE" if clearance < 0.35 else "NEAR MISS"
	ui.show_feedback("%s  +%d  /  x%.1f" % [title, awarded, progress.multiplier], Color("#ffe399"))
	audio.play_cue("near_miss")
	if pursuit.active:
		pursuit.register_close_call()


func _boost_requested() -> bool:
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE):
		return true
	var joypads := Input.get_connected_joypads()
	return not joypads.is_empty() and Input.get_joy_axis(joypads[0], JOY_AXIS_TRIGGER_RIGHT) > 0.25


func _load_best_score(resumed: bool = false) -> void:
	best_score = 0
	best_distance = 0.0
	best_combo = 1.0
	best_speed = 0.0
	var config := ConfigFile.new()
	if config.load("user://highscore.cfg") == OK:
		var section := _score_section(selected_mode, resumed)
		best_score = _saved_score(config, section)
		best_distance = _saved_stat(config, section, "distance", 0.0)
		best_combo = _saved_stat(config, section, "combo", 1.0)
		best_speed = _saved_stat(config, section, "speed", 0.0)


func _save_best_score() -> Dictionary:
	var path := "user://highscore.cfg"
	var result := {"error": ERR_BUSY, "previous_best": 0}
	if DirAccess.make_dir_absolute(path + ".lock") != OK:
		return result
	# Merge under the lock: another open game may have finished since this run
	# started. Atomic replacement also preserves its other mode partitions.
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == OK or error == ERR_FILE_NOT_FOUND:
		var section := _score_section(run_mode, run_resumed)
		result.previous_best = _saved_score(config, section)
		var merged_score := maxi(best_score, result.previous_best)
		var merged_distance := maxf(best_distance, _saved_stat(config, section, "distance", 0.0))
		var merged_combo := maxf(best_combo, _saved_stat(config, section, "combo", 1.0))
		var merged_speed := maxf(best_speed, _saved_stat(config, section, "speed", 0.0))
		config.set_value(section, "best", merged_score)
		config.set_value(section, "distance", merged_distance)
		config.set_value(section, "combo", merged_combo)
		config.set_value(section, "speed", merged_speed)
		error = config.save(path + ".tmp")
		if error == OK:
			error = DirAccess.rename_absolute(path + ".tmp", path)
			if error != OK:
				DirAccess.remove_absolute(path + ".tmp")
		if error == OK:
			best_score = merged_score
			best_distance = merged_distance
			best_combo = merged_combo
			best_speed = merged_speed
	DirAccess.remove_absolute(path + ".lock")
	result.error = error
	return result


func _saved_score(config: ConfigFile, section: String) -> int:
	var value: Variant = config.get_value(section, "best", 0)
	return maxi(0, value) if value is int else 0


func _saved_stat(config: ConfigFile, section: String, key: String, fallback: float) -> float:
	var value: Variant = config.get_value(section, key, fallback)
	if not (value is float or value is int):
		return fallback
	var number := float(value)
	return number if is_finite(number) and number >= fallback else fallback


func _score_section(mode: GameMode, resumed: bool = false) -> String:
	# Preserve existing earned-boost records and keep unlimited runs separate.
	if mode == GameMode.SECRET:
		return "scores_secret_resumed" if resumed else "scores_secret"
	return "scores" if mode == GameMode.FAIR else "scores_infinite"


func _on_settings_changed(key: String, value: float) -> void:
	settings.set_value(key, value)
	_apply_settings()
	if settings.save_settings() != OK:
		push_warning("Could not save preferences.")


func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, settings.volume)))
	AudioServer.set_bus_mute(0, settings.volume <= 0.0)
	camera.shake_strength = settings.shake
	world.set_effects(settings.effects)
	if settings.quality == SettingsScript.Quality.LOW:
		world.environment.glow_enabled = false
	get_viewport().msaa_3d = Viewport.MSAA_2X if settings.quality == SettingsScript.Quality.HIGH else Viewport.MSAA_DISABLED
	ui.set_effects(settings.effects)
	player.effects_strength = settings.effects
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		if settings.resolution > 0 and not settings.fullscreen:
			var desired: Vector2i = SettingsScript.RESOLUTIONS[settings.resolution]
			var screen := DisplayServer.window_get_current_screen()
			var usable := DisplayServer.screen_get_usable_rect(screen)
			var available := usable.size - Vector2i(32, 64)
			var factor := minf(1.0, minf(float(available.x) / desired.x, float(available.y) / desired.y))
			var size := Vector2i(Vector2(desired) * maxf(0.1, factor))
			if DisplayServer.window_get_size() != size:
				DisplayServer.window_set_size(size)
				DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


func _update_debug() -> void:
	ui.set_debug("SEED %d   /   %s\n%s   /   ENCOUNTERS %d   /   POOL %d\nROAD %d   /   FPS %d" % [obstacles.active_seed, director.get_wave_name(distance), road.get_section_name(), obstacles.get_active_count(), obstacles.obstacle_pool.size(), road.segments.size(), Engine.get_frames_per_second()], debug_visible)


func _quit_game() -> void:
	if quitting:
		return
	quitting = true
	state = GameState.PAUSED
	get_tree().paused = true
	audio.stop_all()
	# Startup or fixed-FPS deltas can consume a timer instantly. The mixer uses
	# real time, so let stopped playback drain against the same clock.
	var drain_until := Time.get_ticks_msec() + 150
	while Time.get_ticks_msec() < drain_until:
		await get_tree().process_frame
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and audio:
		_quit_game()


static func parse_run_seed(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if argument.begins_with("--seed="):
			var value := argument.trim_prefix("--seed=")
			if value.is_valid_int() and value.to_int() >= 0:
				return value.to_int()
	return -1
