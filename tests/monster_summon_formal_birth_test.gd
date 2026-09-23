extends "res://tests/m30_r4/test_m30_summon_reproduction.gd"

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "summon_cap_birth")
	var caster: PlayerCharacter = game.player
	caster.max_hp = 999999
	caster.current_hp = caster.max_hp
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(
		Fixture.FIXTURE_GROUND_POSITION + Fixture.CASTER_GROUND_OFFSET))
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			value.set_combat_position(caster.global_position + Vector2(3000, 3000), &"summon_test_clear")
			value.set_physics_process(false)
	var sources: Array[EnemyActor] = []
	for index in range(3):
		var id: int = [182, 126, 160][index]
		var position: Vector2 = game._canonical_ground_gu_to_screen_px(Fixture.FIXTURE_GROUND_POSITION + Vector2(index * 4, 0))
		var source: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(id), position, false, -1.0,
			{"respawn_enabled": false, "spawn_slot_id": "cap:%d" % id})
		check(source != null and source.monster_id == id, "formal source birth%d" % id)
		if source == null:
			get_tree().quit(1)
			return
		source.set_physics_process(false)
		source.dormant = false
		source.target = caster
		sources.append(source)
	for index in range(20):
		for source in sources:
			if source.is_boss:
				source._boss_health_stage = 5
				source.current_hp = 1
				source._apply_health_stage_mechanics()
			else:
				source._summon_cooldown = 0
				source._update_behavior_summon(0)
				source._update_behavior_summon(0.5)
	var queue: HCM30SummonQueue = game._hc_m30_get_summon_queue()
	await _drain_formal(queue)
	for source in sources:
		var cap := 15 if source.is_boss else 5
		var slot := "cap:%d" % source.monster_id
		check(queue._active(slot) == cap, "formal live count%d=%d" % [source.monster_id, cap])
		for ref: WeakRef in queue._children.get(slot, {}).values():
			var child: EnemyActor = ref.get_ref()
			var allowed_ids: Array = [156, 153, 150, 128] if source.is_boss else ([183] if source.monster_id == 182 else [127])
			check(child.monster_id in allowed_ids, "formal newborn identity matches source%d" % source.monster_id)
			check(child.direct_spell_stats_valid and child.current_hp > 0, "newborn has valid combat stats")
	var phantom_child: EnemyActor = (queue._children["cap:182"].values()[0] as WeakRef).get_ref()
	phantom_child.take_damage(999999, caster, {"source": "summon_birth_regression"})
	check(queue._active("cap:182") == 4, "real damage/death frees one phantom slot")
	sources[0]._summon_cooldown = 0
	sources[0]._update_behavior_summon(0)
	sources[0]._update_behavior_summon(0.5)
	await _drain_formal(queue)
	check(queue._active("cap:182") == 5, "real phantom producer refills exactly one")
	for monster_id in [33, 241]:
		var empty_actor: EnemyActor = game._spawn_enemy(GameData.get_monster_by_id(monster_id),
			game._canonical_ground_gu_to_screen_px(Fixture.FIXTURE_GROUND_POSITION + Vector2(-3, 3)),
			false, -1.0, {"respawn_enabled": false, "spawn_slot_id": "empty:%d" % monster_id})
		check(empty_actor != null and empty_actor.monster_id == monster_id, "no-drop ordinary spawn%d works" % monster_id)
		if empty_actor != null:
			empty_actor.take_damage(999999, caster, {"source": "empty_drop_regression"})
	check(int(queue.snapshot().max_materializations_in_tick) <= 1, "formal materialization budget1 retained")
	check(int(queue.snapshot().max_probes_in_tick) <= 8, "formal landing budget8 retained")
	await _wait_physics_frames(self, 10)
	print("MONSTER_SUMMON_FORMAL_BIRTH_%s checks=%d failures=%d snapshot=%s" % [
		"PASS" if failures == 0 else "FAIL", checks, failures, JSON.stringify(queue.snapshot())])
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func _drain_formal(queue: HCM30SummonQueue) -> void:
	for _tick in range(360):
		for ref_dict: Dictionary in queue._children.values():
			for ref: WeakRef in ref_dict.values():
				var child: EnemyActor = ref.get_ref()
				if is_instance_valid(child):
					child.set_physics_process(false)
		for slot in ["cap:182", "cap:126", "cap:160"]:
			check(queue._active(slot) + int(queue._reserved.get(slot, 0)) <= (15 if slot == "cap:160" else 5), "formal active+reserved invariant")
		if queue._jobs.is_empty():
			return
		await get_tree().physics_frame
	check(false, "formal queue failed to drain")
