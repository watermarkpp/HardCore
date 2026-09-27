extends Node

## HC-MONSTER-COMBAT-R2 T4 (R2-02/R2-04 acceptance): the direct-magic walk
## postponement must be real against the INTEGRATED movement chain, not only
## at the cadence unit boundary:
##   1. a committed movement step in flight is NOT cancelled when the delay
##      lands mid-step,
##   2. the step finishes naturally on its own,
##   3. the NEXT segment - including the cadence-bypassing pursuit
##      continuation entry - is denied until the postponement floor passes,
##      and allowed right after it.

const MonsterStruckPolicyScript := preload("res://scripts/monster_struck_policy.gd")


func _ready() -> void:
	var player := PlayerCharacter.new()
	player.set_physics_process(false)
	add_child(player)
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(24), player, false)
	enemy.global_position = Vector2.ZERO
	enemy.set_meta("spawn_position", Vector2.ZERO)
	enemy.set_meta("safe_zones", [])
	add_child(enemy)
	enemy.set_physics_process(false)
	var cadence: MonsterMovementCadence = enemy._movement_cadence
	assert(cadence != null and cadence.configured, "fixture: actor cadence configured")
	cadence.walk_interval_ms = 400
	cadence.walk_tick_ms = 800

	# 1. A real committed step is in flight when the direct magic lands.
	assert(
		enemy._begin_autonomous_step_without_cadence(
			Vector2(1, 0), 1.0, false, &"pursuit", player, 800
		),
		"fixture: the pursuit segment must start"
	)
	assert(enemy._movement_step_active, "fixture: the movement step is active")
	var epoch_before: int = enemy._movement_step_epoch

	enemy.apply_source_direct_magic_walk_delay(0)
	assert(
		cadence.walk_tick_ms == 800 + MonsterStruckPolicyScript.direct_magic_walk_delay_ms(0),
		"fixture: the postponement extended the walk tick"
	)

	# 2. The committed step is not cancelled: the epoch is untouched and the
	# step still finishes naturally (never revoked by the delay).
	assert(
		enemy._movement_step_active and enemy._movement_step_epoch == epoch_before,
		"the direct-magic delay must not cancel a committed movement step"
	)
	var completed := false
	for _tick in 600:
		if not enemy._movement_step_active:
			completed = true
			break
		enemy._advance_autonomous_step(1.0 / 60.0)
	assert(
		completed,
		"the movement step in flight must finish naturally, not be cut short"
	)

	# 3. The next segment stays denied at the postponement floor ...
	assert(
		not enemy._begin_autonomous_step_without_cadence(
			Vector2(1, 0), 1.0, false, &"pursuit", player, 1600
		),
		"the exact postponement floor must still deny the next segment"
	)
	assert(
		not enemy._movement_step_active,
		"no step may have been committed while the delay holds"
	)
	# ... and the cadence-bypassing pursuit continuation is gated by the same
	# schedule: a grant releases only when now - walk_tick > walk_interval
	# (strict >), i.e. strictly after 1600 + 400 = 2000 ms here.
	assert(
		not enemy._begin_autonomous_step_without_cadence(
			Vector2(1, 0), 1.0, false, &"pursuit", player, 2000
		),
		"the vanilla strict > grant schedule still holds inside the window"
	)
	assert(
		enemy._begin_autonomous_step_without_cadence(
			Vector2(1, 0), 1.0, false, &"pursuit", player, 2001
		),
		"the next segment must release right after the grant schedule"
	)
	assert(enemy._movement_step_active, "the released segment commits a real step")

	enemy.queue_free()
	player.queue_free()
	print("HC_MCR2_DIRECT_MAGIC_STEP_CHAIN_PASS")
	get_tree().quit()
