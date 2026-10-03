extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var Progress = load("res://scripts/run_progress.gd")
	if Progress == null:
		quit(1)
		return
	var progress = Progress.new()
	progress.reset()
	progress.advance(1.0, 10.0, 31.0)
	_check(progress.get_score() == 100, "survival distance remains valuable")
	progress.reward_near_miss(100, 0.7)
	_check(progress.multiplier == 1.5 and progress.near_misses == 1, "near miss raises combo once")
	_check(progress.get_score() == 250, "near-miss points use combo")
	_check(progress.boost_charge > 0.4, "risk earns boost")
	var meter: float = progress.boost_charge
	_check(progress.update_boost(true, 0.2), "charged boost activates")
	_check(progress.boost_charge < meter, "boost consumes charge")
	for step in range(30):
		progress.update_boost(true, 0.2)
	_check(not progress.boosting and progress.boost_charge == 0.0, "empty boost stays off while held")
	progress.advance(5.0, 0.0, 31.0)
	_check(progress.multiplier == 1.0, "quiet driving expires combo")
	_check(progress.top_combo == 1.5, "run keeps highest combo")
	progress.reset()
	_check(progress.get_score() == 0 and progress.near_misses == 0 and progress.top_combo == 1.0, "restart clears run state")
	_check(progress.boost_charge == 0.4 and not progress.boosting, "restart replenishes starter boost")
	for pass_number in range(20):
		progress.reward_near_miss(250, 0.2)
	_check(progress.multiplier <= 5.0 and progress.boost_charge <= 1.0, "combo and charge cap")
	var score_before_crash: int = progress.get_score()
	progress.crash()
	_check(progress.multiplier == 1.0 and not progress.boosting, "crash stops combo and boost")
	_check(progress.get_score() == score_before_crash, "crash preserves final score")
	if failures == 0:
		print("PROGRESSION PASS: rewards, combo expiry/cap, boost drain/reset, crash")
	quit(1 if failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("PROGRESSION FAIL: " + label)
