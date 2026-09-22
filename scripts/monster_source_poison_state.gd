extends RefCounted

# Only the explicitly sourced monster poison lane. Existing skill/item poison
# retains its own contract. Damage/death remain owned by the target actor.
var remaining_seconds := 0.0
var tick_damage := 0
var interval_seconds := 0.0
var elapsed_seconds := 0.0


func apply(damage: int, seconds: float, interval: float) -> bool:
	if damage <= 0 or not is_finite(seconds) or not is_finite(interval) or seconds <= 0.0 or interval <= 0.0:
		return false
	if remaining_seconds <= 0.0:
		elapsed_seconds = 0.0
		# An expired lane starts clean so a weaker poison takes over after
		# the strong one fully expired.
		tick_damage = 0
	# Poison never stacks: while a poison is active, a weaker application
	# must not downgrade its damage (both legacy lanes take the max).
	tick_damage = maxi(tick_damage, damage)
	remaining_seconds = maxf(remaining_seconds, seconds)
	interval_seconds = interval
	return true


func advance(delta: float) -> int:
	if remaining_seconds <= 0.0 or not is_finite(delta) or delta <= 0.0:
		return 0
	elapsed_seconds += minf(delta, remaining_seconds)
	remaining_seconds = maxf(0.0, remaining_seconds - delta)
	var ticks := int(floor((elapsed_seconds + 0.000001) / interval_seconds))
	elapsed_seconds = maxf(0.0, elapsed_seconds - float(ticks) * interval_seconds)
	return ticks


func clear() -> void:
	remaining_seconds = 0.0
	tick_damage = 0
	interval_seconds = 0.0
	elapsed_seconds = 0.0
