extends SceneTree

const Race = preload("res://scripts/apex_race.gd")
const Models = preload("res://scripts/traffic_models.gd")
const Progress = preload("res://scripts/run_progress.gd")
var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_race_rules()
	_test_reward()
	_test_spawn_catalog()
	await _test_integration()
	if failures == 0:
		print("APEX RACE PASS: seeded random 4-7s targets, actual 30s opponent win/loss, seven seconds of earned-fuel boost, clean requirements, rare catalog, reward expiry/fuel preservation, all-mode outcomes, pause, reset and pooled reuse")
	quit(1 if failures else 0)


func _test_race_rules() -> void:
	var actor := RoadObstacle.new()
	root.add_child(actor)
	for fixture in [{"boost": 0.0, "clean": true, "lead": 50.0, "required": 4.0, "result": -1}, {"boost": 3.99, "clean": true, "lead": 50.0, "required": 4.0, "result": -1}, {"boost": 4.0, "clean": false, "lead": 50.0, "required": 4.0, "result": -1}, {"boost": 4.0, "clean": true, "lead": 0.0, "required": 4.0, "result": -1}, {"boost": 4.0, "clean": true, "lead": -1.0, "required": 4.0, "result": -1}, {"boost": 4.0, "clean": true, "lead": 1.0, "required": 4.0, "result": 1}, {"boost": 6.99, "clean": true, "lead": 50.0, "required": 7.0, "result": -1}, {"boost": 7.0, "clean": true, "lead": 1.0, "required": 7.0, "result": 1}]:
		actor.activate(Vector3(-5, 0, -13), 3, 0, Models.Model.APEX)
		var race := Race.new()
		race.begin(actor, 62.0, fixture.required)
		_check(actor.racing and actor.cruise_speed == 63.0, "Apex changes from traffic to race speed")
		_check(race.advance(10.0, false) == 0 and race.remaining() == 20.0, "race does not resolve early")
		race.boost_seconds = fixture.boost
		if not fixture.clean:
			race.hit_pothole()
		actor.position.z = fixture.lead
		_check(race.advance(20.0, false) == fixture.result, "finish requires actual lead, boost and no potholes: %s" % fixture)
		_check(not race.active and race.advance(1.0, true) == 0, "each race resolves once")
		race.reset()
		_check(not actor.racing and race.actor == null and race.clean and race.boost_seconds == 0.0, "race reset clears requirements and actor")
	actor.free()


func _test_reward() -> void:
	var progress := Progress.new()
	progress.reset()
	progress.boost_charge = 0.0
	progress.boost_empty_lock = true
	progress.grant_race_reward()
	for tick in range(600):
		_check(progress.update_boost(true, 1.0 / 60.0), "reward enables every tick with no fuel")
	_check(progress.reward_boost_remaining == 0.0 and progress.boost_charge == 0.0, "reward expires after exactly ten driving seconds")
	_check(not progress.update_boost(true, 1.0 / 60.0), "empty fuel cannot boost after reward expiry")
	progress.reset()
	progress.boost_charge = 0.6
	progress.grant_race_reward(0.5)
	progress.update_boost(true, 0.75)
	_check(is_equal_approx(progress.boost_charge, 0.6 - 0.25 * progress.BOOST_DRAIN), "expiry tick drains only paid portion")
	progress.reset()
	progress.grant_race_reward()
	progress.damage_remaining = 4.0
	_check(not progress.update_boost(true, 2.0) and progress.reward_boost_remaining == 8.0, "damage preserves ordinary boost restriction while reward time advances")
	_check(progress.update_boost(true, 1.0, true), "Secret damaged driver can use free reward")
	progress.reset(true)
	progress.grant_race_reward()
	progress.update_boost(true, 11.0)
	_check(progress.infinite_boost and progress.boosting and progress.reward_boost_remaining == 0.0, "reward expiry preserves Infinite mode")
	progress.reset()
	_check(progress.reward_boost_remaining == 0.0, "restart clears reward")


func _test_spawn_catalog() -> void:
	var spawner := ObstacleSpawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(741)
	for actor in spawner.obstacle_pool:
		actor.deactivate()
	var seen: Dictionary = {}
	var apex_count := 0
	for index in range(600):
		spawner._total_run_distance = index * 10000.0
		spawner._activate_encounter(0, -100, 10.0, -1)
		var actor: RoadObstacle = spawner.obstacle_pool[0]
		seen[actor.model_id] = true
		if actor.model_id == Models.Model.APEX:
			apex_count += 1
		actor.deactivate()
	_check(seen.size() == 10 and apex_count >= 20 and apex_count <= 60, "all ten designs spawn; Apex appears more often but remains uncommon")
	print("APEX CATALOG: %d Apex encounters in 600 eligible draws" % apex_count)
	spawner.reset_spawner(741)
	for actor in spawner.obstacle_pool:
		actor.deactivate()
	spawner._total_run_distance = spawner.APEX_FIRST_DISTANCE
	_check(_draw_apex(spawner), "Apex becomes eligible after warmup")
	var next_distance: float = spawner._next_apex_distance
	_check(next_distance == spawner.APEX_FIRST_DISTANCE + 2500.0, "Apex spacing is now 2500 meters")
	spawner._total_run_distance = next_distance - 0.001
	_check(not _draw_apex(spawner), "Apex spacing excludes early duplicate encounters")
	spawner._total_run_distance = next_distance
	_check(_draw_apex(spawner), "Apex becomes eligible at the exact spacing boundary")
	var racer: RoadObstacle = spawner.obstacle_pool[0]
	racer.activate(Vector3(-5, 0, -13), 3, 0, Models.Model.APEX)
	spawner.begin_race(racer)
	spawner._total_run_distance = 1000000.0
	_check(not _draw_apex(spawner), "an active race prevents additional Apex spawns")
	spawner.finish_race()
	spawner.reset_spawner(741)
	spawner._total_run_distance = 1700.0
	for actor in spawner.obstacle_pool:
		actor.deactivate()
	for index in range(500):
		spawner._activate_encounter(0, -100, 10.0, -1)
		var actor: RoadObstacle = spawner.obstacle_pool[0]
		_check(actor.model_id != Models.Model.APEX, "Apex cannot spawn in opening warmup")
		actor.deactivate()
	spawner.free()


func _draw_apex(spawner: ObstacleSpawner) -> bool:
	for draw in range(400):
		spawner._activate_encounter(0, -100, 10.0, -1)
		var found := false
		for actor in spawner.obstacle_pool:
			if actor == spawner.race_actor or not actor.active:
				continue
			found = found or actor.model_id == Models.Model.APEX
			actor.deactivate()
		if found:
			return true
	return false


func _test_integration() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game.run_seed = 321
	game.obstacles.spawning_enabled = false
	# Requirements vary per encounter, repeat with the run seed, and leave the
	# traffic generator's random stream untouched.
	var targets: Array[int] = []
	var seen: Dictionary = {}
	for replay in range(2):
		game.start_game()
		var traffic_state: int = game.obstacles.random.state
		for encounter in range(64):
			_clear(game)
			var rival := game.obstacles._take_obstacle() as RoadObstacle
			rival.activate(Vector3(-5, 0, -13), 3, 0, Models.Model.APEX)
			game._update_apex_race(0.0)
			var required: int = roundi(game.apex_race.required_boost_seconds)
			_check(required >= 4 and required <= 7, "random requirement stays within four to seven seconds")
			if replay == 0:
				targets.append(required)
				seen[required] = true
			else:
				_check(required == targets[encounter], "race requirements replay with the run seed")
			game._reset_apex_race()
		_check(game.obstacles.random.state == traffic_state, "race draw preserves the traffic random stream")
	_check(seen.size() == 4, "seeded encounters draw all four possible boost targets")
	for mode in range(3):
		game.start_game()
		_clear(game)
		game.run_mode = mode
		game.progress.reset(mode == 1)
		game.distance = 2000.0
		game.speed = 62.0
		var actor := game.obstacles._take_obstacle() as RoadObstacle
		actor.activate(Vector3(-5, 0, -13), 3, 0, Models.Model.APEX)
		game._update_apex_race(0.0)
		_check(game.apex_race.active and game.apex_ui.notification_panel.visible, "meeting physical Apex starts challenge in mode %d" % mode)
		game.pause_game()
		var frozen: float = game.apex_race.remaining()
		game._physics_process(5.0)
		_check(game.apex_race.remaining() == frozen and actor.position.z == -13.0, "pause freezes race and opponent")
		game.resume_game()
		# No boost: the real opponent pulls away for the entire thirty seconds.
		for tick in range(1800):
			game._physics_process(1.0 / 60.0)
		_check(not game.apex_race.active and game.apex_ui.notification_title.text == "APEX WINS", "Apex wins a real unboosted thirty-second race")
		_check(game.state == game.GameState.PLAYING and game.pursuit.active == (mode == 2), "loss starts police only in Secret mode")
		_check(game.progress.reward_boost_remaining == 0.0 and game.progress.bonus_points == 0, "loss grants no points or free boost")
		game.start_game()
		_clear(game)
		game.run_mode = mode
		game.progress.reset(mode == 1)
		game.progress.boost_charge = 1.0
		game.distance = 2000.0
		game.speed = 62.0
		actor = game.obstacles._take_obstacle()
		actor.activate(Vector3(-5, 0, -13), 3, 0, Models.Model.APEX)
		game._update_apex_race(0.0)
		_key(true)
		for tick in range(420):
			if tick in [60, 120, 180, 240]:
				var close_pass := game.obstacles._take_obstacle() as RoadObstacle
				close_pass.activate(Vector3(2.85, 0, -6), RoadObstacle.Kind.CAR, 0.0, Models.Model.PULSE)
			game._physics_process(1.0 / 60.0)
			# Real swept close passes award fuel on the deferred signal queue.
			await process_frame
		_key(false)
		var close_pass_points: int = game.progress.bonus_points
		_check(mode == 1 or game.progress.near_misses == 4, "four real close passes replenish finite boost fuel")
		_check(game.apex_race.boost_seconds >= 7.0 - 0.000001, "earned fuel supports the maximum seven-second requirement")
		for tick in range(1380):
			game._physics_process(1.0 / 60.0)
		_check(game.apex_ui.notification_title.text == "APEX DEFEATED" and not game.pursuit.active, "actual charged boost wins clean race in mode %d" % mode)
		_check(game.progress.bonus_points == close_pass_points + Race.POINTS and is_equal_approx(game.progress.reward_boost_remaining, 10.0), "win grants exactly one score bonus and ten seconds")
		var saved_fuel: float = game.progress.boost_charge
		_key(true)
		for tick in range(300):
			game._physics_process(1.0 / 60.0)
		_key(false)
		_check(mode == 1 or is_equal_approx(game.progress.boost_charge, saved_fuel), "winning free boost preserves finite fuel")
		game.pause_game()
		var saved_reward: float = game.progress.reward_boost_remaining
		game._physics_process(5.0)
		_check(game.progress.reward_boost_remaining == saved_reward, "pause freezes reward")
		game.resume_game()
		game.start_game()
		_check(not game.apex_race.active and game.obstacles.race_actor == null and game.progress.reward_boost_remaining == 0.0, "restart clears race actor and reward")
	game.start_game()
	_clear(game)
	var pothole_actor := game.obstacles._take_obstacle() as RoadObstacle
	pothole_actor.activate(Vector3(-5, 0, -13), 3, 0, Models.Model.APEX)
	game._update_apex_race(0.0)
	game._on_pothole_hit()
	_check(not game.apex_race.clean and game.apex_race.active, "first pothole permanently disqualifies race while ordinary driving continues")
	game.apex_race.boost_seconds = 5.0
	pothole_actor.position.z = 20.0
	game._update_apex_race(30.0)
	_check(game.apex_ui.notification_title.text == "APEX WINS", "pothole blocks reward even after recovering and finishing ahead")
	game.return_to_menu()
	_check(not game.apex_ui.race_panel.visible and not game.apex_ui.reward_panel.visible, "menu clears quest overlays")
	game.audio.stop_all()
	# The manual thirty-second simulations can yield a large engine delta;
	# audio playback drains on real time rather than that simulation clock.
	var drain_until := Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < drain_until:
		await process_frame
	game.free()
	await process_frame


func _clear(game: Node) -> void:
	for actor in game.obstacles.obstacle_pool:
		actor.deactivate()


func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("APEX RACE FAIL: " + label)
