extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := VisualWorld.new()
	root.add_child(world)
	await process_frame
	if not world.has_method("set_secret_level"):
		push_error("SECRET WORLD FAIL: distinct Secret lighting exists")
		world.free()
		quit(1)
		return
	var original_ambient: Color = world.environment.ambient_light_color
	var original_energy: float = world.environment.ambient_light_energy
	var original_nodes := world.get_child_count()
	world.set_effects(0.3)
	for cycle in range(200):
		world.set_secret_level(true)
		_check(world.secret_level and world.sun_material.get_shader_parameter("secret_amount") == 1.0, "blue palette enabled")
		_check(world.environment.ambient_light_energy >= 0.75 and world.environment.fog_density <= 0.002, "hazard visibility retained")
		world.set_secret_level(false)
		_check(world.environment.ambient_light_color == original_ambient and world.environment.ambient_light_energy == original_energy, "ordinary lighting restored")
		_check(world.sun_material.get_shader_parameter("secret_amount") == 0.0, "ordinary sun restored")
	_check(world.get_child_count() == original_nodes and world.effects_amount == 0.3, "bounded resources and effects retained")
	world.free()
	if failures == 0:
		print("SECRET WORLD PASS: blue night palette, clear hazards, original-theme restore, preserved effects and bounded reuse")
	quit(1 if failures else 0)


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("SECRET WORLD FAIL: " + label)
