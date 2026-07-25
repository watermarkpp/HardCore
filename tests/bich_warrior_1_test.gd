extends Node

const WARRIOR_SKILLS := ["基本剑术", "攻杀剑术", "刺杀剑术", "半月弯刀", "野蛮冲撞", "烈火剑法"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for skill_name: String in WARRIOR_SKILLS:
		var profile := ProfessionRules.skill_profile(skill_name)
		assert(not profile.is_empty() and str(profile.get("profession", "")) == "战士", "%s未从职业成长表注册" % skill_name)
		assert(int(profile.get("service_magic_id", -1)) >= 0, "%s缺少服务端MagicId" % skill_name)
	var policy := ContentLayers.policy_override("warrior_basic_attack_mobile")
	assert(int(policy.get("vanillaValue", 0)) == 600 and int(policy.get("overrideValue", 0)) == 850, "600ms服务端基准与850ms手机策略没有同时保留")
	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	assert(is_equal_approx(player.attack_cooldown, 0.9) and is_equal_approx(player.attack_animation_duration, 0.51), "续刀或完整收招时序错误")
	player.set_combat_facing(Vector2.LEFT)
	assert(player.facing.is_equal_approx(Vector2.LEFT) and player.request_attack(), "攻击事务没有锁定目标方向")
	player.set_touch_vector(Vector2.RIGHT)
	await get_tree().physics_frame
	assert(player.velocity == Vector2.ZERO, "完整攻击动作结束前仍可移动")
	player.queue_free()

	var wood_sword := GameData.get_item("木剑")
	wood_sword["modifiers"] = [
		{"stat": "attack_speed", "op": "add", "value": 0.20},
		{"stat": "cast_speed", "op": "add", "value": 0.25},
		{"stat": "critical_chance", "op": "add", "value": 0.10},
		{"stat": "skill_level", "op": "add", "value": 2, "skill": "烈火剑法"},
	]
	PlayerState.learned_skills = {"烈火剑法": 1}
	PlayerState.add_item("木剑")
	var index := -1
	for candidate in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[candidate].get("name", "")) == "木剑":
			index = candidate
			break
	assert(index >= 0 and PlayerState.equip_inventory_index(index).begins_with("已装备"), "数据驱动装备无法装备")
	assert(is_equal_approx(float(PlayerState.computed_stats.attack_speed_percent), 0.20), "数组式攻速词条未进入战斗属性")
	assert(is_equal_approx(float(PlayerState.computed_stats.cast_speed_percent), 0.25), "数组式施法速度词条未进入战斗属性")
	assert(is_equal_approx(float(PlayerState.computed_stats.critical_chance), 0.10), "数组式暴击词条未进入战斗属性")
	assert(PlayerState.effective_skill_level("烈火剑法") == 3, "数组式技能等级词条未生效")
	print("BICH_WARRIOR_1_PASS：基础攻击、六技能数据与通用装备属性联动正常")
	get_tree().quit(0)
