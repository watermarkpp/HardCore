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
	assert(_has_formal_visual(game, "taoist.summon_divine_beast"), "召唤神兽正式施法视觉未从canonical入口创建")
	var first_pet_id := main_pet.get_instance_id()
	var recall: Dictionary = game._execute_canonical_skill("召唤神兽", caster.global_position, Vector2.DOWN, 0)
	assert(bool(recall.get("accepted", false)) and game._canonical_main_pet().get_instance_id() == first_pet_id, "已有道士主宠未执行召回而是替换")

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


func _has_formal_visual(game: Node, stable_skill_id: String) -> bool:
	for child: Node in game.get_children():
		if child is CasterSkillVisualEffect and child.skill_id == stable_skill_id:
			return true
	return false
