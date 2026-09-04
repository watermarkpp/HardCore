extends Node

const SkillDataLoader := preload(
	"res://scripts/skills/skill_data_loader.gd"
)

const DROP_AUTHORING_OVERLAY_PATH := (
	"res://assets/data/"
	+ "canonical_monster_drop_authoring_overrides_v1.json"
)
const BASE_CANONICAL_DROP_ROW_COUNT := 7032


# ITEM-P0C-FULL: 9 aliases (4 legacy source + 5 runtime authority).
const ALIAS_EXPECTATIONS := {
	# Existing audited raw-source aliases (4).
	"毒蜘蛛牙齿": {
		"canonical": "蜘蛛牙",
		"service_index": 868,
	},
	"食人树叶": {
		"canonical": "食人花叶",
		"service_index": 866,
	},
	"食人树的果实": {
		"canonical": "食人花果",
		"service_index": 867,
	},
	"蝎子的尾巴": {
		"canonical": "蝎尾",
		"service_index": 873,
	},

	# ITEM-P0C-FULL: runtime authority exact aliases (5).
	"篮翡翠项链": {
		"canonical": "蓝翡翠项链",
		"item_id": 165,
	},
	"铂金项链": {
		"canonical": "白金项链",
		"item_id": 155,
	},
	"群体治愈术": {
		"canonical": "群体治疗术",
		"service_index": 1029,
	},
	"极速神水": {
		"canonical": "疾风药水",
		"item_id": 910013,
	},
	"道力神水": {
		"canonical": "精神神水",
		"item_id": 910006,
	},
}


# ITEM-P0C-FULL: 13 runtime authority newItems.
const AUTHORITY_ITEM_IDS := {
	"体力强效神水": 910001,
	"魔力强效神水": 910002,
	"疾风神水": 910003,
	"攻击神水": 910004,
	"魔力神水": 910005,
	"精神神水": 910006,
	"疗伤药": 910007,
	"HP强化水": 910008,
	"MP强化水": 910009,
	"攻击力药水": 910010,
	"魔法力药水": 910011,
	"道术力药水": 910012,
	"疾风药水": 910013,
}


const FORBIDDEN_QUEST_SERVICE_INDEX := 1127


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(
		GameData.ensure_loaded(),
		"GameData canonical catalog failed to load"
	)

	# --------------------------------------------------
	# 1. Exact aliases: 9 total (4 legacy + 5 authority)
	# --------------------------------------------------

	for token: String in ALIAS_EXPECTATIONS:
		var expected: Dictionary = ALIAS_EXPECTATIONS[token]

		var resolved := GameData.resolve_canonical_drop_item({
			"item": token,
		})

		assert(
			bool(resolved.get("ok", false)),
			"drop token did not resolve: %s -> %s"
			% [token, resolved]
		)

		assert(
			str(resolved.get("item_name", ""))
			== str(expected.get("canonical", "")),
			"wrong canonical item: %s -> %s"
			% [token, resolved]
		)

		if expected.has("item_id"):
			assert(
				int(resolved.get("item_id", -1))
				== int(expected.get("item_id", -1)),
				"wrong item_id: %s -> %s"
				% [token, resolved]
			)

		if expected.has("service_index"):
			assert(
				int(resolved.get("service_index", -1))
				== int(expected.get("service_index", -1)),
				"wrong service_index: %s -> %s"
				% [token, resolved]
			)

	# Preserve the already-audited 食人树 fruit distinction.
	var fruit := GameData.resolve_canonical_drop_item({
		"item": "食人树的果实",
	})

	assert(
		int(fruit.get("service_index", -1)) == 867
	)

	assert(
		int(fruit.get("service_index", -1))
		!= FORBIDDEN_QUEST_SERVICE_INDEX
	)

	# Legacy 4 aliases still resolve through ITEM_ALIASES directly.
	assert(
		str(
			GameData.resolve_canonical_drop_item({"item": "毒蜘蛛牙齿"}).get(
				"item_name", ""
			)
		)
		== "蜘蛛牙"
	)

	# --------------------------------------------------
	# 2. Runtime authority: 13 newItems + contract shape
	# --------------------------------------------------

	var authority: Dictionary = GameData.item_runtime_authority

	assert(
		str(authority.get("contractId", ""))
		== "item.runtime.authority.v1"
	)

	assert(
		(authority.get("newItems", []) as Array).size() == 13
	)

	var aliases_value: Variant = authority.get("aliases", {})
	assert(
		aliases_value is Dictionary
		and (aliases_value as Dictionary).size() == 5
	)

	var observed_item_ids := {}

	for item_name: String in AUTHORITY_ITEM_IDS:
		var expected_id := int(
			AUTHORITY_ITEM_IDS[item_name]
		)

		var record := GameData.get_item_record(
			item_name
		)

		assert(
			not record.is_empty(),
			"authority item missing: %s"
			% item_name
		)

		assert(
			_stable_item_id(record) == expected_id,
			"authority item id mismatch: %s -> %s"
			% [item_name, record]
		)

		assert(
			not observed_item_ids.has(expected_id),
			"duplicate authority item id: %d"
			% expected_id
		)

		observed_item_ids[expected_id] = item_name

		assert(
			str(record.get("kind", ""))
			== "consumable"
		)

		assert(
			not str(
				record.get("category", "")
			).is_empty()
		)

		assert(
			int(record.get("weight", 0)) > 0,
			"authority item weight missing: %s"
			% item_name
		)

		var art: Dictionary = record.get("art", {})

		assert(
			not _art_path(
				art.get("inventoryIcon", null)
			).is_empty(),
			"inventory art missing: %s"
			% item_name
		)

		assert(
			not _art_path(
				art.get("groundIcon", null)
			).is_empty(),
			"ground art missing: %s"
			% item_name
		)

	# --------------------------------------------------
	# 3. ALL canonical drop rows must resolve (7032).
	# --------------------------------------------------

	var entries: Dictionary = (
		GameData.canonical_monster_catalog.get(
			"entries_by_id", {}
		)
	)

	var profiles: Dictionary = (
		GameData.canonical_monster_catalog.get(
			"drop_profiles", {}
		)
	)

	var total_drop_rows := 0
	var unresolved := []

	for raw_entry: Variant in entries.values():
		assert(raw_entry is Dictionary)

		var monster: Dictionary = raw_entry
		var monster_id := int(
			monster.get("monster_id", -1)
		)

		var profile_id := str(
			monster.get("drop_profile_id", "")
		)

		var profile_value: Variant = profiles.get(
			profile_id, {}
		)

		assert(
			profile_value is Dictionary,
			"drop profile missing: monster=%d profile=%s"
			% [monster_id, profile_id]
		)

		var profile: Dictionary = profile_value

		for raw_drop: Variant in profile.get(
			"entries", []
		):
			assert(raw_drop is Dictionary)

			total_drop_rows += 1

			var reward := (
				GameData.resolve_canonical_drop_reward(
					raw_drop
				)
			)

			if not bool(
				reward.get("ok", false)
			):
				unresolved.append({
					"monster_id": monster_id,
					"profile_id": profile_id,
					"item": str(
						raw_drop.get("item", "")
					),
					"reason": str(
						reward.get(
							"reason", ""
						)
					),
				})

	var expected_drop_rows := (
		BASE_CANONICAL_DROP_ROW_COUNT
		+ _expected_authoring_row_count(profiles.size())
	)
	assert(
		total_drop_rows == expected_drop_rows,
		"canonical drop row count drifted: observed=%d expected=%d"
		% [total_drop_rows, expected_drop_rows]
	)

	assert(
		unresolved.is_empty(),
		"canonical unresolved drop rows remain: %s"
		% str(unresolved)
	)

	# --------------------------------------------------
	# 4. Monster runtime closure remains complete.
	# --------------------------------------------------

	var counts := GameData.canonical_monster_counts()

	assert(
		int(
			counts.get(
				"catalog_identity_count", 0
			)
		) == 156
	)

	assert(
		int(
			counts.get(
				"catalog_runtime_allowed_count", 0
			)
		) == 153
	)

	assert(
		int(
			counts.get(
				"runtime_spawnable_count", 0
			)
		) == 153
	)

	assert(
		int(
			counts.get(
				"runtime_rejected_count", -1
			)
		) == 0
	)

	# --------------------------------------------------
# 5. Every skill book is non-stackable and carries the level-up explanation.
	# --------------------------------------------------

	var skill_book_stackable_count := 0
	var skill_book_non_stackable_count := 0

	for record: Variant in GameData.item_catalog:
		if not record is Dictionary:
			continue
		if str(record.get("kind", "")) != "skill_book":
			continue
		if bool(record.get("stackable", false)):
			skill_book_stackable_count += 1
		else:
			skill_book_non_stackable_count += 1
		assert(int(record.get("maxStack", 0)) == 1, str(record))
		assert(
			"使用技能书可以使对应技能等级+1，技能最高3级。"
			in str(record.get("description", "")),
			"skill book description missing: %s" % str(record.get("name", "")),
		)

	assert(
		skill_book_stackable_count == 0,
		"skill books must not stack, got %d stackable records"
		% skill_book_stackable_count,
	)
	assert(
		skill_book_non_stackable_count == 106,
		"expected 106 non-stackable skill books, got %d"
		% skill_book_non_stackable_count,
	)
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.add_item("基本剑术", 2)
	var basic_sword_book_slots := 0
	for inventory_record: Variant in PlayerState.inventory:
		if (
			inventory_record is Dictionary
			and str((inventory_record as Dictionary).get("name", "")) == "基本剑术"
		):
			basic_sword_book_slots += 1
			assert(int((inventory_record as Dictionary).get("count", 0)) == 1)
	assert(basic_sword_book_slots == 2, "two skill books must occupy two slots")
	PlayerState.reset_progress()

	# --------------------------------------------------
	# 6. 万年雪霜 is stackable via authority policy.
	# --------------------------------------------------

	var snow_frost := GameData.get_item_record(
		"万年雪霜"
	)

	assert(
		not snow_frost.is_empty(),
		"万年雪霜 missing from catalog"
	)

	assert(
		bool(snow_frost.get("stackable", false)),
		"万年雪霜 should be stackable"
	)

	# --------------------------------------------------
	# 7. Non-stacking items remain non-stackable.
	# --------------------------------------------------

	var mass_heal_book := GameData.get_item_record(
		"群体治疗术"
	)

	assert(
		int(
			mass_heal_book.get(
				"serviceIndex",
				mass_heal_book.get(
					"service_index", -1
				)
			)
		) == 1029
	)

	# Formal skill SOT still contains 群体治疗术.
	assert(
		SkillDataLoader.reload_data().valid
	)

	assert(
		SkillDataLoader.stable_skill_id(
			"群体治疗术"
		)
		== "taoist.mass_healing"
	)

	# --------------------------------------------------
	# 8. Temporary buff mechanics.
	# --------------------------------------------------

	var buff_result := PlayerState.apply_temporary_item_buff(
		"测试药水",
		{
			"contractId": "item.temporary_stat_buff.v1",
			"buffGroup": "max_hp",
			"durationSeconds": 60.0,
			"modifiers": {"max_hp": 100, "attack_max": 5},
		}
	)

	assert(
		bool(buff_result.get("ok", false)),
		"temporary buff application failed: %s"
		% buff_result
	)

	assert(
		PlayerState.temporary_item_buff_revision > 0,
		"buff revision not incremented"
	)

	var buff_entry: Dictionary = PlayerState.temporary_item_buffs.get(
		"测试药水", {}
	)

	assert(
		not buff_entry.is_empty(),
		"buff entry not found in temporary_item_buffs"
	)

	assert(
		float(buff_entry.get("remaining", 0.0)) > 0.0,
		"buff remaining duration is zero"
	)

	PlayerState.advance_temporary_item_buffs(
		999999.0
	)

	assert(
		PlayerState.temporary_item_buffs.is_empty(),
		"buffs not cleared after advance with large delta"
	)

	# --------------------------------------------------
	# 9. HP preservation across buff stat changes.
	# --------------------------------------------------

	var stats_before: Dictionary = PlayerState.computed_stats.duplicate(true)
	var hp_before := int(stats_before.get("max_hp", 120))

	PlayerState.apply_temporary_item_buff(
		"HP测试",
		{
			"contractId": "item.temporary_stat_buff.v1",
			"buffGroup": "max_hp",
			"durationSeconds": 30.0,
			"modifiers": {"max_hp": 200},
		}
	)

	var stats_after: Dictionary = PlayerState.computed_stats.duplicate(true)
	var hp_after := int(stats_after.get("max_hp", hp_before))

	assert(
		hp_after > hp_before,
		"max_hp should increase after buff: %d -> %d"
		% [hp_before, hp_after]
	)

	# Clear the buff for test cleanup
	PlayerState.advance_temporary_item_buffs(999999.0)
	PlayerState.recalculate_stats()

	# --------------------------------------------------
	# 10. Print summary.
	# --------------------------------------------------

	var alias_count := ALIAS_EXPECTATIONS.size()

	print(
		"CANONICAL_DROP_ITEM_ALIAS_PASS: "
		+ "drop_rows=%d unresolved=0 " % total_drop_rows
		+ "authority_items=13 aliases=%d "
		% alias_count
		+ "non_stackable_skill_books=%d "
		% skill_book_non_stackable_count
		+ "spawnable=153"
	)

	get_tree().quit(0)


func _expected_authoring_row_count(
	profile_count: int
) -> int:
	assert(
		FileAccess.file_exists(
			DROP_AUTHORING_OVERLAY_PATH
		)
	)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(
			DROP_AUTHORING_OVERLAY_PATH
		)
	)
	assert(parsed is Dictionary)
	var overlay: Dictionary = parsed

	var enabled_global := 0
	for raw: Variant in overlay.get(
		"global_additions", []
	):
		if raw is Dictionary and bool(
			raw.get("enabled", false)
		):
			enabled_global += 1

	var enabled_monster := 0
	for raw: Variant in overlay.get(
		"monster_additions", []
	):
		if raw is Dictionary and bool(
			raw.get("enabled", false)
		):
			enabled_monster += 1

	return (
		enabled_global * profile_count
		+ enabled_monster
	)


func _stable_item_id(
	record: Dictionary
) -> int:
	for key: String in [
		"item_id",
		"itemId",
		"stableItemId",
		"id",
	]:
		if record.has(key):
			var value := int(
				record.get(key, -1)
			)

			if value >= 0:
				return value

	return -1


func _art_path(
	value: Variant
) -> String:
	if value is String:
		return str(value)

	if value is Dictionary:
		return str(
			value.get("path", "")
		)

	return ""
