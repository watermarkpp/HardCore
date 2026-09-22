extends Node

const CANONICAL_MONSTERS := {
	21: "稻草人",
	26: "钉耙猫",
	24: "多钩猫",
	34: "半兽人",
	36: "半兽战士",
	28: "森林雪人",
	30: "食人花",
	18: "毒蜘蛛",
	47: "骷髅",
	56: "骷髅精灵",
	89: "尸王",
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(not GameData.bich_community_baseline.is_empty(), "比奇社区基准未加载")
	var summary: Dictionary = GameData.bich_community_baseline.get("summary", {})
	assert(int(summary.get("monsterOverrides", 0)) >= 20, "社区怪物覆盖不足")
	assert(int(summary.get("spawnGroups", 0)) == 25, "D001—D003刷新组数量异常")
	assert(int(summary.get("runtimeDropMonsters", 0)) == 10, "社区运行掉落怪物数量异常")
	assert(int(summary.get("runtimeDropSlots", 0)) <= 50, "社区运行掉落槽过多")
	for monster_id: int in [21, 34, 47, 56, 89]:
		var name: String = CANONICAL_MONSTERS[monster_id]
		var monster: Dictionary = GameData.get_monster_by_id(monster_id)
		assert(not monster.is_empty(), "缺少社区怪物：%s" % name)
		assert(
			int(monster.get("monster_id", -1)) == monster_id
			and str(monster.get("canonical_name", "")) == name,
			"社区怪物身份漂移：%d/%s" % [monster_id, name]
		)
		var timing: Dictionary = monster.get("combat", {}).get("timing", {})
		assert(
			int(timing.get("attack_interval_ms", 0)) > 0,
			"%s未接入canonical攻击间隔" % name
		)
		assert(
			str(timing.get("resolution_status", ""))
			== "user_authoritative_21cq",
			"%s攻击间隔未遵循当前用户权威" % name
		)
		var timing_evidence: Dictionary = monster.get(
			"source_evidence", {}
		).get("combat_ai_timing", {}).get("detail", {})
		assert(
			str(timing_evidence.get("distribution", ""))
			== "user.21cq.com.mir.monster_detail"
			and str(timing_evidence.get("role", ""))
			== "monster_21cq_detail_timing_and_life_flags",
			"%s canonical攻击间隔来源证据缺失" % name
		)
	var player := PlayerCharacter.new()
	var enemy := EnemyActor.new()
	enemy.setup(GameData.get_monster_by_id(21), player, false)
	assert(is_equal_approx(enemy._attack_interval, 2.5), "普通怪没有使用社区攻击间隔")
	var boss := EnemyActor.new()
	boss.setup(GameData.get_monster_by_id(89), player, true)
	assert(is_equal_approx(boss._attack_interval, 2.8), "尸王社区时序与Boss规则没有一致接入")
	assert(GameData.is_dpv2_direct_baseline_loaded(), "DPV2 direct掉落权威未加载")
	for monster_id: int in [21, 26, 24, 34, 36, 28, 30, 18, 56, 89]:
		var name: String = CANONICAL_MONSTERS[monster_id]
		var profile: Dictionary = GameData.dpv2_direct_profile(monster_id)
		assert(
			int(profile.get("canonical_monster_id", -1)) == monster_id
			and str(profile.get("canonical_monster_name", "")) == name
			and str(profile.get("drop_profile_id", ""))
			== "dpv2.direct.%d" % monster_id,
			"%s DPV2掉落身份异常" % name
		)
		assert(
			bool(profile.get("runtime_allowed", false))
			and bool(profile.get("drop_enabled", false)),
			"%s DPV2掉落未启用" % name
		)
		var slots: Array = profile.get("slots", [])
		assert(not slots.is_empty(), "%s DPV2掉落槽为空" % name)
		var seen_slot_uids := {}
		for raw_slot: Variant in slots:
			assert(raw_slot is Dictionary, "%s DPV2掉落槽格式异常" % name)
			var slot: Dictionary = raw_slot
			var slot_uid := str(slot.get("slot_uid", ""))
			assert(
				slot_uid.begins_with("dpv2.direct.m%d." % monster_id)
				and not seen_slot_uids.has(slot_uid),
				"%s DPV2掉落槽身份异常:%s" % [name, slot_uid]
			)
			seen_slot_uids[slot_uid] = true
			var reward: Dictionary = GameData.dpv2_direct_resolve_slot_reward(slot)
			assert(bool(reward.get("ok", false)), "%s掉落物无法解析:%s" % [name, slot_uid])
			if str(reward.get("kind", "")) == "item":
				assert(
					not GameData.get_item_record(
						str(reward.get("item_name", ""))
					).is_empty(),
					"%s掉落物未进入物品目录:%s" % [name, slot_uid]
				)
			else:
				assert(int(reward.get("gold_amount", 0)) > 0, "%s金币掉落无效" % name)
			var probability: Dictionary = GameData.dpv2_direct_slot_probability(
				monster_id, slot_uid
			)
			var base_numerator := int(probability.get("base_numerator", 0))
			var base_denominator := int(probability.get("base_denominator", 0))
			var final_numerator := int(probability.get("final_numerator", 0))
			var final_denominator := int(probability.get("final_denominator", 0))
			assert(
				bool(probability.get("ok", false))
				and base_numerator > 0
				and base_numerator <= base_denominator
				and final_numerator > 0
				and final_numerator <= final_denominator,
				"%s掉落概率无效:%s" % [name, slot_uid]
			)
	player.free()
	enemy.free()
	boss.free()
	print("BICH_COMMUNITY_BASELINE_PASS：社区怪物时序、来源、刷新画像和Boss覆盖正常")
	get_tree().quit(0)
