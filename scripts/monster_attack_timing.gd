class_name MonsterAttackTiming
extends RefCounted

## Raw timing remains primary 21CQ data. The service loader's interpretation
## is LocalDB.pas:1362-1363 (wAttackSpeed below 200 becomes 200ms).
## This is a cadence floor, not a hit-delay or a missing-data fallback.
const MIN_INTERVAL_MS := 200

static func effective_interval_ms(raw: Variant) -> int:
	if not (raw is int or raw is float) or not is_finite(float(raw)) or float(raw) < 0 or float(raw) != floorf(float(raw)):
		return -1
	return maxi(MIN_INTERVAL_MS, int(raw))
