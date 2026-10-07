extends Node

const CombatRuntime := preload("res://scripts/layers/runtime/combat_runtime_service.gd")

## Direct-magic regression: a direct-magic struck must not gate the NEXT
## autonomous pursuit segment, including the cadence-bypassing continuation.


func _authority_record() -> Dictionary:
	return {
		"monster_id": 24,
		"runtime_allowed": true,
		"movement": {
			"movement_source_status": "ACCEPTED_CANDIDATE",
			"movement_enabled": true,
			"walk_interval_ms": 400,
			"walk_interval_status": "ACCEPTED_CANDIDATE",
			"walk_interval_authority": "B_CANDIDATE",
			"walk_step": 1,
			"walk_step_status": "ACCEPTED_CANDIDATE",
			"walk_step_authority": "B_CANDIDATE",
			"walk_wait_ms": 0,
			"walk_wait_status": "ACCEPTED_CANDIDATE",
			"walk_wait_authority": "B_CANDIDATE",
			"walk_wait_explicit_zero": true,
			"source": {
				"runtime_lookup": "monster_id_only",
				"binding_status": "EXACT_SOURCE_ROW",
			},
			"m00r_resolution": "hc_monster_combat_r1_continuous_magic_walk_delay_test",
		},
	}


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var combat_runtime := CombatRuntime.new()
	add_child(combat_runtime)
	# Unit part: the ordinary cadence remains valid.
	var cadence := MonsterMovementCadence.new()
	assert(cadence.configure(_authority_record(), 0))
	assert(cadence.evaluate(800).granted, "fixture: first walk grant at 800ms")
	assert(cadence.walk_tick_ms == 800)

	# Actor part: the shared next-segment gate consumed by the pursuit
	# continuation entry (which bypasses evaluate()).
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
	var actor_cadence: MonsterMovementCadence = enemy._movement_cadence
	assert(actor_cadence != null and actor_cadence.configured, "fixture: actor cadence configured")
	# Pin the example values on the real actor cadence.
	actor_cadence.walk_interval_ms = 400
	actor_cadence.walk_tick_ms = 800
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
	assert(actor_cadence.walk_tick_ms == 800, "direct magic leaves actor cadence unchanged")
	enemy._hc_pursuit_session = true
	assert(
		enemy._begin_autonomous_step_without_cadence(
			Vector2(1, 0), 1.0, false, &"pursuit", player, 1900
		),
		"direct magic must not gate the next pursuit segment"
	)
	enemy.queue_free()
	player.queue_free()
	print("HC_MCR1_CONTINUOUS_MAGIC_WALK_DELAY_PASS")
	get_tree().quit()
