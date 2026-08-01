extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {"雷电术": 3}
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var caster: PlayerCharacter = game.player
	caster.current_mp = 100
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor:
			(value as EnemyActor).global_position = caster.global_position + Vector2(3000, 3000)
	var target := _make_enemy(game, caster, caster.global_position + Vector2(80, 0))
	game.locked_target = target
	var hp_before := target.current_hp
	var mana_before := caster.current_mp
	var lightning: Dictionary = game._execute_canonical_skill(
		"雷电术",
		caster.global_position,
		Vector2.RIGHT,
		999999
	)
	assert(lightning.get("runtime_contract", "") == "skills.runtime_router.cn_mir2_176.v1", "真实入口未经过SkillRuntimeRouter.execute")
	assert(lightning.get("adapter_contract", "") == "skills.production_adaptation.hardcore.v1", "真实入口缺少六类生产适配合同")
	assert(caster.current_mp == mana_before - 15, "雷电术未按canonical rank3唯一提交15MP")
	assert(target.current_hp < hp_before and hp_before - target.current_hp < 999999, "GameRoot仍采信客户端伤害或未应用canonical伤害")
	assert(_has_formal_visual(game, "wizard.lightning"), "雷电术canonical真实入口未创建稳定source_skill_id正式视觉")

	PlayerState.learned_skills = {"瞬息移动": 3, "火墙": 3}
	caster.current_mp = 100
	var teleport_origin := caster.global_position
	var teleport_destination: Vector2 = game._find_valid_random_teleport_position(
		teleport_origin
	)
	assert(teleport_destination != teleport_origin, "测试地图没有可用的瞬息移动目标点")
	var teleport: Dictionary = game._execute_canonical_skill(
		"瞬息移动",
		teleport_origin,
		Vector2.RIGHT,
		0,
		{
			"force_success": true,
			"destination_valid": true,
			"destination_tile": game._canonical_world_to_tile(teleport_destination),
		}
	)
	assert(bool(teleport.get("effect_success", false)), "瞬息移动canonical真实入口未完成移动")
	assert(caster.global_position != teleport_origin, "瞬息移动成功后玩家位置未改变")
	assert(
		_has_formal_visual(game, "wizard.teleport", "")
		and _has_formal_visual(game, "wizard.teleport", "arrival"),
		"瞬息移动canonical真实入口未创建主库离场/到达两阶段动画"
	)

	target.global_position = caster.global_position + Vector2(80, 0)
	game._set_magic_locked_target(target, true)
	game._skill_cast_target = target
	var fire_wall: Dictionary = game._execute_canonical_skill(
		"火墙",
		caster.global_position,
		Vector2.RIGHT,
		0,
		{"primary_stat_roll": 8}
	)
	assert(bool(fire_wall.get("accepted", false)), "火墙canonical真实入口被拒绝")
	var fire_wall_visual_count := 0
	for child: Node in game.get_children():
		if child is GroundSkillEffect and child.skill_id == "wizard.fire_wall":
			fire_wall_visual_count += 1
			assert(child._sprite != null and child._sprite.frame_count() == 6, "火墙未加载主库1630..1635六帧动画")
	assert(fire_wall_visual_count == 4, "火墙canonical真实入口未按主合同创建2×2四格动画")

	PlayerState.learned_skills = {
		SkillDataLoader.display_name("wizard.magic_shield"): 3,
	}
	caster.current_mp = 100
	var shield_result: Dictionary = game._execute_canonical_skill(
		"wizard.magic_shield",
		caster.global_position,
		Vector2.DOWN,
		0,
		{"primary_stat_roll": 12}
	)
	assert(bool(shield_result.get("accepted", false)), "魔法盾正式入口被拒绝")
	assert(bool(caster.magic_shield_snapshot().get("active", false)))
	var persistent_shields := get_tree().get_nodes_in_group(
		"wizard_magic_shield_persistent_visual"
	)
	assert(persistent_shields.size() == 1, "魔法盾未创建唯一常驻正式视觉")
	var persistent_shield := persistent_shields[0] as CasterSkillVisualEffect
	assert(persistent_shield.target_node == caster)
	var persistent_sprite: CasterSkillAnimationPlayer = persistent_shield._sprites[0]
	persistent_sprite._process(persistent_sprite.animation_duration() + 0.01)
	persistent_shield._process(0.1)
	assert(
		persistent_sprite.playback_complete
		and persistent_sprite.current_frame_index == persistent_sprite.frame_count() - 1,
		"魔法盾没有在成形动画后保留完整末帧"
	)
	assert(not persistent_shield.is_queued_for_deletion())
	caster.shield_capacity = 0.0
	persistent_shield._process(0.01)
	assert(persistent_shield.is_queued_for_deletion(), "魔法盾容量耗尽后视觉仍未移除")
	await get_tree().process_frame

	PlayerState.profession = "道士"
	PlayerState.learned_skills = {"召唤神兽": 3}
	PlayerState.inventory = [{"name": "护身符", "count": 5}]
	PlayerState.recalculate_stats()
	caster.current_mp = 100
	var summon_result: Dictionary = game._execute_canonical_skill(
		"召唤神兽",
		caster.global_position,
		Vector2.DOWN,
		0
	)
	assert(bool(summon_result.get("accepted", false)), "召唤神兽canonical真实入口被拒绝")
	assert(PlayerState.item_count("护身符") == 0, "道士材料适配器未按rank3消耗5张护身符")
	var main_pet: SummonActor = game._canonical_main_pet()
	assert(main_pet != null and main_pet.skill_id == "taoist.summon_divine_beast", "道士唯一主宠未携带稳定source_skill_id")
	assert(main_pet._sprite != null, "召唤神兽canonical主宠未加载正式动画")
	var first_pet_id := main_pet.get_instance_id()
	var recall: Dictionary = game._execute_canonical_skill("召唤神兽", caster.global_position, Vector2.DOWN, 0)
	assert(bool(recall.get("accepted", false)) and game._canonical_main_pet().get_instance_id() == first_pet_id, "已有道士主宠未执行召回而是替换")

	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("CANONICAL_SKILL_PRODUCTION_ENTRY_PASS")
	get_tree().quit(0)


func _make_enemy(game: Node, caster: PlayerCharacter, position: Vector2) -> EnemyActor:
	var enemy := EnemyActor.new()
	enemy.setup({
		"name": "canonical目标",
		"hp": 9999,
		"attackMin": 1,
		"attackMax": 1,
		"level": 1,
		"anti_magic_points": 0,
		"magic_defense_min": 0,
		"magic_defense_max": 0,
	}, caster, false)
	enemy.global_position = position
	enemy.control_time = 60.0
	game.add_child(enemy)
	return enemy


func _has_formal_visual(
	game: Node,
	stable_skill_id: String,
	phase_id := ""
) -> bool:
	for child: Node in game.get_children():
		if (
			child is CasterSkillVisualEffect
			and child.skill_id == stable_skill_id
			and child.phase_id == phase_id
		):
			return true
	return false
