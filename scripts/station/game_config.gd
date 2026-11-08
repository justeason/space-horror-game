extends RefCounted
## Round 34: central DEVELOPMENT/BALANCING settings (not player settings,
## not difficulty). Change here to rebalance the day.

## Real seconds of active gameplay in one standard daily shift.
const SHIFT_DURATION_S: float = 600.0

## Tests and tools may shorten the shift at runtime (never saved).
static var shift_duration_override_s: float = -1.0


static func shift_duration_s() -> float:
	return shift_duration_override_s if shift_duration_override_s > 0.0 else SHIFT_DURATION_S
