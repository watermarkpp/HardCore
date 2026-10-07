extends Node

const CombatRuntime := preload("res://scripts/layers/runtime/combat_runtime_service.gd")

## HC-MONSTER-COMBAT-R2 regression: a direct-magic struck must be transparent
## to the INTEGRATED movement chain:
##   1. a committed movement step in flight is NOT cancelled when the delay
##      lands mid-step,
##   2. the step finishes naturally on its own,
##   3. the NEXT segment - including the cadence-bypassing pursuit
##      continuation entry - remains allowed immediately.


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var combat_runtime := CombatRuntime.new()
	add_child(combat_runtime)
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
	await get_tree().physics_frame
	enemy.max_hp = 1000000
	enemy.current_hp = enemy.max_hp
	enemy.direct_spell_anti_magic_points = 0
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

	var hp_before := enemy.current_hp
	var direct_result := combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		"wizard.lightning",
		1000,
		null,
		null,
		Callable(),
		0,
		{},
		CombatRuntime.EnemyMagicDeliveryKind.AUTO,
	)
	assert(bool(direct_result.get("success", false)), "direct magic positive result")
	assert(enemy.current_hp < hp_before, "direct magic reduced HP")
	assert(cadence.walk_tick_ms == 800, "direct magic leaves the walk cadence unchanged")

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

	# 3. The next segment remains available immediately after the committed
	# step, including through the cadence-bypassing pursuit continuation.
	assert(
		enemy._begin_autonomous_step_without_cadence(
			Vector2(1, 0), 1.0, false, &"pursuit", player, 1600
		),
		"the next segment remains available without a struck movement delay"
	)
	assert(enemy._movement_step_active, "the next segment commits a real step")

	enemy.queue_free()
	player.queue_free()
	print("HC_MCR2_DIRECT_MAGIC_STEP_CHAIN_PASS")
	get_tree().quit()
