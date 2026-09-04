extends Node

const SkillDataLoader := preload("res://scripts/skills/skill_data_loader.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	PlayerState.profession = "法师"
	PlayerState.level = 6
	PlayerState.attack_ring_slots = ["", "", "", "", "", ""]
	PlayerState._sync_legacy_quick_slots_from_ring()

	# First book is rejected below the rank-0 player level gate without consuming.
	PlayerState.add_item("火球术", 5)
	var books_before := PlayerState.item_count("火球术")
	var result := PlayerState.learn_skill("火球术")
	assert(result.contains("需要人物等级"), "rank0 等级门槛未拒绝：%s" % result)
	assert(PlayerState.item_count("火球术") == books_before, "等级不足时错误消费了技能书")
	assert(not PlayerState.is_skill_learned("火球术"), "等级不足时不应学习技能")

	# 0 -> 1 -> 2 -> 3 with per-rank SOT gates; each upgrade consumes exactly one book.
	PlayerState.level = 7
	result = PlayerState.learn_skill("火球术")
	assert(result.begins_with("已学会"), "第一本书未学习：%s" % result)
	assert(PlayerState.item_count("火球术") == books_before - 1, "第一本书未消费")
	assert(PlayerState.skill_progression_snapshot().get("skills", {}).get("wizard.fireball", {}).get("base_rank", -1) == 0, "首学 rank 应为 0")
	assert(PlayerState.attack_ring_slots[0] == "火球术", "首学未自动填入空技能槽")
	assert(PlayerState.attack_ring_slots[1].is_empty(), "首学不应占用多个技能槽")

	result = PlayerState.learn_skill("火球术")
	assert(result.begins_with("技能提升"), "第二本书未升级：%s" % result)
	assert(PlayerState.skill_progression_snapshot().get("skills", {}).get("wizard.fireball", {}).get("base_rank", -1) == 1, "第二本应为 rank1")
	assert(PlayerState.attack_ring_slots[0] == "火球术" and PlayerState.attack_ring_slots[1].is_empty(), "升级重复绑定了技能槽")

	PlayerState.level = 10
	books_before = PlayerState.item_count("火球术")
	result = PlayerState.learn_skill("火球术")
	assert(result.contains("需要人物等级"), "rank2 等级门槛未拒绝：%s" % result)
	assert(PlayerState.item_count("火球术") == books_before, "rank2 门槛拒绝时错误消费")
	PlayerState.level = 11
	result = PlayerState.learn_skill("火球术")
	assert(result.begins_with("技能提升"), "第三本书未升级到 rank2：%s" % result)
	assert(PlayerState.skill_progression_snapshot().get("skills", {}).get("wizard.fireball", {}).get("base_rank", -1) == 2, "第三本应为 rank2")

	PlayerState.level = 15
	books_before = PlayerState.item_count("火球术")
	result = PlayerState.learn_skill("火球术")
	assert(result.contains("需要人物等级"), "rank3 等级门槛未拒绝：%s" % result)
	assert(PlayerState.item_count("火球术") == books_before, "rank3 门槛拒绝时错误消费")
	PlayerState.level = 16
	result = PlayerState.learn_skill("火球术")
	assert(result.begins_with("技能提升"), "第四本书未升级到 rank3：%s" % result)
	assert(PlayerState.skill_progression_snapshot().get("skills", {}).get("wizard.fireball", {}).get("base_rank", -1) == 3, "第四本应为 rank3")

	books_before = PlayerState.item_count("火球术")
	result = PlayerState.learn_skill("火球术")
	assert(result.contains("最高等级"), "满级后未拒绝：%s" % result)
	assert(PlayerState.item_count("火球术") == books_before, "满级拒绝时错误消费")
	assert(PlayerState.skill_progression_snapshot().get("skills", {}).get("wizard.fireball", {}).get("base_rank", -1) == 3, "满级拒绝不应改变 rank")

	# Wrong profession rejects without consuming.
	PlayerState.profession = "战士"
	books_before = PlayerState.item_count("火球术")
	result = PlayerState.learn_skill("火球术")
	assert(result.contains("只能由法师学习"), "职业错误未拒绝：%s" % result)
	assert(PlayerState.item_count("火球术") == books_before, "职业错误时错误消费")
	PlayerState.profession = "法师"

	# Unknown skill and missing book reject without consuming.
	result = PlayerState.learn_skill("不存在的技能书")
	assert(result.contains("技能数据不存在"), "未知技能未拒绝：%s" % result)
	books_before = PlayerState.item_count("火球术")
	var unknown_before := PlayerState.inventory.size()
	PlayerState.remove_item("火球术", PlayerState.item_count("火球术"))
	result = PlayerState.learn_skill("火球术")
	assert(result.contains("背包中缺少"), "无书未拒绝：%s" % result)
	assert(PlayerState.inventory.size() == unknown_before - int(books_before), "无书拒绝不应改动背包")

	# SkillDataLoader identity used by legacy names must be stable.
	assert(SkillDataLoader.stable_skill_id("火球术") == "wizard.fireball", "技能书中文名映射不稳定")
	assert(
		not PlayerState.skill_progression_snapshot().get("skills", {}).get("wizard.fireball", {}).has("current_proficiency"),
		"技能书升级不应产生熟练度"
	)

	print("SKILL_BOOK_RANK_UPGRADE_INTEGRATION_PASS: 0->1->2->3, max/level/profession/unknown/no-book rejects, no consumption, first-learn-only bind")
	get_tree().quit(0)
