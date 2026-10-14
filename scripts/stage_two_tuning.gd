extends RefCounted
## Shared physical budgets and long-run balance; speeds are meters/second.

const OPENING_KMH := 130.0
const CURVE_GAIN_KMH := 200.0
# Speed progression runs at five times the original pace, including the endless tail.
const CURVE_MINUTES := 4.0
const ENDLESS_KMH_PER_MINUTE := 7.0
const DISTANCE_WEIGHT := 0.05
const DISTANCE_REFERENCE_SPEED := 50.0
const LOOK_AHEAD_BASE := 285.0
const LOOK_AHEAD_SECONDS := 4.0
# Covers four seconds at 2,160 km/h while keeping world resources finite.
const LOOK_AHEAD_MAX := 2400.0
const MIN_SPAWN_SECONDS := 1.2
# The cruise curve remains uncapped. Actual motion has a remote technical limit:
# a finite preview must contain 1.2 seconds plus the largest row footprint.
const MAX_PHYSICAL_SPEED := (LOOK_AHEAD_MAX - 20.0) / MIN_SPAWN_SECONDS
const REACTION_SECONDS := 0.72
const TRAFFIC_SCALE := 1.08
const PLAYER_SIZE := Vector3(3.45, 1.5, 6.15)
const TRAFFIC_LANE_SPEED := 5.0
const MIXED_ROWS_AFTER_SECONDS := 600.0
const HEAT_MAX := 6
const HEAT_DECAY_SECONDS := 90.0
const HEAT_DECAY_RATE := 0.004

static func clamp_physical_speed(requested_speed: float) -> float:
	return 0.0 if is_nan(requested_speed) else clampf(requested_speed, 0.0, MAX_PHYSICAL_SPEED)
