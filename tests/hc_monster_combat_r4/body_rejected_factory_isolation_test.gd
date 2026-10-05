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
	# R4-B: every mutant is constructed from original24.duplicate(true) with
	# EXACTLY ONE field changed, so the rejection is attributable to that
	# field's validation alone (the previous version poisoned the same dict
	# cumulatively, letting later mutants be rejected by earlier damage).
	# The catalog dict is mutated in place by reference; each case restores
	# the byte-for-byte original and clears the entry cache, then a normal
	# 24 positive control confirms the restoration.
	var catalog: Dictionary = MonsterIdentityScript._catalog()
	var profile_slot: Dictionary = catalog["entries_by_id"]["24"]["combat"]
	var original24: Dictionary = (profile_slot["body_profile"] as Dictionary).duplicate(true)
	var screen24: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(46.5, 13.5))

	var mutants := [
		{"label": "empty_profile", "mutation": {}},
		{"label": "broken_required_field", "mutation": {"screen_radius_px": 0.0}},
		{"label": "wrong_policy_hash", "mutation": {"policy_sha256": "0000000000000000000000000000000000000000000000000000000000000000"}},
		{"label": "foreign_assignment_rule", "mutation": {"assignment_rule": "boss_large_body"}},
	]
	var mutants_ok := true
	var mutant_report: Array = []
	for mutant: Variant in mutants:
		# Independent mutant: deep copy of the original, one field changed.
		var mutated := original24.duplicate(true)
		var mutation: Dictionary = mutant["mutation"]
		if mutation.is_empty():
			mutated = {}
		else:
			for key: String in mutation:
				mutated[key] = mutation[key]
		# Every non-target field must remain intact and correct: the ONLY
		# possible rejection cause is the mutated field's own validation.
		if not mutation.is_empty():
			for original_key: String in original24:
				if mutation.has(original_key):
					continue
				if mutated.get(original_key) != original24.get(original_key):
					mutants_ok = false
					mutant_report.append("%s: collateral field %s" % [mutant["label"], original_key])
		(profile_slot["body_profile"] as Dictionary).clear()
		for key: String in mutated:
			(profile_slot["body_profile"] as Dictionary)[key] = mutated[key]
		MonsterIdentityScript._entry_cache.clear()
		var rejected: bool = game._spawn_enemy(GameData.get_monster_by_id(24), screen24, false, -1.0, context) == null
		var no_residual: bool = index.registered_actor_count() == registered_after_controls
		if not rejected or not no_residual:
			mutants_ok = false
			mutant_report.append("%s: rejected=%s residual=%s" % [mutant["label"], rejected, no_residual])
		# Restore the byte-for-byte original and prove the restoration with a
		# normal 24 positive control through the SAME factory path.
		(profile_slot["body_profile"] as Dictionary).clear()
		for key: String in original24:
			(profile_slot["body_profile"] as Dictionary)[key] = original24[key]
		MonsterIdentityScript._entry_cache.clear()
		var control_after: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(24), screen24 + Vector2(30.0, 0.0), false, -1.0, context)
		if control_after == null or bool(control_after.get_meta("body_policy_rejected", false)):
			mutants_ok = false
			mutant_report.append("%s: post-restore control failed" % mutant["label"])
		if control_after != null:
			control_after.free()

	var failures_ok: bool = mutants_ok
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
			"R4_BODY_FACTORY: controls_ok=%s failures_ok=%s reason_ok=%s residual_ok=%s registered=%d->%d details=%s" % [
				controls_ok, failures_ok, failure_reason_ok, no_residual_registration,
				registered_before, registered_after_controls, str(mutant_report),
			]
		)
		get_tree().quit(1)
		return
	print("R4_BODY_REJECTED_FACTORY_ISOLATION_PASS: four independent one-field mutants all rejected with zero residual registration and healthy post-restore controls")
	get_tree().quit(0)
