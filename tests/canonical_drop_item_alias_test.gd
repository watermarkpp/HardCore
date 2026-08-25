extends Node

const SkillDataLoader := preload(
	"res://scripts/skills/skill_data_loader.gd"
)


const ALIAS_EXPECTATIONS := {
	# Existing audited raw-source aliases.
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

	# ITEM-P0C exact compatibility aliases.
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
}


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
	"道力神水": 910014,
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
	# 1. Exact aliases
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

	# --------------------------------------------------
	# 2. Project drop Item authority
	# --------------------------------------------------

	assert(
		str(
			GameData.canonical_drop_item_authority.get(
				"contractId", ""
			)
		)
		== "item.canonical_drop_authority.v1"
	)

	assert(
		(
			GameData.canonical_drop_item_authority.get(
				"items", []
			) as Array
		).size()
		== 14
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

		# ITEM-P0 deliberately prevents these special potions
		# from falling into the current generic 神水 behavior.
		assert(
			record.get("usable", true) == false,
			"special potion unexpectedly executable: %s"
			% item_name
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
	# 3. ALL canonical drop rows must resolve.
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

	assert(
		total_drop_rows == 7032,
		"canonical drop row count drifted: %d"
		% total_drop_rows
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
	# 5. Do NOT change current skill-book / 万年雪霜
	#    stackability just to satisfy the old audit heuristic.
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

	assert(
		mass_heal_book.get(
			"stackable", true
		) == false
	)

	var snow_frost := GameData.get_item_record(
		"万年雪霜"
	)

	assert(
		snow_frost.get(
			"stackable", true
		) == false
	)

	# Formal skill SOT already contains 群体治疗术.
	assert(
		SkillDataLoader.reload_data().valid
	)

	assert(
		SkillDataLoader.stable_skill_id(
			"群体治疗术"
		)
		== "taoist.mass_healing"
	)

	print(
		"CANONICAL_DROP_ITEM_ALIAS_PASS: "
		+ "drop_rows=7032 unresolved=0 "
		+ "authority_items=14 aliases=%d "
		% ALIAS_EXPECTATIONS.size()
		+ "spawnable=153"
	)

	get_tree().quit(0)


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
