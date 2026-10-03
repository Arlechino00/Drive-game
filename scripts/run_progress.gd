class_name RunProgress
extends RefCounted

const COMBO_TIMEOUT: float = 4.5
const MAX_MULTIPLIER: float = 5.0
const BOOST_DRAIN: float = 0.27
const STARTER_BOOST: float = 0.4
const POTHOLE_SCORE_LOSS: int = 500
const POTHOLE_SPEED_LOSS: float = 18.0
const POTHOLE_WINDOW: float = 10.0
const POTHOLE_RECOVERY: float = 4.0

var multiplier: float = 1.0
var top_combo: float = 1.0
var near_misses: int = 0
var boost_charge: float = STARTER_BOOST
var boosting: bool = false
var top_speed: float = 0.0
var distance_points: float = 0.0
var bonus_points: int = 0
var combo_remaining: float = 0.0
var boost_empty_lock: bool = false
var infinite_boost: bool = false
var score_valid: bool = true
var score_penalty: int = 0
var pothole_remaining: float = 0.0
var damage_remaining: float = 0.0
var damage_speed_loss: float = POTHOLE_SPEED_LOSS
var reward_boost_remaining: float = 0.0
var unlimited_this_tick: bool = false


func reset(unlimited: bool = false) -> void:
	multiplier = 1.0
	top_combo = 1.0
	near_misses = 0
	infinite_boost = unlimited
	boost_charge = 1.0 if unlimited else STARTER_BOOST
	boosting = false
	top_speed = 0.0
	distance_points = 0.0
	bonus_points = 0
	combo_remaining = 0.0
	boost_empty_lock = false
	score_valid = true
	score_penalty = 0
	pothole_remaining = 0.0
	damage_remaining = 0.0
	damage_speed_loss = POTHOLE_SPEED_LOSS
	reward_boost_remaining = 0.0
	unlimited_this_tick = false


func advance(delta: float, distance_delta: float, speed: float) -> void:
	pothole_remaining = _advance_timer(pothole_remaining, delta)
	damage_remaining = _advance_timer(damage_remaining, delta)
	combo_remaining = maxf(0.0, combo_remaining - delta)
	if is_zero_approx(combo_remaining):
		multiplier = 1.0
	# Survival stays the main score source; risky chains add a modest distance bonus.
	distance_points += distance_delta * 10.0 * (1.0 + (multiplier - 1.0) * 0.1)
	top_speed = maxf(top_speed, speed)


func _advance_timer(remaining: float, delta: float) -> float:
	var result := remaining - delta
	# Discard floating-point residue at the exact 4s/10s physics-tick boundary.
	return result if result > 0.000000001 else 0.0


func reward_near_miss(points: int, clearance: float) -> int:
	near_misses += 1
	multiplier = minf(MAX_MULTIPLIER, multiplier + 0.5)
	top_combo = maxf(top_combo, multiplier)
	combo_remaining = COMBO_TIMEOUT
	var awarded := roundi(points * multiplier)
	bonus_points += awarded
	boost_charge = minf(1.0, boost_charge + (0.24 if clearance < 0.35 else 0.18))
	return awarded


func update_boost(requested: bool, delta: float, allow_damaged: bool = false) -> bool:
	# Consume reward time in driving ticks, including damage and released input.
	# A tick straddling expiry charges only its ordinary-fuel portion.
	var free_seconds := minf(maxf(0.0, delta), reward_boost_remaining)
	unlimited_this_tick = infinite_boost or free_seconds > 0.0
	reward_boost_remaining = _advance_timer(reward_boost_remaining, maxf(0.0, delta))
	if (damage_remaining > 0.0 and not allow_damaged) or not score_valid:
		boosting = false
		return false
	if infinite_boost:
		boost_charge = 1.0
		boost_empty_lock = false
		boosting = requested
		return boosting
	if free_seconds > 0.0:
		boost_empty_lock = false
		boosting = requested
		var paid_seconds := maxf(0.0, delta - free_seconds)
		if boosting and paid_seconds > 0.000000001:
			boost_charge = maxf(0.0, boost_charge - BOOST_DRAIN * paid_seconds)
			if boost_charge <= 0.0:
				boosting = false
				boost_empty_lock = true
		return boosting
	if not requested:
		boost_empty_lock = false
	boosting = requested and not boost_empty_lock and boost_charge > 0.0
	if boosting:
		boost_charge = maxf(0.0, boost_charge - BOOST_DRAIN * delta)
		if boost_charge <= 0.0:
			boosting = false
			boost_empty_lock = true
	return boosting


func grant_race_reward(seconds: float = 10.0) -> void:
	reward_boost_remaining = maxf(reward_boost_remaining, seconds)
	boost_empty_lock = false


func crash() -> void:
	boosting = false
	multiplier = 1.0
	combo_remaining = 0.0


func get_score() -> int:
	return maxi(0, floori(distance_points) + bonus_points - score_penalty) if score_valid else 0


func hit_pothole() -> bool:
	# One ten-second window in driving time, never wall time or time spent paused.
	if pothole_remaining > 0.0:
		return true
	pothole_remaining = POTHOLE_WINDOW
	apply_damage(POTHOLE_SCORE_LOSS, POTHOLE_SPEED_LOSS)
	return false


func apply_damage(points: int, speed_loss: float) -> void:
	score_penalty += mini(maxi(0, points), get_score())
	damage_speed_loss = maxf(0.0, speed_loss)
	damage_remaining = POTHOLE_RECOVERY
	crash()


func invalidate_score() -> void:
	score_valid = false
	crash()
