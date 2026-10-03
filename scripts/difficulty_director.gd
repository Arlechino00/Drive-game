class_name DifficultyDirector
extends RefCounted

const INITIAL_SPEED: float = 45.0
const MAX_CRUISE_SPEED: float = 62.0
const BOOST_SPEED_GAIN: float = 18.0
const MAX_BOOST_SPEED: float = 80.0


func get_base_speed(distance: float) -> float:
	return lerpf(INITIAL_SPEED, MAX_CRUISE_SPEED, clampf(distance / 650.0, 0.0, 1.0))


func get_density(distance: float) -> float:
	if distance < 250.0:
		return 0.08
	# Smooth density waves create recovery windows without also dropping speed.
	var wave := 0.5 + 0.5 * sin((distance - 250.0) * TAU / 1400.0)
	return lerpf(0.08, 0.3 + wave * 0.7, clampf((distance - 250.0) / 1750.0, 0.0, 1.0))


func get_wave_name(distance: float) -> String:
	if distance < 250.0:
		return "WARM UP"
	var wave := sin((distance - 250.0) * TAU / 1400.0)
	if wave > 0.5:
		return "SURGE"
	if wave < -0.35:
		return "RECOVERY"
	return "CRUISE"
