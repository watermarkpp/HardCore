extends Node

## R4 T3 factory-level isolation inside the FORMAL mapped world: a
## config-rejected body profile must fail the spawn transaction atomically -
## no spatial index entry, no activity registration, no node leak - while
## ordinary, boss and legal non-combat chest spawns keep working through the
## SAME formal factory path (`_spawn_enemy`).

const FIXTURE_MONSTERS := [18, 76, 226]
const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")


func _ready() -> void:
	_run.call_deferred()


func _poison_profile(monster_id: int, mutation: Dictionary) -> void:
	var entry: Dictionary = MonsterIdentityScript._catalog()["entries_by_id"][str(monster_id)]
	var poisoned: Dictionary = (entry["combat"] as Dictionary)["body_profile"]
	for key: String in mutation:
		poisoned[key] = mutation[key]
	MonsterIdentityScript._entry_cache.clear()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var deadline_ms: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline_ms:
		if int(game.get("current_map_id")) >= 0 and bool(game.call("gameplay_input_is_enabled")):
			break
		await get_tree().process_frame
	assert(int(game.get("current_map_id")) == GameData.service_runtime_map_id(0), "fixture needs the formal mapped world")
	var index: RuntimeCombatSpatialIndex = game._combat_spatial_index
	var registered_before: int = index.registered_actor_count()
	var context := {
		"respawn_enabled": false,
		"spawn_slot_id": "test:r4-body-isolation",
	}
	var ground_positions := [Vector2(40.5, 13.5), Vector2(42.5, 13.5), Vector2(44.5, 13.5)]

	# --- Positive controls through the REAL factory path ---
	var control_ok := true
	var control_actors: Array = []
	for i: int in FIXTURE_MONSTERS.size():
		var screen: Vector2 = game._canonical_ground_gu_to_screen_px(ground_positions[i])
		var actor: EnemyActor = game._spawn_enemy(
			GameData.get_monster_by_id(FIXTURE_MONSTERS[i]),
			screen,
			FIXTURE_MONSTERS[i] == 76,
			-1.0,
			context,
		)
		control_actors.append(actor)
		if actor == null or bool(actor.get_meta("body_policy_rejected", false)):
			control_ok = false
	# Monster 226 is one of the 9 legal contract-disabled identities: its body
	# is VALID, it simply is not a combatant. It must spawn and register like
	# any other actor (the chest must NOT be deleted by the isolation work).
	var chest_ok: bool = control_actors[2] != null and not bool(control_actors[2].get_meta("body_policy_rejected", false))
	var registered_after_controls: int = index.registered_actor_count()
	var controls_ok: bool = (
		control_ok
		and chest_ok
		and registered_after_controls == registered_before + 3
	)

	# --- Failure injections through the REAL factory path ---
	# The enemy setup reads its body profile through the MonsterIdentity
	# catalog cache, so the injection mutates THAT production source and
	# clears the entry cache. `_catalog()` returns the cached dictionary by
	# reference, so in-place mutations are visible to every later read.
	var catalog: Dictionary = MonsterIdentityScript._catalog()
	var original24: Dictionary = (catalog["entries_by_id"]["24"]["combat"] as Dictionary)["body_profile"].duplicate(true)
	var screen24: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(46.5, 13.5))
	# 1. empty profile
	(catalog["entries_by_id"]["24"]["combat"] as Dictionary)["body_profile"] = {}
	MonsterIdentityScript._entry_cache.clear()
	var rejected_empty: bool = game._spawn_enemy(GameData.get_monster_by_id(24), screen24, false, -1.0, context) == null
	# 2. broken required field
	_poison_profile(24, {"screen_radius_px": 0.0})
	var rejected_field: bool = game._spawn_enemy(GameData.get_monster_by_id(24), screen24, false, -1.0, context) == null
	# 3. wrong policy hash
	_poison_profile(24, {"policy_sha256": "0000000000000000000000000000000000000000000000000000000000000000"})
	var rejected_hash: bool = game._spawn_enemy(GameData.get_monster_by_id(24), screen24, false, -1.0, context) == null
	# 4. foreign assignment rule (rule/tier cross)
	_poison_profile(24, {"assignment_rule": "boss_large_body"})
	var rejected_rule: bool = game._spawn_enemy(GameData.get_monster_by_id(24), screen24, false, -1.0, context) == null
	# Restore the production catalog byte-for-byte.
	(catalog["entries_by_id"]["24"]["combat"] as Dictionary)["body_profile"] = original24
	MonsterIdentityScript._entry_cache.clear()
	var failures_ok: bool = rejected_empty and rejected_field and rejected_hash and rejected_rule
	var failure_reason_ok: bool = str(game.get("_staged_actor_spawn_failure_reason")) == "body_policy_rejected"
	# Rejected spawns leave NO residual registration behind.
	var no_residual_registration: bool = index.registered_actor_count() == registered_after_controls

	var valid: bool = (
		controls_ok
		and failures_ok
		and failure_reason_ok
		and no_residual_registration
	)
	game.queue_free()
	if not valid:
		printerr(
			"R4_BODY_FACTORY: controls_ok=%s failures_ok=%s reason_ok=%s residual_ok=%s registered=%d->%d" % [
				controls_ok, failures_ok, failure_reason_ok, no_residual_registration,
				registered_before, registered_after_controls,
			]
		)
		get_tree().quit(1)
		return
	print("R4_BODY_REJECTED_FACTORY_ISOLATION_PASS")
	get_tree().quit(0)
