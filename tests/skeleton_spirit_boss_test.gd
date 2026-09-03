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
	var rules: Dictionary = GameData.boss_service_rules
	assert(rules.get("serviceEvidence", {}).get("confidence", "") == "A", "Boss服务端类证据必须保持A级")
	var rule: Dictionary = rules.get("runtimeRulesByMonsterId", {}).get("56", {})
	assert(int(rule.get("serviceRace", 0)) == 89 and rule.get("serviceClass", "") == "TATMonster", "骷髅精灵服务端类映射错误")
	assert(not bool(rule.get("specialSkill", {}).get("enabled", true)) and not bool(rule.get("phaseTwo", {}).get("enabled", true)), "骷髅精灵仍保留无来源项目技能")

	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	# 固定战斗夹具，避免本地存档中的防御、魔法盾或复活装备污染命中断言。
	player.max_hp = 500
	player.current_hp = 500
	player.max_mp = 0
	player.current_mp = 0
	player.defense_min = 0
	player.defense_max = 0
	player.global_position = GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2.RIGHT * 1.5)
	var boss := EnemyActor.new()
	var canonical_monster: Dictionary = GameData.get_monster_by_id(56)
	assert(not canonical_monster.is_empty(), "骷髅精灵 canonical monster_id=56 未加载")
	boss.setup(canonical_monster, player, true)
	# ID 56 is classified as an elite spawn in the canonical map catalog, while
	# the service evidence still defines its Race89/TATMonster timing.  Project
	# that ID-keyed boss rule explicitly for this mechanics fixture; production
	# setup remains classification-authoritative and never uses the caller flag.
	var canonical_boss_rule: Dictionary = MonsterIdentityScript.boss_rule(
		canonical_monster,
		GameData.boss_service_rules,
	)
	assert(not canonical_boss_rule.is_empty(), "骷髅精灵 ID 56 缺少 canonical boss rule")
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
	var art: Dictionary = GameData.bich_undead_art.get("runtimeMappings", {}).get("骷髅精灵", {})
	var expected_frame := Vector2i(int(art.frameSize[0]), int(art.frameSize[1]))
	var expected_foot := Vector2i(int(art.footAnchor[0]), int(art.footAnchor[1]))
	assert(visual.uses_final_art() and visual.frame_size == expected_frame, "骷髅精灵Boss客户端资源未启用")
	assert(visual.actor_ground_offset == Vector2i(32, 28), "骷髅精灵未采用经典客户端角色原点迁移量")
	assert(sprite.texture.get_size() == Vector2(expected_frame.x * 4, expected_frame.y * 8) and sprite.position == -Vector2(expected_foot + visual.actor_ground_offset), "骷髅精灵图集或绘制原点迁移错误")
	assert(
		visual.position.is_equal_approx(visual.reviewed_visual_origin())
		and (
			visual.position
			+ visual.visual_foot_offset()
		).is_zero_approx()
		and visual.manual_alignment_replay_displacement().y > 0.0
		and is_equal_approx(
			boss.overhead.position.y, boss.health_bar_anchor_y()
		),
		"骷髅精灵脚底/头顶层高度错误",
	)
	assert(boss.overhead.name_global_bottom_y() < boss.overhead.bar_global_top_y(), "骷髅精灵名称没有固定在血条上方")
	assert(boss.max_hp == 500 and boss.attack_min == 7 and boss.attack_max == 24, "骷髅精灵2003候选属性未采用")
	assert(is_equal_approx(boss._attack_interval, 2.0) and is_equal_approx(boss._attack_animation_duration, 0.6) and is_equal_approx(boss._attack_hit_delay, 0.3), "骷髅精灵速度或命中帧错误")
	assert(not boss._boss_skill_enabled and not boss._boss_phase_enabled, "骷髅精灵项目技能开关未关闭")

	var hp_before := player.current_hp
	# This fixture validates attack timing, not target-acquisition staggering.
	# Pin the already-authorized player target so an unrelated acquisition policy
	# cannot prevent the attack from reaching its hit-frame assertions.
	boss.target = player
	boss._attack_timer = 0.0
	boss._physics_process(0.01)
	assert(
		boss._pending_attack_time > 0.0 and player.current_hp == hp_before,
		"骷髅精灵伤害没有等待客户端命中帧 pending=%.3f hp=%d/%d target_valid=%s" % [
			boss._pending_attack_time,
			player.current_hp,
			hp_before,
			str(is_instance_valid(boss.target)),
		]
	)
	var expected_attack_facing_px := GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(Vector2.RIGHT).normalized()
	assert(boss.facing.dot(expected_attack_facing_px) > 0.99 and boss.velocity == Vector2.ZERO, "骷髅精灵攻击时未面对目标或仍在移动")
	visual._process(0.05)
	assert(visual.current_state == "attack" and sprite.texture.get_size() == Vector2(expected_frame.x * 6, expected_frame.y * 8), "骷髅精灵攻击动画未触发")
	boss._physics_process(0.28)
	assert(player.current_hp == hp_before, "骷髅精灵命中帧提前")
	boss._physics_process(0.03)
	assert(player.current_hp < hp_before and boss._pending_attack_time < 0.0, "骷髅精灵命中帧没有结算伤害")
	assert(boss._retarget_timer > 7.0, "TATMonster八秒重新寻敌节奏未接入")

	var speed_before := boss.move_speed_gu_per_sec
	boss.take_damage(251)
	assert(not boss._boss_phase_two and boss.move_speed_gu_per_sec == speed_before, "骷髅精灵仍触发无来源半血狂暴")
	boss.take_damage(999)
	assert(boss._death_pending and not boss._dying, "致死伤害没有等待对象周期结束")
	boss._physics_process(0.0)
	visual._process(0.02)
	assert(boss._dying and visual.current_state == "death", "骷髅精灵死亡动画未触发")
	await get_tree().create_timer(0.90).timeout
	assert(
		is_instance_valid(boss)
		and visual.current_state == "death"
		and visual._death_pose_held,
		"骷髅精灵死亡末帧没有作为尸体保留"
	)
	await get_tree().create_timer(2.10).timeout
	assert(not is_instance_valid(boss), "骷髅精灵尸体保留期结束后未移除")
	print("SKELETON_SPIRIT_BOSS_PASS：Race89/TATMonster、2秒攻击、命中帧、朝向、无伪技能、延迟死亡与尸体保留正常")
	get_tree().quit(0)
