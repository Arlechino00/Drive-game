extends SceneTree

const Spawner = preload("res://scripts/obstacle_spawner.gd")
const Models = preload("res://scripts/traffic_models.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var spawner := Spawner.new()
	root.add_child(spawner)
	spawner.reset_spawner(7)
	spawner.spawning_enabled = false
	for obstacle in spawner.obstacle_pool:
		obstacle.deactivate()
	spawner.configure_progression(40.0, 0.0)
	var bike: RoadObstacle = spawner._take_obstacle()
	bike.activate(Vector3(5.0, 0.0, -200.0), Models.kind_for_model(Models.Model.MOTO), 0.0, Models.Model.MOTO)
	_check(bike.visible and bike._model_visuals[Models.Model.MOTO].find_child("RiderHelmet", true, false) != null, "motorcycle carries a helmeted rider")
	var cut_at := INF
	for frame in range(600):
		spawner.advance(40.0 / 60.0, 0.0, 0.0, 1.0 / 60.0, 0.0)
		if cut_at == INF and is_equal_approx(bike.lane_target, 0.0):
			cut_at = -bike.position.z
	_check(cut_at >= 20.0 and cut_at <= 120.0, "motorcycle cuts into the player's lane with reaction distance (%.1f m)" % cut_at)
	spawner.free()
	if failures == 0:
		print("MOTORCYCLE PASS")
	quit(1 if failures else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("MOTORCYCLE FAIL: " + message)
