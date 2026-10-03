extends SceneTree

const Progress = preload("res://scripts/run_progress.gd")
var failures: int = 0


func _initialize() -> void:
	var progress = Progress.new()
	if not progress.has_method("hit_pothole") or not progress.has_method("invalidate_score"):
		_check(false, "pothole penalties and score invalidation exist")
		quit(1)
		return
	for unlimited in [false, true]:
		progress.reset(unlimited)
		progress.distance_points = 1200.0
		progress.bonus_points = 300
		progress.multiplier = 2.0
		_check(not progress.hit_pothole(), "first pothole permits continued driving")
		_check(progress.get_score() == 1000, "first pothole deducts 500 points")
		_check(progress.multiplier == 1.0, "pothole breaks the combo")
		_check(not progress.update_boost(true, 0.1), "damage suppresses boost in both modes")
		progress.advance(9.999, 0.0, 45.0)
		_check(progress.hit_pothole(), "second hole at 9.999 seconds is fatal")
		progress.reset(unlimited)
		progress.distance_points = 1200.0
		progress.hit_pothole()
		progress.advance(10.0, 0.0, 45.0)
		_check(not progress.hit_pothole(), "a hit exactly ten seconds later starts a new window")
		_check(progress.get_score() == 200, "separate first hits deduct separately")
		progress.reset(unlimited)
		progress.hit_pothole()
		for tick in range(240):
			progress.advance(1.0 / 60.0, 0.0, 45.0)
		_check(progress.damage_remaining == 0.0, "four-second recovery ends on tick 240 at 60 Hz")
		for tick in range(360):
			progress.advance(1.0 / 60.0, 0.0, 45.0)
		_check(not progress.hit_pothole(), "ten-second boundary holds after 600 individual physics ticks")
		progress.reset(unlimited)
		progress.distance_points = 100.0
		progress.hit_pothole()
		_check(progress.get_score() == 0, "low score clamps at zero")
		progress.advance(1.0, 10.0, 27.0)
		_check(progress.get_score() == 100, "low-score penalty does not consume future points")
		progress.invalidate_score()
		progress.advance(1.0, 100.0, 62.0)
		_check(not progress.score_valid and progress.get_score() == 0, "invalid score stays invalid")
		progress.reset(unlimited)
		_check(progress.score_valid and progress.pothole_remaining == 0.0 and progress.damage_remaining == 0.0, "restart clears penalty and violation state")
	if failures == 0:
		print("HAZARD RULES PASS: score clamp, 10-second boundary, recovery boost lock, invalidation and both modes")
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("HAZARD RULES FAIL: " + label)
