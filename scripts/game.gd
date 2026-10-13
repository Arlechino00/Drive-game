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
const TutorialScript = preload("res://scripts/tutorial_ui.gd")
const RaceScript = preload("res://scripts/apex_race.gd")
const RaceUIScript = preload("res://scripts/apex_race_ui.gd")
const TrafficModels = preload("res://scripts/traffic_models.gd")
const EnforcementScript = preload("res://scripts/speed_enforcement.gd")
const RadarDisplayScript = preload("res://scripts/radar_display.gd")
const TouchControlsScript = preload("res://scripts/touch_drive_controls.gd")
const SaveLockScript = preload("res://scripts/save_lock.gd")
const HeatScript = preload("res://scripts/heat_controller.gd")
const DriveInput = preload("res://scripts/drive_input.gd")
const Tuning = preload("res://scripts/stage_two_tuning.gd")
const L = preload("res://scripts/localization.gd")
const BRAKE_MIN_SPEED: float = 8.0
const BRAKE_DECELERATION: float = 7.0

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
var tutorial: Node
var player_name: String = ""
var run_resumed: bool = false
var secret_escapes: int = 0
var apex_race := RaceScript.new()
var apex_ui: Node
var race_random := RandomNumberGenerator.new()
var records_recovered: bool = false
var enforcement := EnforcementScript.new()
var radar_display: Node3D
var braking: bool = false
var mobile_mode: bool = false
var touch_controls: Control
var _settings_dirty: bool = false
var _settings_save_remaining: float = 0.0
var run_seconds := 0.0
var heat := HeatScript.new()
var next_speed_milestone := 200
var capture_warning_active := false
var tutorial_enabled := true
var _round_settled := true
var _slow_warning_shown := false


func _ready() -> void:
	DriveInput.ensure_actions()
	tutorial_enabled = not (OS.has_feature("editor") and OS.get_cmdline_user_args().has("--no-tutorial"))
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	mobile_mode = mobile_mode or OS.has_feature("android") or OS.has_feature("ios") or OS.get_cmdline_user_args().has("--mobile-controls")
	if mobile_mode and not (OS.has_feature("android") or OS.has_feature("ios")):
		Input.emulate_touch_from_mouse = true
	run_seed = parse_run_seed(OS.get_cmdline_user_args())
	var records_error: Error = records.load_records()
	if records_error in [ERR_PARSE_ERROR, ERR_FILE_CORRUPT]:
		records_recovered = records.recover_records() == OK
	access.load_access()
	player_name = records.player_name
	_load_best_score()
	if mobile_mode:
		settings.quality = SettingsScript.Quality.LOW
		settings.effects = 0.4
		settings.shake = 0.15
	settings.load_settings()
	L.set_language("ro" if settings.language == 1 else "en")
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
	obstacles.pursuit = pursuit
	pursuit.caught.connect(_on_pursuit_caught)
	pursuit.escaped.connect(_on_pursuit_escaped)
	crash_effect = CrashScript.new()
	add_child(crash_effect)
	camera = CameraScript.new()
	add_child(camera)
	audio = AudioScript.new()
	add_child(audio)
	ui = GameUI.new()
	ui.mobile_mode = mobile_mode
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
	tutorial = TutorialScript.new()
	add_child(tutorial)
	tutorial.attach(ui, community)
	ui.secret_access_pressed.connect(community.request_access)
	community.name_submitted.connect(_on_name_submitted)
	community.secret_code_submitted.connect(_on_secret_code_submitted)
	community.resume_code_submitted.connect(_on_resume_code_submitted)
	community.leaderboard_requested.connect(_on_leaderboard_requested)
	community.set_rearview_texture(pursuit.get_rearview_texture())
	apex_ui = RaceUIScript.new()
	add_child(apex_ui)
	apex_ui.attach(ui)
	if mobile_mode:
		apex_ui.opponent_panel.offset_top = -382.0
		apex_ui.opponent_panel.offset_bottom = -192.0
	radar_display = RadarDisplayScript.new()
	add_child(radar_display)
	radar_display.attach(ui)
	if mobile_mode:
		radar_display.brake_label.text = L.text("ui.hold_brake")
	touch_controls = TouchControlsScript.new()
	touch_controls.attach(ui)
	touch_controls.set_enabled(mobile_mode)
	touch_controls.pause_pressed.connect(pause_game)
	touch_controls.boost_released.connect(_on_touch_boost_released)
	player.touch_controls = touch_controls
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
	if tutorial.active and tutorial.practice:
		_advance_tutorial_drive(delta)
		return
	if apex_race.active:
		var until_finish: float = apex_race.countdown_remaining + apex_race.remaining()
		if until_finish > 0.000000001 and delta > until_finish:
			# Finish the race before contacts and timers in the later part of a
			# delayed frame can retroactively change its outcome.
			_physics_process(until_finish)
			_physics_process(delta - until_finish)
			return
	var was_boosting := progress.boosting
	run_seconds += maxf(0.0, delta)
	heat.advance(delta, pursuit.active)
	braking = _brake_requested()
	progress.update_boost(_boost_requested() and not braking, delta, run_mode == GameMode.SECRET)
	if progress.boosting and not was_boosting:
		ui.show_feedback(L.text("game.boost_engaged"), Color("#54edff"))
	var target_speed := director.get_base_speed(distance, run_seconds)
	if progress.damage_remaining > 0.0:
		target_speed = maxf(27.0, target_speed - progress.damage_speed_loss * progress.damage_remaining / progress.POTHOLE_RECOVERY)
	if progress.boosting:
		target_speed += director.BOOST_SPEED_GAIN
	if pursuit.active:
		target_speed *= 1.0 - pursuit.slowdown_fraction * 0.12
	var previous_speed := speed
	if braking:
		target_speed = BRAKE_MIN_SPEED
	target_speed = Tuning.clamp_physical_speed(target_speed)
	speed = Tuning.clamp_physical_speed(move_toward(speed, target_speed, (BRAKE_DECELERATION if braking else (16.0 if progress.boosting else 12.0)) * delta))
	_update_ranked_pace(delta)
	var distance_delta := speed * delta
	# Detect the whole approach step before traffic can move or retire Apex.
	var race_was_active: bool = apex_race.active
	_try_begin_apex_race(distance_delta, delta)
	if apex_race.active:
		apex_race.set_difficulty(run_seconds, director.get_density(distance, run_seconds))
		# A swept trigger occurs during this approach frame. Keep that real
		# approach motion; acceleration begins on the following race tick.
		if race_was_active:
			apex_race.prepare_opponent(delta, _physical_cruise_speed(), player.position.x, obstacles.obstacle_pool, speed)
	distance += distance_delta
	progress.advance(delta, distance_delta, speed, heat.risk_multiplier(speed, pursuit.active, pursuit.capture_fraction, apex_race.active))
	road.advance(distance_delta)
	enforcement.configure_progression(speed, run_seconds, BRAKE_DECELERATION)
	var radar_event: Dictionary = enforcement.advance(distance, previous_speed, speed)
	obstacles.configure_progression(speed, run_seconds)
	obstacles.set_speed_limit(enforcement.current_limit)
	obstacles.advance(distance_delta, distance, director.get_density(distance, run_seconds), delta, player.position.x)
	# Swept road contacts can end the run during encounter advancement.
	if state != GameState.PLAYING:
		return
	var radar_started := _handle_radar(radar_event)
	_update_apex_race(delta)
	if pursuit.active:
		var pursuit_delta := delta * (1.0 - float(radar_event.get("crossing_fraction", 1.0))) if radar_started else delta
		pursuit.set_heat(heat.level())
		pursuit.advance(pursuit_delta, player.position, speed, _physical_cruise_speed(), settings.effects, obstacles.obstacle_pool)
		if state != GameState.PLAYING:
			return
	community.update_pursuit(pursuit.active, pursuit.gap_m, pursuit.get_escape_progress(), pursuit.chase_duration, pursuit.timed_chase)
	community.update_capture(heat.level(), pursuit.capture_fraction)
	var capture_critical: bool = pursuit.active and pursuit.capture_fraction >= 0.75
	if capture_critical and not capture_warning_active:
		audio.play_cue("capture")
		ui.show_feedback(L.text("game.capture_critical"), GameUI.ORANGE, 3, 2.0)
	capture_warning_active = capture_critical
	if speed * 3.6 >= next_speed_milestone:
		ui.show_feedback(L.text("game.speed_milestone", [next_speed_milestone]), GameUI.CYAN)
		next_speed_milestone += 50
	radar_display.warning_distance = enforcement.warning_distance
	radar_display.update_display(distance, enforcement.current_limit, enforcement.next_limit, enforcement.sector_at, enforcement.radar_at, enforcement.radar_pending, speed * 3.6, braking, enforcement.fine_points)
	audio.set_police(pursuit.active)
	audio.set_tension(maxf(pursuit.capture_fraction, maxf(float(heat.level()) / 4.0, 0.65 if apex_race.active else 0.0)))
	player.set_boost(progress.boosting, settings.effects)
	audio.set_driving(true, speed, progress.boosting)
	ui.update_hud(get_score(), roundi(speed * 3.6), progress.multiplier, progress.boost_charge, progress.boosting, 0.0 if run_mode == GameMode.SECRET else progress.damage_remaining)
	ui.update_hazard_warning(progress.pothole_remaining)
	ui.set_reward_boost(progress.reward_boost_remaining)
	if tutorial.active:
		tutorial.advance(delta)
	debug_refresh += delta
	if debug_refresh >= 0.25:
		debug_refresh = 0.0
		_update_debug()


func request_live_tutorial(secret: bool = false) -> void:
	if state == GameState.MENU:
		if secret and access.secret_unlocked:
			select_mode(GameMode.SECRET)
		request_start_game()
	elif state == GameState.PAUSED:
		resume_game()
		if not tutorial.active:
			tutorial.begin(false)


func complete_tutorial_handoff(snapshot: Dictionary) -> void:
	# Practice is never settled as a ranked round. Preserve its visible pose
	# while resetting scores, encounter RNG and the real round's clock.
	_round_settled = true
	start_game(false)
	tutorial.restore_handoff(snapshot)


func _update_ranked_pace(delta: float) -> void:
	var radar_approach := enforcement.radar_pending and enforcement.radar_at >= distance and enforcement.radar_at - distance <= enforcement.warning_distance
	var legal_sector := enforcement.current_limit > 0 and distance <= enforcement.sector_end
	var was_ranked: bool = progress.ranked_eligible
	progress.track_ranked_pace(delta, speed, director.get_base_speed(distance, run_seconds), radar_approach or legal_sector or progress.damage_remaining > 0.0)
	if was_ranked and not progress.ranked_eligible:
		ui.configure_ranked(false)
		ui.show_feedback(L.text("game.slow_unranked"), GameUI.ORANGE, 2, 3.0)
	elif progress.ranked_eligible and progress.slow_seconds >= 15.0 and not _slow_warning_shown:
		_slow_warning_shown = true
		ui.show_feedback(L.text("game.slow_warning"), GameUI.ORANGE, 1, 2.5)
	elif progress.slow_seconds == 0.0:
		_slow_warning_shown = false


func _advance_tutorial_drive(delta: float) -> void:
	braking = _brake_requested()
	progress.update_boost(_boost_requested() and not braking, delta, run_mode == GameMode.SECRET)
	var previous_speed := speed
	var target := 33.0 + (director.BOOST_SPEED_GAIN if progress.boosting else 0.0)
	speed = move_toward(speed, BRAKE_MIN_SPEED if braking else target, (BRAKE_DECELERATION if braking else 12.0) * delta)
	var motion := speed * delta
	distance += motion
	road.advance(motion)
	obstacles.advance(motion, distance, 0.0, delta, player.position.x)
	enforcement.configure_progression(speed, 0.0, BRAKE_DECELERATION)
	var event: Dictionary = enforcement.advance(distance, previous_speed, speed)
	tutorial.radar_checked(event)
	if pursuit.active:
		pursuit.advance(delta, player.position, speed, 12.0 if tutorial.current_step() == "escape" else 33.0, settings.effects, obstacles.obstacle_pool)
	community.update_pursuit(pursuit.active, pursuit.gap_m, pursuit.get_escape_progress())
	community.update_capture(0, pursuit.capture_fraction)
	radar_display.warning_distance = enforcement.warning_distance
	radar_display.update_display(distance, enforcement.current_limit, enforcement.next_limit, enforcement.sector_at, enforcement.radar_at, enforcement.radar_pending, speed * 3.6, braking, enforcement.fine_points)
	player.set_boost(progress.boosting, settings.effects)
	audio.set_driving(true, speed, progress.boosting)
	audio.set_police(pursuit.active)
	ui.update_hud(0, roundi(speed * 3.6), 1.0, progress.boost_charge, progress.boosting)
	tutorial.advance(delta)


func _process(delta: float) -> void:
	if _settings_dirty and _settings_save_remaining >= 0.0:
		_settings_save_remaining -= maxf(0.0, delta)
		if _settings_save_remaining <= 0.0:
			_flush_settings()
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


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventJoypadButton or not event.pressed:
		return
	if community and community.is_modal_open():
		return
	if event.is_action_pressed("drive_pause"):
		if state == GameState.PLAYING:
			pause_game()
		elif state == GameState.PAUSED:
			resume_game()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if ui.is_settings_open():
			ui._close_settings()
		elif state == GameState.PLAYING:
			pause_game()
		elif state == GameState.PAUSED:
			resume_game()
		elif state == GameState.GAME_OVER:
			return_to_menu()
		get_viewport().set_input_as_handled()


func request_start_game() -> void:
	if state == GameState.MENU:
		community.request_name(player_name)


func _on_name_submitted(raw: String) -> void:
	if state != GameState.MENU:
		return
	var normalized: String = records.display_player_name(raw)
	if normalized.is_empty():
		community.show_name_error(L.text("game.name_invalid"))
		return
	var saved: Error = records.save_player_name(raw)
	if saved in [ERR_PARSE_ERROR, ERR_FILE_CORRUPT] and records.recover_records() == OK:
		records_recovered = true
		saved = records.save_player_name(normalized)
	# A damaged or temporarily unwritable save must never lock the driver out.
	player_name = normalized
	start_game()
	if saved != OK:
		ui.show_feedback(L.text("game.name_unsaved"), GameUI.ORANGE)
	elif records_recovered:
		ui.show_feedback(L.text("game.records_recovered"), GameUI.CYAN)
		records_recovered = false


func _on_secret_code_submitted(code: String) -> void:
	if state != GameState.MENU:
		return
	if not access.unlock(code):
		community.show_access_error(L.translate_message(access.configuration_error) if not access.configuration_error.is_empty() else L.text("game.access_invalid"))
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


func start_game(with_intro: bool = true) -> void:
	var settlement := _settle_round()
	if tutorial != null:
		tutorial.cancel()
	run_seconds = 0.0
	heat.reset()
	pursuit.set_heat(0)
	next_speed_milestone = 200
	capture_warning_active = false
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
	touch_controls.clear_inputs()
	touch_controls.set_driving(true)
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
	_round_settled = false
	_slow_warning_shown = false
	ui.configure_ranked(true)
	world.set_secret_level(run_mode == GameMode.SECRET)
	ui.configure_mode(run_mode)
	camera.reset_camera()
	crash_effect.reset_effect()
	audio.stop_transients()
	audio.set_tension(0.0)
	player.reset_car()
	player.active = true
	road.reset_road()
	obstacles.reset_spawner(run_seed)
	# A separate seeded stream keeps race requirements replayable without
	# changing the traffic layouts when another challenge is encountered.
	race_random.seed = obstacles.active_seed ^ 0x41504558
	enforcement.reset(obstacles.active_seed)
	braking = false
	radar_display.reset_display()
	radar_display.update_display(distance, enforcement.current_limit, enforcement.next_limit, enforcement.sector_at, enforcement.radar_at, enforcement.radar_pending, speed * 3.6, false, 0)
	ui.update_hud(0, roundi(speed * 3.6), progress.multiplier, progress.boost_charge)
	ui.show_playing()
	ui.update_hazard_warning(0.0)
	audio.play_cue("ui")
	audio.set_driving(true, speed, false)
	_update_debug()
	if with_intro and tutorial_enabled:
		tutorial.begin(true)
	if not String(settlement.notice).is_empty():
		ui.show_feedback(settlement.notice, GameUI.ORANGE, 2, 3.0)


func return_to_menu() -> void:
	var settlement := _settle_round()
	if tutorial != null:
		tutorial.cancel()
	get_tree().paused = false
	_reset_apex_race()
	state = GameState.MENU
	touch_controls.set_driving(false)
	braking = false
	radar_display.reset_display()
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
	audio.set_tension(0.0)
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
	ui.configure_ranked(true)
	if not String(settlement.notice).is_empty():
		ui.show_feedback(settlement.notice, GameUI.ORANGE, 2, 3.0)


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
	touch_controls.set_driving(false)
	if mobile_mode:
		player.lateral_velocity = 0.0
	audio.set_driving(false, speed, false)
	audio.set_police(false)
	ui.show_paused()
	get_tree().paused = true


func resume_game() -> void:
	if state != GameState.PAUSED:
		return
	get_tree().paused = false
	state = GameState.PLAYING
	touch_controls.set_driving(true)
	ui.show_playing()
	audio.set_driving(true, speed, progress.boosting)
	audio.set_police(pursuit.active)


func get_score() -> int:
	return progress.get_score()


func _physical_cruise_speed() -> float:
	return Tuning.clamp_physical_speed(director.get_base_speed(distance, run_seconds))


func _handle_radar(event: Dictionary) -> bool:
	if event.get("warning", false):
		ui.show_feedback(L.text("game.radar_ahead", [int(event.warning_limit)]), GameUI.ORANGE, 1, 2.0)
		audio.play_cue("ui")
	if not event.get("checked", false):
		return false
	var points: int = event.get("fine", 0)
	if points <= 0:
		ui.show_feedback(L.text("game.radar_cleared"), GameUI.CYAN)
		audio.play_cue("ui")
		return false
	progress.score_penalty += points
	heat.radar_violation(float(event.get("measured_kmh", speed * 3.6)), int(event.get("limit", 80)))
	# Radar updates the pursuit without canceling an active racing challenge.
	var started: bool = not pursuit.active
	if started:
		pursuit.set_heat(heat.level())
		pursuit.begin(player.position)
	else:
		pursuit.set_heat(heat.level())
		pursuit.report_radar()
	ui.show_feedback(L.text("game.speeding_fine", [points]), GameUI.ORANGE, 2, 2.0)
	community.update_pursuit(true, pursuit.gap_m, pursuit.get_escape_progress(), pursuit.chase_duration, pursuit.timed_chase)
	audio.set_police(true)
	return started


func _on_player_hit() -> void:
	if tutorial.active and tutorial.practice:
		tutorial.retry()
		return
	var struck: RoadObstacle = obstacles.last_hit_obstacle
	if run_mode == GameMode.SECRET and state == GameState.PLAYING:
		_secret_impact(L.text("game.traffic_impact"), 1000, 30.0)
		return
	var traffic_collision := struck == null or struck.kind in [RoadObstacle.Kind.CAR, RoadObstacle.Kind.VAN, RoadObstacle.Kind.WIDE]
	_finish_run(L.text("game.traffic_collision") if traffic_collision else L.text("game.barrier_collision"), false, traffic_collision, struck)


func _on_pothole_hit() -> void:
	if state != GameState.PLAYING:
		return
	apex_race.hit_pothole()
	var before := get_score()
	if progress.hit_pothole():
		if run_mode == GameMode.SECRET:
			progress.pothole_remaining = progress.POTHOLE_WINDOW
			_secret_impact(L.text("game.repeat_pothole"), 500, progress.POTHOLE_SPEED_LOSS)
			return
		_finish_run(L.text("game.potholes_end"))
		return
	speed = minf(speed, maxf(27.0, speed - progress.POTHOLE_SPEED_LOSS))
	player.set_boost(false, settings.effects)
	camera.impact()
	audio.play_cue("pothole")
	audio.set_driving(true, speed, false)
	ui.show_feedback(L.text("game.pothole", [before - get_score()]), GameUI.ORANGE, 2)
	ui.update_hud(get_score(), roundi(speed * 3.6), progress.multiplier, progress.boost_charge, false, 0.0 if run_mode == GameMode.SECRET else progress.damage_remaining)
	ui.update_hazard_warning(progress.pothole_remaining)
	if pursuit.active:
		pursuit.register_mistake()


func _on_roadworks_entered() -> void:
	if run_mode == GameMode.SECRET and state == GameState.PLAYING:
		_secret_impact(L.text("game.worksite_violation"), 750, 26.0)
		return
	_finish_run(L.text("game.worksite_end"), true, true)


func _secret_impact(caption: String, points: int, speed_loss: float) -> void:
	var was_pursuing: bool = pursuit.active
	if apex_race.active:
		_resolve_apex_race(false)
	progress.apply_damage(points, speed_loss)
	speed = minf(speed, maxf(27.0, speed - speed_loss))
	player.set_boost(false, settings.effects)
	camera.impact()
	audio.play_cue("pothole")
	ui.show_feedback(caption + L.text("game.pursuit_suffix"), GameUI.ORANGE, 2)
	if was_pursuing and pursuit.active:
		pursuit.register_mistake()
	else:
		pursuit.set_heat(heat.level())
		pursuit.begin(player.position)
	if state == GameState.PLAYING:
		audio.set_police(true)
		community.update_pursuit(pursuit.active, pursuit.gap_m, pursuit.get_escape_progress(), pursuit.chase_duration, pursuit.timed_chase)


func _on_pursuit_caught() -> void:
	if state == GameState.PLAYING:
		_finish_run(L.text("game.busted"), false, true, null, true)


func _on_pursuit_escaped() -> void:
	if state != GameState.PLAYING:
		return
	if tutorial.active and tutorial.practice:
		tutorial.on_escape()
		return
	if run_mode == GameMode.SECRET:
		secret_escapes += 1
	progress.bonus_points += 1000
	heat.escaped()
	audio.set_police(false)
	ui.show_feedback(L.text("game.escaped"), GameUI.CYAN, 1)
	community.update_pursuit(false, 0.0, 0.0)


func _on_resume_code_submitted(code: String) -> void:
	if state != GameState.GAME_OVER or run_mode != GameMode.SECRET or run_resumed or not aftermath.active or not aftermath.arrived:
		community.show_resume_error(L.text("game.resume_wait"))
		return
	if not access.validate_resume_code(code):
		community.show_resume_error(L.translate_message(access.resume_configuration_error) if not access.resume_configuration_error.is_empty() else L.text("game.resume_invalid"))
		return
	run_resumed = true
	_round_settled = false
	ui.configure_resumed(true)
	_load_best_score(true)
	state = GameState.PLAYING
	touch_controls.clear_inputs()
	touch_controls.set_driving(true)
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
	speed = Tuning.clamp_physical_speed(director.get_base_speed(distance, run_seconds))
	camera.reset_camera()
	crash_effect.reset_effect()
	audio.stop_transients()
	audio.set_driving(true, speed, false)
	ui.show_playing()
	ui.update_hud(get_score(), roundi(speed * 3.6), progress.multiplier, progress.boost_charge)
	ui.update_hazard_warning(0.0)
	ui.show_feedback(L.text("game.resumed"), GameUI.CYAN)


func _finish_run(reason: String, invalid: bool = false, police_scene: bool = false, struck: RoadObstacle = null, pursuit_end: bool = false) -> void:
	if state != GameState.PLAYING:
		return
	if tutorial.active and tutorial.practice:
		tutorial.retry()
		return
	tutorial.cancel()
	_reset_apex_race()
	state = GameState.GAME_OVER
	touch_controls.set_driving(false)
	braking = false
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
		if invalid or run_mode == GameMode.SECRET or pursuit_end:
			aftermath.start_roadworks(player.position)
		else:
			var kind: int = struck.kind if struck else RoadObstacle.Kind.CAR
			var at: Vector3 = struck.position if struck else player.position + Vector3(0, 0, -6.3)
			aftermath.start_crash(player.position, kind, at, struck.model_id if struck else -1)
		audio.set_police(true)
	var settlement := _settle_round(true)
	var save_notice: String = settlement.notice
	if not progress.ranked_eligible:
		save_notice = L.text("game.unranked_reason")
	ui.show_game_over(get_score(), best_score, distance, progress.top_combo, progress.near_misses, settlement.new_best, reason, invalid, police_scene, save_notice)


func _settle_round(allow_empty: bool = false) -> Dictionary:
	var result := {"new_best": false, "notice": ""}
	if _round_settled or state == GameState.MENU or (tutorial != null and tutorial.active and tutorial.practice):
		return result
	_round_settled = true
	if progress.score_valid and progress.ranked_eligible and (allow_empty or get_score() > 0 or distance > 0.0):
		var score := get_score()
		var new_best := score > best_score
		best_score = maxi(best_score, score)
		best_distance = maxf(best_distance, distance)
		best_combo = maxf(best_combo, progress.top_combo)
		best_speed = maxf(best_speed, progress.top_speed)
		var saved := _save_best_score()
		result.new_best = new_best and saved.error == OK and score > saved.previous_best
		if saved.error != OK:
			result.notice = L.text("game.records_unsaved")
		elif not String(saved.get("recovered_backup", "")).is_empty():
			result.notice = L.text("game.records_backup")
		if not player_name.is_empty():
			if records.record_run(player_name, run_mode, score, distance, run_resumed, secret_escapes) != OK:
				result.notice += ("\n" if not String(result.notice).is_empty() else "") + L.text("game.leaderboard_unsaved")
	return result


func _update_apex_race(delta: float) -> void:
	if apex_race.active:
		if not is_instance_valid(apex_race.actor) or not apex_race.actor.active:
			_resolve_apex_race(false)
		else:
			var result := apex_race.advance(delta, progress.boosting)
			if result != 0:
				_resolve_apex_race(result > 0)
	else:
		_try_begin_apex_race()
	_sync_apex_ui()


func _try_begin_apex_race(distance_delta: float = 0.0, delta: float = 0.0) -> void:
	if apex_race.active:
		return
	for obstacle in obstacles.obstacle_pool:
		if not obstacle.active or obstacle.model_id != TrafficModels.Model.APEX or obstacle.pass_collided:
			continue
		var next_z: float = obstacle.position.z + distance_delta - obstacle.cruise_speed * delta
		if next_z >= -RaceScript.ENCOUNTER_DISTANCE and obstacle.position.z <= -8.0 and next_z >= obstacle.position.z:
			apex_race.begin(obstacle, _physical_cruise_speed(), race_random.randi_range(4, 7))
			apex_race.set_difficulty(run_seconds, director.get_density(distance, run_seconds))
			obstacles.begin_race(obstacle)
			apex_ui.show_challenge(obstacle.position.x, apex_race.required_boost_seconds)
			audio.play_cue("ui")
			return


func _resolve_apex_race(won: bool) -> void:
	var reason: String = "interrupted" if apex_race.active and not won else apex_race.outcome_reason
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
			pursuit.set_heat(heat.level())
			pursuit.begin(player.position)
		audio.set_police(true)
		community.update_pursuit(true, pursuit.gap_m, pursuit.get_escape_progress(), pursuit.chase_duration, pursuit.timed_chase)
	apex_ui.show_result(won, run_mode == GameMode.SECRET, reason)
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
	if tutorial.active and tutorial.practice:
		return
	var awarded := progress.reward_near_miss(points, clearance)
	var title := L.text("game.very_close") if clearance < 0.35 else L.text("game.near_miss")
	ui.show_feedback(L.text("game.near_miss_points", [title, awarded, progress.multiplier]), Color("#ffe399"))
	audio.play_cue("near_miss")


func _boost_requested() -> bool:
	if touch_controls != null and touch_controls.get_boost_requested():
		return true
	if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_SPACE):
		return true
	var joypads := Input.get_connected_joypads()
	return not joypads.is_empty() and Input.get_joy_axis(joypads[0], JOY_AXIS_TRIGGER_RIGHT) > 0.25


func _brake_requested() -> bool:
	if touch_controls != null and touch_controls.get_brake_requested():
		return true
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		return true
	var joypads := Input.get_connected_joypads()
	return not joypads.is_empty() and Input.get_joy_axis(joypads[0], JOY_AXIS_TRIGGER_LEFT) > 0.25


func _on_touch_boost_released() -> void:
	if not _boost_requested():
		progress.boost_empty_lock = false


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
	var result := {"error": ERR_BUSY, "previous_best": 0, "recovered_backup": ""}
	var lock := SaveLockScript.new()
	var acquired: Error = lock.acquire(path + ".lock")
	if acquired != OK:
		result.error = acquired
		return result
	# Merge under the lock: another open game may have finished since this run
	# started. Atomic replacement also preserves its other mode partitions.
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_PARSE_ERROR or error == ERR_FILE_CORRUPT:
		# Preserve the damaged bytes before replacing a syntactically invalid
		# ledger. Permission/storage failures must never trigger recovery.
		var backup := path + ".recovered-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()]
		while FileAccess.file_exists(backup) or DirAccess.dir_exists_absolute(backup):
			backup += "-copy"
		error = DirAccess.copy_absolute(path, backup)
		if error == OK:
			result.recovered_backup = backup
			config.clear()
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
	lock.release()
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
	_settings_dirty = true
	_settings_save_remaining = 0.35
	ui.set_settings_save_notice("")


func _flush_settings() -> void:
	if not _settings_dirty:
		return
	_settings_save_remaining = -1.0
	if settings.save_settings() != OK:
		ui.set_settings_save_notice(L.text("game.settings_unsaved"))
	else:
		_settings_dirty = false
		ui.set_settings_save_notice("")


func _apply_settings() -> void:
	ui.configure_language(settings.language)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, settings.volume)))
	AudioServer.set_bus_mute(0, settings.volume <= 0.0)
	camera.shake_strength = settings.shake
	world.set_effects(settings.effects)
	if settings.quality == SettingsScript.Quality.LOW:
		world.environment.glow_enabled = false
	get_viewport().msaa_3d = Viewport.MSAA_2X if settings.quality == SettingsScript.Quality.HIGH else Viewport.MSAA_DISABLED
	ui.set_effects(settings.effects)
	player.effects_strength = settings.effects
	if not mobile_mode and DisplayServer.get_name() != "headless":
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
	ui.set_debug("SEED %d / %.0fs / %.1fkm / TIER %d\nTARGET %.0f / SPEED %.0f / DENSITY %.2f / LOOK %.0fm\nHEAT %d / CAPTURE %.0f%% / POLICE %d / APEX %s\nENCOUNTERS %d / POOL %d / ROAD %d / FPS %d" % [obstacles.active_seed, run_seconds, distance / 1000.0, director.get_tier(run_seconds), director.get_base_speed(distance, run_seconds) * 3.6, speed * 3.6, director.get_density(distance, run_seconds), obstacles.spawn_ahead, heat.level(), pursuit.capture_fraction * 100.0, pursuit.units.size(), apex_race.ai_state, obstacles.get_active_count(), obstacles.obstacle_pool.size(), road.segments.size(), Engine.get_frames_per_second()], debug_visible and OS.has_feature("editor"))


func _quit_game() -> void:
	if quitting:
		return
	_settle_round()
	_flush_settings()
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
	elif mobile_mode and what == NOTIFICATION_WM_GO_BACK_REQUEST and ui and community:
		if community.is_modal_open():
			community.dismiss()
		elif ui.is_settings_open():
			ui._close_settings()
		elif state == GameState.PLAYING:
			pause_game()
		elif state == GameState.PAUSED:
			resume_game()
		elif state == GameState.GAME_OVER:
			return_to_menu()
		else:
			_quit_game()
	elif what in [MainLoop.NOTIFICATION_APPLICATION_PAUSED, MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_flush_settings()
		if touch_controls:
			touch_controls.clear_inputs()
		if player:
			player.lateral_velocity = 0.0
		pause_game()


static func parse_run_seed(arguments: PackedStringArray) -> int:
	for argument in arguments:
		if argument.begins_with("--seed="):
			var value := argument.trim_prefix("--seed=")
			if value.is_valid_int() and value.to_int() >= 0:
				return value.to_int()
	return -1
