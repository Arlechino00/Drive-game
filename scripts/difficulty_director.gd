class_name DifficultyDirector
extends RefCounted

# Historical reference constants remain for tools/old fixtures, not speed caps.
const Tuning = preload("res://scripts/stage_two_tuning.gd")
const INITIAL_SPEED: float = Tuning.OPENING_KMH / 3.6
const MAX_CRUISE_SPEED: float = 62.0
const BOOST_SPEED_GAIN: float = 38.0
const MAX_BOOST_SPEED: float = 100.0


func get_base_speed(distance: float, survival_seconds: float = -1.0) -> float:
	var distance_time := maxf(0.0, distance) / Tuning.DISTANCE_REFERENCE_SPEED
	var driving_time := distance_time if survival_seconds < 0.0 else maxf(0.0, survival_seconds)
	var minutes := (driving_time * (1.0 - Tuning.DISTANCE_WEIGHT) + distance_time * Tuning.DISTANCE_WEIGHT) / 60.0
	# Smooth diminishing early gain plus a gentle endless tail: no practical cap.
	return (Tuning.OPENING_KMH + Tuning.CURVE_GAIN_KMH * (1.0 - exp(-minutes / Tuning.CURVE_MINUTES)) + Tuning.ENDLESS_KMH_PER_MINUTE * minutes) / 3.6


func get_tier(survival_seconds: float) -> int:
	return maxi(0, floori(survival_seconds / 300.0))


func get_look_ahead(speed: float) -> float:
	# Shared spatial budget covers long-run cruise plus boost; pool is finite.
	return clampf(maxf(Tuning.LOOK_AHEAD_BASE, speed * Tuning.LOOK_AHEAD_SECONDS), Tuning.LOOK_AHEAD_BASE, Tuning.LOOK_AHEAD_MAX)


func get_density(distance: float, survival_seconds: float = -1.0) -> float:
	if distance < 250.0:
		return 0.08
	# Smooth density waves create recovery windows without also dropping speed.
	var wave := 0.5 + 0.5 * sin((distance - 250.0) * TAU / 1400.0)
	var seconds := distance / Tuning.DISTANCE_REFERENCE_SPEED if survival_seconds < 0.0 else survival_seconds
	var pressure := 1.0 - exp(-maxf(0.0, seconds) / 1100.0)
	return lerpf(0.08, 0.3 + pressure * 0.3 + wave * 0.4, clampf((distance - 250.0) / 8000.0, 0.0, 1.0))


func get_wave_name(distance: float) -> String:
	if distance < 250.0:
		return "WARM UP"
	var wave := sin((distance - 250.0) * TAU / 1400.0)
	if wave > 0.5:
		return "SURGE"
	if wave < -0.35:
		return "RECOVERY"
	return "CRUISE"
