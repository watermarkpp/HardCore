extends Node


const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")


func _test_ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(value)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var rule: Dictionary = GameData.boss_service_rules.get("runtimeRulesByMonsterId", {}).get("89", {})
	assert(int(rule.get("serviceRace", 0)) == 81 and rule.get("serviceClass", "") == "TATMonster", "尸王服务端类映射错误")
	assert(not bool(rule.get("specialSkill", {}).get("enabled", true)) and not bool(rule.get("phaseTwo", {}).get("enabled", true)), "尸王仍保留无来源范围技能")

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	# 固定战斗夹具，避免本地存档中的魔法盾/复活装备污染命中断言。
	player.max_hp = 500
	player.current_hp = 500
	player.max_mp = 0
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2.RIGHT * 1.5)
	var boss := EnemyActor.new()
	var canonical_monster: Dictionary = GameData.get_monster_by_id(89)
	assert(not canonical_monster.is_empty(), "尸王 canonical monster_id=89 未加载")
	boss.setup(canonical_monster, player, true)
	# ID 89 is classified as an elite spawn in the canonical map catalog, while
	# the service evidence still defines its Race81/TATMonster timing.  Project
	# that ID-keyed boss rule explicitly for this mechanics fixture; production
	# setup remains classification-authoritative and never uses the caller flag.
	var canonical_boss_rule: Dictionary = MonsterIdentityScript.boss_rule(
		canonical_monster,
		GameData.boss_service_rules,
	)
	assert(not canonical_boss_rule.is_empty(), "尸王 ID 89 缺少 canonical boss rule")
	boss.is_boss = true
	boss.boss_rule = canonical_boss_rule
	boss._apply_boss_rule()
	boss.configure_runtime_map_projection(
		1,
		Callable(self, "_test_ground_to_screen")
	, GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu)
	add_child(boss)
	boss.set_physics_process(false)
	await get_tree().process_frame
	var visual: MonsterVisual = boss.get_node("MonsterVisual")
	var sprite: Sprite2D = visual.get_node("BodySprite")
	var art: Dictionary = GameData.bich_undead_art.get("runtimeMappings", {}).get("尸王", {})
	var expected_frame := Vector2i(int(art.frameSize[0]), int(art.frameSize[1]))
	var expected_foot := Vector2i(int(art.footAnchor[0]), int(art.footAnchor[1]))
	assert(visual.uses_final_art() and visual.frame_size == expected_frame, "尸王客户端资源未启用")
	assert(visual.actor_ground_offset == Vector2i(32, 28), "尸王未采用经典客户端角色原点迁移量")
	assert(
		sprite.position == -Vector2(expected_foot + visual.actor_ground_offset)
		and (
			visual.position + visual.visual_foot_offset()
		).is_zero_approx(),
		"尸王绘制原点或人工脚点不在怪物逻辑原点",
	)
	assert(is_equal_approx(boss.overhead.position.y, boss.health_bar_anchor_y()), "尸王头顶层未按固定动画帧锚点定位")
	assert(boss.overhead.name_global_bottom_y() < boss.overhead.bar_global_top_y(), "尸王名称没有固定在血条上方")
	assert(boss.max_hp == 500 and boss.attack_min == 18 and boss.attack_max == 36, "尸王2003候选属性未采用")
	assert(is_equal_approx(boss._attack_interval, 2.8) and is_equal_approx(boss._attack_animation_duration, 0.72) and is_equal_approx(boss._attack_hit_delay, 0.36), "尸王速度或命中帧错误")

	var hp_before := player.current_hp
	boss._physics_process(0.01)
	assert(boss._pending_attack_time > 0.0 and player.current_hp == hp_before, "尸王伤害没有等待命中帧")
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2.DOWN * 1.5)
	boss._physics_process(0.12)
	var expected_attack_facing_px := GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2.DOWN).normalized()
	assert(boss.facing.dot(expected_attack_facing_px) > 0.99 and boss.velocity == Vector2.ZERO, "尸王追击/攻击时没有持续面对玩家")
	boss._physics_process(0.25)
	assert(player.current_hp < hp_before, "尸王客户端命中帧没有结算伤害")
	var speed_before := boss.move_speed_gu_per_sec
	boss.take_damage(251)
	assert(not boss._boss_phase_two and boss.move_speed_gu_per_sec == speed_before and boss._boss_warning <= 0.0, "尸王仍触发无来源狂暴或震地")
	boss.set_targeted(true)
	assert(boss.is_targeted, "尸王选中状态没有生效")
	assert(boss.ground_indicator_center().is_zero_approx(), "尸王地面锁定光圈未固定在怪物物理原点")
	print("CORPSE_KING_BOSS_PASS：Race81/TATMonster、2.8秒攻击、命中帧、持续朝向、无伪技能与脚底选中正常")
	get_tree().quit(0)
