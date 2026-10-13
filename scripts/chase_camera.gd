class_name ChaseCamera
extends Camera3D

const Director = preload("res://scripts/difficulty_director.gd")
var shake_strength: float = 0.35
var impact_remaining: float = 0.0
var elapsed: float = 0.0
var follow_x: float = 0.0
var lean: float = 0.0


func _ready() -> void:
	current = true
	far = 650.0
	# The rival screen can extend road scenery beyond the recycled main view.
	# Its presentation layer must not appear in the player's driving camera.
	cull_mask &= ~(1 << 19)
	reset_camera()


func reset_camera() -> void:
	far = 650.0
	follow_x = 0.0
	lean = 0.0
	impact_remaining = 0.0
	fov = 74.0
	position = Vector3(0.0, 5.2, 12.8)
	look_at(Vector3(0.0, 1.0, -22.0), Vector3.UP)


func impact() -> void:
	impact_remaining = 0.32


func follow(delta: float, player_x: float, steering: float, speed: float, boosting: bool, rival_z: float = NAN) -> void:
	# Render only the current preview, while the larger recycled ring remains
	# ready for long runs. Opening speed should not draw the whole late-run road.
	far = maxf(650.0, clampf(speed * Director.Tuning.LOOK_AHEAD_SECONDS, Director.Tuning.LOOK_AHEAD_BASE, Director.Tuning.LOOK_AHEAD_MAX) + 80.0)
	elapsed += delta
	impact_remaining = maxf(0.0, impact_remaining - delta)
	follow_x = lerpf(follow_x, player_x * 0.48, 1.0 - exp(-4.5 * delta))
	lean = lerpf(lean, -steering * 0.0018, 1.0 - exp(-5.0 * delta))
	var cruise_ratio := 1.0 - exp(-maxf(0.0, speed - Director.INITIAL_SPEED) / 65.0)
	var target_fov := 74.0 + cruise_ratio * 17.0 + (5.0 if boosting else 0.0)
	fov = lerpf(fov, target_fov, 1.0 - exp(-3.5 * delta))
	var target_z := 13.8 if boosting else 12.8
	# Keep a nearby trailing rival in the driving view. Beyond 24 m the live
	# opponent screen takes over, so the main view remains useful for steering.
	if not is_nan(rival_z):
		var near_weight := clampf((50.0 - rival_z) / 26.0, 0.0, 1.0)
		target_z = maxf(target_z, minf(24.0, maxf(0.0, rival_z)) * near_weight + 14.0)
	var camera_z := lerpf(position.z, target_z, 1.0 - exp(-3.5 * delta))
	position = Vector3(follow_x, 5.2 + maxf(0.0, camera_z - 13.8) * 0.1, camera_z)
	# Tiny high-speed vibration stays below the impact shake and respects settings.
	var wind_shake := cruise_ratio * 0.035 * shake_strength
	position.x += sin(elapsed * 29.0) * wind_shake
	position.y += sin(elapsed * 37.0) * wind_shake * 0.5
	if impact_remaining > 0.0 and shake_strength > 0.0:
		var amplitude := impact_remaining * 0.65 * shake_strength
		position.x += sin(elapsed * 83.0) * amplitude
		position.y += sin(elapsed * 67.0) * amplitude * 0.6
	look_at(Vector3(player_x * 0.6, 1.0, -22.0), Vector3.UP)
	rotation.z += lean
