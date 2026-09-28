extends Node

const AttackTimingScript := preload("res://scripts/monster_attack_timing.gd")

## Explicit primary-source zero is present data. Native LocalDB applies 200ms
## at load time; raw primary data must remain zero, not a guessed replacement.
func _ready() -> void:
	var failures: Array = []
	for pair: Array in [[0, 200], [1, 200], [199, 200], [200, 200], [2000, 2000], [-1, -1], [null, -1], ["200", -1], [0.5, -1]]:
		if AttackTimingScript.effective_interval_ms(pair[0]) != pair[1]:
			failures.append("interval_boundary_wrong:%s" % str(pair))
	for mid: int in [183, 241]:
		var actor := EnemyActor.new()
		actor.setup(GameData.get_monster_by_id(mid), null, false)
		var timing: Dictionary = actor.behavior_profile.get("timing", {})
		if not timing.has("attackIntervalMs") or int(timing.attackIntervalMs) != 0:
			failures.append("%d:raw_primary_zero_changed" % mid)
		if not is_equal_approx(actor._attack_interval, 0.2):
			failures.append("%d:explicit_zero_became_default_%f" % [mid, actor._attack_interval])
		actor.free()
	# The primary combat row for ID19 has 0..5 DC. Setup must retain the
	# legitimate zero outcome rather than silently raising the lower bound.
	var zero_floor := EnemyActor.new()
	zero_floor.setup(GameData.get_monster_by_id(19), null, false)
	if zero_floor.attack_min != 0 or zero_floor.attack_max < 1:
		failures.append("19:zero_dc_floor_changed:%d..%d" % [zero_floor.attack_min, zero_floor.attack_max])
	zero_floor.free()
	print("R4_ZERO_ATTACK_TIMING_PASS" if failures.is_empty() else "R4_ZERO_ATTACK_TIMING_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
