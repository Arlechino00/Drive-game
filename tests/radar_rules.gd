extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ResourceLoader.exists("res://scripts/speed_enforcement.gd"):
		_check(false, "speed-sector and radar rules exist")
		quit(1)
		return
	var rules = load("res://scripts/speed_enforcement.gd").new()
	var camera_seed := 42
	rules.reset(camera_seed)
	while not rules.radar_pending:
		camera_seed += 1
		rules.reset(camera_seed)
	_check(rules.current_limit == 0, "run starts on an unlimited sector")
	_check(rules.sector_at >= 600.0 and rules.next_limit in [30, 50, 70, 80, 90, 120, 130, 200], "first restricted sector supports the full limit catalog")
	_check(rules.radar_at - rules.sector_at >= 80.0, "radar is inside restricted sector")
	var first_sector: float = rules.sector_at
	var first_radar: float = rules.radar_at
	var first_limit: int = rules.next_limit
	_check(not rules.advance(first_radar - rules.WARNING_DISTANCE - 1.0, 80.0, 80.0).get("warning", false), "radar stays unreported before the warning radius")
	_check(rules.advance(first_radar - rules.WARNING_DISTANCE, 80.0, 80.0).get("warning", false), "audible warning fires at a fixed camera distance")
	_check(not rules.advance(first_sector - 1.0, 80.0, 80.0).get("warning", false), "warning is announced once per trap")
	rules.advance(first_sector, 80.0, 80.0)
	_check(rules.current_limit == first_limit, "limit activates exactly at sign")
	var safe: Dictionary = rules.advance(first_radar, float(first_limit) / 3.6, float(first_limit) / 3.6)
	_check(safe.get("checked", false) and safe.get("fine", -1) == 0, "exact-limit pass avoids fine")
	_check(not rules.radar_pending and rules.fine_points == 0, "one safe check consumes the radar")
	_check(not rules.advance(first_radar + 1.0, 80.0, 80.0).get("checked", false), "passing same radar cannot award twice")
	rules.reset(camera_seed)
	var fine: Dictionary = rules.advance(first_radar + 1.0, 80.0, 80.0)
	_check(fine.get("fine", 0) > 0 and rules.fine_points == fine.get("fine", 0), "speeding awards cumulative fine points")
	_check(fine.get("chase_seconds", 0.0) >= 8.0 and fine.get("chase_seconds", 17.0) <= 16.0, "radar chooses chase duration within eight to sixteen seconds")
	var previous_end: float = rules.sector_end
	_check(rules.advance(previous_end, 80.0, 80.0).get("fine", 0) == 0 and rules.current_limit == 0, "sector returns to unlimited")
	_check(rules.sector_at - previous_end >= rules.WARNING_DISTANCE, "next trap leaves another complete warning window")
	var replay = load("res://scripts/speed_enforcement.gd").new()
	replay.reset(camera_seed)
	var same: Dictionary = replay.advance(first_radar + 1.0, 80.0, 80.0)
	_check(same == fine, "seed reproduces fine and pursuit length")
	var limits := {}
	var sectors_without_radar := 0
	var durations := {}
	for seed_value in range(300):
		rules.reset(seed_value)
		limits[rules.next_limit] = true
		if not rules.radar_pending:
			sectors_without_radar += 1
			_check(not rules.advance(rules.sector_end - 1.0, 80.0, 80.0).get("checked", false) and rules.fine_points == 0, "speeding without a radar causes no fine")
			continue
		var event: Dictionary = rules.advance(rules.radar_at + 1.0, 80.0, 80.0)
		durations[event.chase_seconds] = true
	_check(limits.size() == 8 and durations.size() > 10 and sectors_without_radar > 0, "seeded variety includes all limits, occasional cameras and varied chase durations")
	for limit in [30, 50, 70, 80, 90, 120, 130, 200]:
		rules.reset(camera_seed)
		rules.next_limit = limit
		var legal: Dictionary = rules.advance(rules.radar_at, float(limit) / 3.6, float(limit) / 3.6)
		_check(legal.get("checked", false) and legal.fine == 0, "exact %d km/h radar reading is legal" % limit)
	# Driving choices and fine duration draws must not move later sector signs.
	rules.reset(camera_seed)
	replay.reset(camera_seed)
	var end_distance: float = rules.sector_end
	rules.advance(end_distance, 80.0, 80.0)
	replay.advance(end_distance, 8.0, 8.0)
	_check(rules.next_limit == replay.next_limit and rules.sector_at == replay.sector_at and rules.radar_at == replay.radar_at, "sector layout is independent of whether driver paid a fine")
	# The radar samples speed at its swept crossing, not the end of a delayed tick.
	rules.reset(camera_seed)
	rules.advance(first_radar - 1.0, 80.0, 80.0)
	var swept: Dictionary = rules.advance(first_radar + 79.0, 80.0, 8.0)
	_check(swept.get("fine", 0) > 0, "braking after a swept radar crossing cannot evade the reading")
	print("RADAR RULES PASS" if failures == 0 else "RADAR RULES FAIL: %d" % failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
