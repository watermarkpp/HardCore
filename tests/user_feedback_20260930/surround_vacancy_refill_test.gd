extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
@export var case_monster_id := 24
const STANDS := [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1)]

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	var actors: Array[EnemyActor] = []
	for offset: Vector2 in STANDS:
		actors.append(_spawn(case_monster_id, CENTER + offset))
	for i in 16:
		actors.append(_spawn(case_monster_id, CENTER + Vector2(3.0 + float(i % 4) * 1.1, (float(i / 4) - 1.5) * 1.1)))
	for actor in actors:
		actor._leave_background_deep_sleep()
		actor.dormant = false
		actor.target = player
		actor._retarget_timer = 999.0
		actor.max_hp = 100000
		actor.current_hp = actor.max_hp
		actor.set_physics_process(true)
	var victim := actors[4]
	# Preserve the canonical first attack deadline and source permission. A
	# fixed two-second warmup can end before this monster's first admission.
	var warmup_frames := 0
	for frame in 360:
		await get_tree().physics_frame
		warmup_frames = frame + 1
		if victim._hc_starts > 0: break
	var old_id := victim.spatial_actor_runtime_id
	_check(victim._hc_access(player) == "CLEAR" and victim._hc_starts > 0, "vacancy must start from a real attacking west occupant")
	var combat := Combat.new()
	add_child(combat)
	var outcome := combat.apply_enemy_direct_spell_damage(victim, "wizard.fire_wall", 1000000, player, null, Callable(), 9, {}, Combat.EnemyMagicDeliveryKind.AUTO)
	_check(bool(outcome.get("success", false)) and victim.current_hp <= 0, "real damage did not free the west occupant")
	var replacement := 0
	var refill_frame := -1
	for frame in 2400:
		await get_tree().physics_frame
		for actor in actors:
			if not is_instance_valid(actor) or not actor.can_receive_damage() or actor.spatial_actor_runtime_id == old_id:
				continue
			if actor.spatial_index_position().distance_to(CENTER + Vector2.LEFT) <= 0.4 and actor._hc_access(player) == "CLEAR" and actor._hc_starts > 0:
				replacement = actor.spatial_actor_runtime_id
				refill_frame = frame
				break
		if replacement > 0: break
	_check(replacement > 0, "rear crowd did not refill the free west attack stand")
	var label := "surround_vacancy_refill" + ("_89" if case_monster_id == 89 else "")
	FileAccess.open("res://outputs/test_logs/" + label + ".json", FileAccess.WRITE).store_string(JSON.stringify({"monster_id": case_monster_id, "old_occupant": old_id, "replacement": replacement, "warmup_frames": warmup_frames, "refill_frame": refill_frame, "failures": failures}, "  "))
	for actor in actors:
		if not is_instance_valid(actor): continue
		actor.set_physics_process(false)
		index.unregister(actor.spatial_actor_runtime_id)
		actor.queue_free()
	combat.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print("SURROUND_VACANCY_REFILL_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
