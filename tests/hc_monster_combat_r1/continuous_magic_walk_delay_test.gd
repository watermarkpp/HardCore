extends Node

## HC-MONSTER-COMBAT-R1 Task 1 (F03) counterexample.
## A direct-magic walk postponement must gate the NEXT autonomous pursuit
## segment even when the granted pursuit session bypasses cadence.evaluate().
## Vanilla rule (ObjBase): m_dwWalkTick += 800 + Random(1000); the next walk
## grant waits until now - walk_tick_ms > walk_interval_ms (strict >).
const MonsterStruckPolicyScript = preload("res://scripts/monster_struck_policy.gd")


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
	# Unit part: the cadence postponement floor itself.
	var cadence := MonsterMovementCadence.new()
	assert(cadence.configure(_authority_record(), 0))
	assert(cadence.evaluate(800).granted, "fixture: first walk grant at 800ms")
	assert(cadence.walk_tick_ms == 800)
	assert(cadence.postpone_walk_tick_ms(800), "fixture: direct-magic postponement accepted")
	assert(cadence.walk_tick_ms == 1600, "postponement must extend the vanilla walk tick")
	# Grant schedule: now - 1600 > 400, i.e. strictly after 2000ms.
	assert(not cadence.evaluate(1000).granted, "pre-floor grant must wait")
	assert(not cadence.evaluate(2000).granted, "the exact floor is still locked (strict >)")
	assert(cadence.evaluate(2001).granted, "the postponed grant must release right after the floor")

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
	var actor_cadence: MonsterMovementCadence = enemy._movement_cadence
	assert(actor_cadence != null and actor_cadence.configured, "fixture: actor cadence configured")
	# Pin the vanilla example values on the real actor cadence.
	actor_cadence.walk_interval_ms = 400
	actor_cadence.walk_tick_ms = 800
	enemy.apply_source_direct_magic_walk_delay(0)
	assert(
		actor_cadence.walk_tick_ms == 800 + MonsterStruckPolicyScript.direct_magic_walk_delay_ms(0),
		"fixture: actor postponement applied (roll 0)"
	)
	enemy._hc_pursuit_session = true
	assert(
		not enemy._begin_autonomous_step_without_cadence(
			Vector2(1, 0), 1.0, false, &"pursuit", player, 1900
		),
		"F03: the direct-magic walk delay must gate the next pursuit segment"
	)
	assert(not enemy._movement_step_active, "no committed step may exist while the delay holds")
	assert(
		enemy._begin_autonomous_step_without_cadence(
			Vector2(1, 0), 1.0, false, &"pursuit", player, 2001
		),
		"the pursuit segment must start once the postponed floor has passed"
	)
	# Expired-deadline counterexample: a stale walk tick plus a small delay
	# must stay expired (allow immediately), never restart a full wait.
	var stale := MonsterMovementCadence.new()
	assert(stale.configure(_authority_record(), 0))
	assert(stale.evaluate(500).granted, "fixture: stale-cadence first grant")
	stale.walk_tick_ms = 100
	assert(stale.postpone_walk_tick_ms(800))
	assert(
		not stale.direct_magic_delay_blocks_next_step(5000),
		"an expired postponed deadline must allow the next segment immediately"
	)
	enemy.queue_free()
	player.queue_free()
	print("HC_MCR1_CONTINUOUS_MAGIC_WALK_DELAY_PASS")
	get_tree().quit()
