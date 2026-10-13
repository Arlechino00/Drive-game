extends RefCounted
## Run-only heat is independent of radar RNG and never changes saved scores.

const Tuning = preload("res://scripts/stage_two_tuning.gd")
var value := 0.0
var violations := 0
var quiet_seconds := 0.0

func reset() -> void:
	value = 0.0
	violations = 0
	quiet_seconds = 0.0

func radar_violation(kmh: float, limit: int) -> int:
	violations += 1
	quiet_seconds = 0.0
	var severity := 1
	if kmh >= 330.0:
		severity = 4
	elif kmh >= 280.0:
		severity = 3
	elif kmh >= 225.0:
		severity = 2
	var excess := maxf(0.0, kmh - limit)
	value = minf(Tuning.HEAT_MAX, value + severity * 0.65 + minf(0.6, excess / 300.0) + minf(0.6, violations * 0.1))
	return level()

func advance(delta: float, pursuing: bool) -> void:
	quiet_seconds += maxf(0.0, delta)
	if not pursuing and quiet_seconds > Tuning.HEAT_DECAY_SECONDS:
		value = maxf(0.0, value - maxf(0.0, delta) * Tuning.HEAT_DECAY_RATE)

func escaped() -> void:
	value = maxf(0.0, value - 0.75)
	quiet_seconds = 0.0

func level() -> int:
	return clampi(ceili(value), 0, Tuning.HEAT_MAX)

func risk_multiplier(speed: float, pursuing: bool, capture: float, apex_active: bool) -> float:
	var speed_risk := maxf(0.0, speed * 3.6 - 170.0) / 130.0
	return 1.0 + minf(2.5, speed_risk) + value * 0.1 + (0.35 + clampf(capture, 0.0, 1.0) * 0.45 if pursuing else 0.0) + (0.25 if apex_active else 0.0)
