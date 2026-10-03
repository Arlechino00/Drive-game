class_name CrashEffect
extends CPUParticles3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	emitting = false
	visible = false
	one_shot = true
	amount = 28
	lifetime = 0.42
	explosiveness = 0.95
	direction = Vector3(0.0, 1.0, 0.0)
	spread = 75.0
	gravity = Vector3(0.0, -12.0, 0.0)
	initial_velocity_min = 3.0
	initial_velocity_max = 7.0
	scale_amount_min = 0.4
	scale_amount_max = 1.0
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.055, 0.055, 0.24)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#ffd28e")
	material.emission_enabled = true
	material.emission = Color("#ffb968")
	material.emission_energy_multiplier = 1.7
	spark_mesh.material = material
	# CPUParticles3D uses a single pooled mesh for all sparks.
	mesh = spark_mesh


func trigger(at_position: Vector3, effects: float) -> void:
	if effects <= 0.0:
		return
	global_position = at_position + Vector3(0.0, 0.65, -1.1)
	visible = true
	restart()
	emitting = true


func reset_effect() -> void:
	emitting = false
	visible = false
