extends Node


class PlayerProbe extends PlayerCharacter:
	var commits := 0
	func _apply_resolved_damage(amount: int, causes_struck: bool, damage_type := "physical", durability_context := {}, force_struck_reaction := false) -> void:
		commits += 1
		super._apply_resolved_damage(amount, causes_struck, damage_type, durability_context, force_struck_reaction)


class SummonProbe extends SummonActor:
	var commits := 0
	func _apply_resolved_damage(amount: int, causes_struck := true) -> void:
		commits += 1
		super._apply_resolved_damage(amount, causes_struck)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerProbe.new()
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.max_hp = 100
	player.current_hp = 100
	player.defense_min = 2
	player.defense_max = 2
	player.defense_buff = 0
	PlayerState.computed_stats["magic_defense_min"] = 3
	PlayerState.computed_stats["magic_defense_max"] = 3
	var context := {"source_monster_id": 76, "source_instance_id": 1, "release_id": "mixed-atomic-test"}
	context.make_read_only()
	var first := player.take_monster_mixed_damage(10, 10, context)
	assert(first.physical_damage == 8 and first.magic_damage == 7)
	assert(first.applied_damage == 15 and player.current_hp == 85)
	assert(player.commits == 1, "mixed player hit must commit exactly once")

	player.shield_time = 10.0
	player.shield_capacity = 100.0
	player.damage_reduction = 0.5
	player.current_hp = 100
	var shielded := player.take_monster_mixed_damage(10, 10, context)
	assert(shielded.pipeline_input == 15 and shielded.applied_damage == 8)
	assert(player.current_hp == 92 and player.shield_capacity == 93.0)
	assert(player.commits == 2, "mixed damage must consume the common shield once")
	var blocked := player.take_monster_mixed_damage(1, 1, context)
	assert(blocked.applied_damage == 0 and player.commits == 2)
	assert(player.take_monster_mixed_damage(-1, 1, context).success == false)
	assert(player.begin_combat_transition("mixed-test"))
	assert(player.take_monster_mixed_damage(100, 100, context).applied_damage == 0)
	assert(player.commits == 2 and player.current_hp == 92)
	assert(player.finish_combat_transition("mixed-test"))

	var summon := SummonProbe.new()
	summon.setup(player, "骷髅", 1, 0, "taoist.summon_skeleton", 19, 1)
	add_child(summon)
	await get_tree().process_frame
	summon.set_physics_process(false)
	summon.current_hp = 100
	summon.ac_min = 2
	summon.ac_max = 2
	summon.mac_min = 3
	summon.mac_max = 3
	var pet_hit := summon.take_monster_mixed_damage(10, 10, context)
	assert(pet_hit.physical_damage == 8 and pet_hit.magic_damage == 7)
	assert(pet_hit.applied_damage == 15 and summon.current_hp == 85 and summon.commits == 1)
	assert(player.begin_combat_transition("mixed-pet-test"))
	assert(summon.take_monster_mixed_damage(100, 100, context).applied_damage == 0)
	assert(summon.commits == 1)
	assert(player.finish_combat_transition("mixed-pet-test"))
	summon.current_hp = 10
	var pet_lethal := summon.take_monster_mixed_damage(20, 20, context)
	assert(pet_lethal.applied_damage == 10 and summon.current_hp == 0)
	assert(summon.state == SummonActor.SummonState.DEAD and summon.commits == 2)
	assert(summon.take_monster_mixed_damage(20, 20, context).success == false)
	assert(summon.commits == 2, "dead pet must not recommit a mixed hit")

	player.shield_time = 0.0
	player.current_hp = 10
	var epoch_before := player.combat_epoch
	var lethal := player.take_monster_mixed_damage(20, 20, context)
	assert(lethal.applied_damage == 10 and player.current_hp == 0 and player._dead)
	assert(player.commits == 3 and player.combat_epoch == epoch_before + 1)
	assert(player.take_monster_mixed_damage(20, 20, context).success == false)
	assert(player.commits == 3 and player.combat_epoch == epoch_before + 1)
	summon.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print("MONSTER_MIXED_DAMAGE_ATOMIC_PASS: AC+MAC then one shield/HP/death commit; player+summon; zero and transition gates")
	get_tree().quit(0)
