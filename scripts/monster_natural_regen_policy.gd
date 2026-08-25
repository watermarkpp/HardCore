class_name MonsterNaturalRegenPolicy
extends RefCounted

## MONSTER-FINAL-CLOSURE / MFC-3
##
## Preserves the locked service cadence:
##   every 6 seconds -> floor(MaxHP / 75) + 1 HP
##
## HardCore intentional correction:
## physical damage, magic damage, red poison and green poison never pause,
## reset or suppress this cadence. The policy therefore has no combat/poison
## input at all. A caller must advance it continuously while the actor is alive.

const CONTRACT_ID := "monster.natural_regen.hardcore.v1"
const TICK_SECONDS := 6.0

var _elapsed_seconds := 0.0
var _total_ticks := 0


func reset() -> void:
	_elapsed_seconds = 0.0
	_total_ticks = 0


func advance(delta_seconds: float, current_hp: int, max_hp: int) -> Dictionary:
	var safe_max_hp := maxi(0, max_hp)
	var hp := 0
	if safe_max_hp > 0:
		hp = clampi(current_hp, 0, safe_max_hp)
	if delta_seconds <= 0.0 or safe_max_hp <= 0:
		return _result(hp, 0, 0)

	_elapsed_seconds += delta_seconds
	var due_ticks := int(floor(_elapsed_seconds / TICK_SECONDS))
	if due_ticks <= 0:
		return _result(hp, 0, 0)

	# Consume every elapsed service tick even at full HP. This is essential:
	# taking damage must never start a fresh six-second timer.
	_elapsed_seconds -= float(due_ticks) * TICK_SECONDS
	_total_ticks += due_ticks

	var healed := 0
	var per_tick := heal_amount(safe_max_hp)
	for _tick_index: int in range(due_ticks):
		var before := hp
		hp = mini(safe_max_hp, hp + per_tick)
		healed += hp - before

	return _result(hp, healed, due_ticks)


func state_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"tick_seconds": TICK_SECONDS,
		"elapsed_seconds": _elapsed_seconds,
		"total_ticks": _total_ticks,
	}


static func heal_amount(max_hp: int) -> int:
	if max_hp <= 0:
		return 0
	return floori(float(max_hp) / 75.0) + 1


func _result(hp: int, healed: int, ticks: int) -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"hp": hp,
		"healed": healed,
		"ticks": ticks,
		"elapsed_seconds": _elapsed_seconds,
		"total_ticks": _total_ticks,
	}
