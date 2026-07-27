extends Node


const CATALOG_PATH := "res://assets/data/equipment_visual_catalog.json"
const LOADOUT_PATH := "res://assets/data/equipment_test_loadouts.json"
const VISUAL_CATEGORIES := ["武器", "盔甲", "头盔"]
const ACTION_FRAMES := {
	"idle": 4,
	"walk": 6,
	"attack": 6,
	"cast": 6,
	"hit": 3,
	"death": 4,
}


func _ready() -> void:
	_run.call_deferred()


func _json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), "缺少数据文件：%s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed is Dictionary, "JSON 不是对象：%s" % path)
	return parsed


func _resource_exists(mapping: Dictionary, label: String) -> void:
	var path := str(mapping.get("path", ""))
	assert(not path.is_empty(), "%s 缺少资源路径" % label)
	assert(FileAccess.file_exists(path), "%s 资源不存在：%s" % [label, path])


func _validate_actions(appearance: Dictionary, label: String, require_imported := true) -> void:
	assert(bool(appearance.get("visible", false)), "%s 不应是隐藏映射" % label)
	var actions: Dictionary = appearance.get("actions", {})
	for action_name: String in ACTION_FRAMES:
		var action: Dictionary = actions.get(action_name, {})
		if require_imported:
			_resource_exists(action, "%s/%s" % [label, action_name])
		else:
			assert(FileAccess.file_exists(str(action.get("path", ""))), "%s/%s 源图不存在" % [label, action_name])
		assert(int(action.get("directions", 0)) == 8, "%s/%s 必须是八方向" % [label, action_name])
		assert(int(action.get("framesPerDirection", 0)) == int(ACTION_FRAMES[action_name]), "%s/%s 帧数错误" % [label, action_name])
		assert(action.get("missingFrames", []).is_empty(), "%s/%s 不得缺帧" % [label, action_name])
		assert(action.get("confidence", "") == "A", "%s/%s 必须来自客户端精确帧" % [label, action_name])


func _run() -> void:
	var manifest := _json(CATALOG_PATH)
	assert(manifest.get("contractId", "") == "equipment.visual_catalog.formal_wearables.v1", "装备视觉目录稳定 ID 错误")
	var coverage: Dictionary = manifest.get("coverage", {})
	assert(int(coverage.get("formalWearables", 0)) == 175, "正式可穿戴目录必须覆盖 175 件")
	assert(int(coverage.get("exactInventoryIcons", 0)) == 175, "每件正式装备必须有精确背包图")
	assert(int(coverage.get("exactEquippedIcons", 0)) == 175, "每件正式装备必须有精确装备槽图")
	assert(int(coverage.get("exactGroundIcons", 0)) == 175, "每件正式装备必须有精确地面图")
	assert(int(coverage.get("visualWearables", 0)) == 73, "武器/衣服/头盔目录数错误")
	assert(int(coverage.get("exactPaperDollOverlays", 0)) == 73, "所有可视穿戴槽必须有精确 StateItem 记录")
	assert(int(coverage.get("exactMaleWorldWear", 0)) == 60, "男性正式世界穿戴覆盖数错误")
	assert(int(coverage.get("exactFemaleWorldWear", 0)) == 12, "武器返修不得生成女性武器资产")
	assert(int(coverage.get("unresolvedWorldShape", 0)) == 1, "缺少 primary 兼容证据的正式武器必须只保留落魄神兵")
	var profession_manifests: Dictionary = manifest.get("professionManifests", {})
	assert(profession_manifests.keys().size() == 3, "必须提供战士/法师/道士三个职业纸娃娃入口")
	for profession_id: String in ["warrior", "wizard", "taoist"]:
		var profession_manifest: Dictionary = profession_manifests.get(profession_id, {})
		assert(profession_manifest.get("professionId", "") == profession_id, "职业纸娃娃稳定 ID 错误")
		_resource_exists(profession_manifest.get("base", {}), "%s/base" % profession_id)
		_resource_exists(profession_manifest.get("hair", {}), "%s/hair" % profession_id)
		var canvas_size: Array = profession_manifest.get("canvasSize", [])
		var paper_anchor: Array = profession_manifest.get("paperDollFootAnchor", [])
		var world_anchor: Array = profession_manifest.get("worldActorSourceFootAnchor", [])
		assert(canvas_size.size() == 2 and int(canvas_size[0]) == 168 and int(canvas_size[1]) == 199, "%s 纸娃娃画布错误" % profession_id)
		assert(paper_anchor.size() == 2 and int(paper_anchor[0]) == 84 and int(paper_anchor[1]) == 186, "%s 纸娃娃脚底锚点错误" % profession_id)
		assert(world_anchor.size() == 2 and int(world_anchor[0]) == 64 and int(world_anchor[1]) == 80, "%s 世界人物脚底锚点错误" % profession_id)
		assert(profession_manifest.get("actionTemplate", "") == "player.visual.classic_eight_direction.v1", "三职业必须复用战士动作模板")
		var world_bases: Dictionary = profession_manifest.get("worldBaseByGender", {})
		for gender: String in ["男", "女"]:
			_validate_actions(world_bases.get(gender, {}), "%s/worldBase/%s" % [profession_id, gender], false)

	var entries: Dictionary = manifest.get("itemsById", {})
	assert(entries.size() == 175, "item_id 视觉目录不完整")
	var unresolved_names: Array[String] = []
	var formal_weapon_count := 0
	for item_id: String in entries:
		var entry: Dictionary = entries[item_id]
		assert(int(entry.get("itemId", -1)) == int(item_id), "item_id 键值不一致：%s" % item_id)
		var icons: Dictionary = entry.get("icons", {})
		_resource_exists(icons.get("inventory", {}), "%s 背包图" % entry.get("itemName", ""))
		_resource_exists(icons.get("equippedSlot", {}), "%s 装备槽图" % entry.get("itemName", ""))
		_resource_exists(icons.get("ground", {}), "%s 地面图" % entry.get("itemName", ""))
		if entry.get("category", "") in VISUAL_CATEGORIES:
			var paper: Dictionary = entry.get("paperDoll", {})
			var expected_paper_status := "user_authorized_redesign" if int(item_id) == 218 else "exact_client_record"
			assert(paper.get("status", "") == expected_paper_status, "%s 纸娃娃不得占位" % entry.get("itemName", ""))
			if int(item_id) == 218:
				assert(paper.get("designIdentity", "") == "mystery_japanese_kabuto_218", "神秘头盔必须使用用户授权的统一重做造型")
			_resource_exists(paper, "%s 纸娃娃" % entry.get("itemName", ""))
		else:
			assert(entry.get("paperDoll", {}).get("status", "") == "slot_icon_only", "附件只能使用经典装备槽图")
		var world: Dictionary = entry.get("worldWear", {})
		if entry.get("category", "") == "武器":
			formal_weapon_count += 1
			assert(entry.has("visualWeaponClass"), "%s 缺少独立 visualWeaponClass" % entry.get("itemName", ""))
			assert(not str(entry.get("profession", "")).is_empty(), "%s 缺少独立 profession" % entry.get("itemName", ""))
			assert(entry.get("weaponCompatibilityRef", "").contains("equipment_primary_weapon_compatibility"), "%s 未引用 primary 武器兼容合同" % entry.get("itemName", ""))
		match str(world.get("status", "")):
			"exact_client_animation":
				if entry.get("category", "") == "武器":
					var weapon_genders: Dictionary = world.get("appearancesByGender", {})
					assert(weapon_genders.size() == 1 and weapon_genders.has("男"), "%s 只能生成男性武器外观" % entry.get("itemName", ""))
					var expected_weapon_confidence := "user_confirmed_semantic_primary_weapon_feature" if int(entry.get("itemId", -1)) in [108, 110] else "primary_pixel_compatibility"
					assert(world.get("shapeEvidence", {}).get("confidence", "") == expected_weapon_confidence, "%s 未使用合规 primary 像素兼容证据" % entry.get("itemName", ""))
					assert(world.get("visualWeaponClass", "") == entry.get("visualWeaponClass", ""), "%s 视觉类别轴不一致" % entry.get("itemName", ""))
				for gender: String in world.get("appearancesByGender", {}):
					_validate_actions(world.get("appearancesByGender", {})[gender], "%s/%s" % [entry.get("itemName", ""), gender], false)
			"unresolved_no_placeholder":
				unresolved_names.append(str(entry.get("itemName", "")))
				assert(world.get("runtimePolicy", "").contains("hide this item layer"), "无 Shape 装备必须保留人物底图并隐藏物品层")
			"classic_client_no_world_layer", "approved_project_extension":
				pass
			_:
				assert(false, "%s 世界穿戴策略未声明" % entry.get("itemName", ""))
	unresolved_names.sort()
	var expected_unresolved: Array[String] = ["落魄神兵"]
	expected_unresolved.sort()
	assert(unresolved_names == expected_unresolved, "世界穿戴缺口必须只保留落魄神兵，不得猜 Shape")
	assert(formal_weapon_count == 37, "profession/visualWeaponClass 双轴必须覆盖 37 把武器")
	for visible_item_id: String in ["80", "82", "86", "88", "99", "105", "107", "108", "109", "110"]:
		assert(entries.get(visible_item_id, {}).get("worldWear", {}).get("status", "") == "exact_client_animation", "%s 必须有 primary 真实世界外观" % visible_item_id)

	var loadouts := _json(LOADOUT_PATH)
	var matrix: Array = loadouts.get("loadouts", [])
	assert(matrix.size() == 9, "验收矩阵必须是 3 职业 × 3 档")
	var expected_profiles := {
		"战士": {"wooma": false, "zuma": false, "chiyue": false},
		"法师": {"wooma": false, "zuma": false, "chiyue": false},
		"道士": {"wooma": false, "zuma": false, "chiyue": false},
	}
	var visual_contracts: Dictionary = manifest.get("loadoutVisualContracts", {})
	assert(visual_contracts.size() == 9, "九人物视觉契约必须全部生成")
	for profile: Dictionary in matrix:
		var profession := str(profile.get("profession", ""))
		var tier := str(profile.get("tierId", ""))
		assert(expected_profiles.has(profession) and expected_profiles[profession].has(tier), "出现非 3×3 职业档位")
		expected_profiles[profession][tier] = true
		var contract: Dictionary = visual_contracts.get(str(profile.get("loadoutId", "")), {})
		assert(contract.get("baseActionTemplate", "") == "player.visual.classic_eight_direction.v1", "三职业必须复用战士动作模板")
		for slot: String in ["武器", "衣服", "头盔"]:
			var item_id := str(int(profile.get("equipment", {}).get(slot, {}).get("itemId", -1)))
			var entry: Dictionary = entries.get(item_id, {})
			assert(not entry.is_empty(), "%s/%s 不在正式目录" % [profile.get("loadoutId", ""), slot])
			if slot in ["武器", "衣服"]:
				var world: Dictionary = entry.get("worldWear", {})
				assert(world.get("status", "") == "exact_client_animation", "%s/%s 必须有精确世界动画" % [profile.get("loadoutId", ""), slot])
				var male: Dictionary = world.get("appearancesByGender", {}).get("男", {})
				_validate_actions(male, "%s/%s" % [profile.get("loadoutId", ""), slot])
	for profession: String in expected_profiles:
		for tier: String in expected_profiles[profession]:
			assert(expected_profiles[profession][tier], "缺少 %s/%s 测试人物" % [profession, tier])

	assert(int(matrix[2].get("equipment", {}).get("衣服", {}).get("itemId", -1)) == 140, "男性战士赤月测试人物必须穿天魔神甲")
	assert(str(matrix[2].get("equipment", {}).get("衣服", {}).get("itemName", "")) == "天魔神甲", "不得把女性圣战宝甲装给男性测试人物")

	var runtime: Dictionary = manifest.get("runtimeMappings", {})
	for item_name: String in ["炼狱", "裁决之杖", "怒斩", "魔杖", "骨玉权杖", "龙牙", "银蛇", "龙纹剑", "逍遥扇"]:
		assert(runtime.has(item_name), "%s 必须有运行时世界外观映射" % item_name)
	var required_features := {
		"木剑": 2,
		"乌木剑": 2,
		"罗刹": 14,
		"炼狱": 22,
		"裁决之杖": 48,
		"龙纹剑": 50,
		"屠龙": 52,
		"命运之刃": 58,
		"嗜魂法杖": 54,
	}
	for item_name: String in required_features:
		assert(int(runtime.get(item_name, {}).get("weaponAppearance", {}).get("feature", -1)) == int(required_features[item_name]), "%s primary 兼容 feature 错误" % item_name)
	var required_classes := {
		"罗刹": "axe",
		"炼狱": "axe",
		"裁决之杖": "staff",
		"龙纹剑": "sword",
		"屠龙": "blade",
		"命运之刃": "sword",
	}
	for item_name: String in required_classes:
		var catalog_item: Dictionary = {}
		for item_id: String in entries:
			if entries[item_id].get("itemName", "") == item_name:
				catalog_item = entries[item_id]
				break
		assert(catalog_item.get("visualWeaponClass", "") == required_classes[item_name], "%s visualWeaponClass 错误" % item_name)
	var confirmed_male_dress_features := {
		116: 2,
		118: 4,
		120: 4,
		122: 6,
		128: 6,
		140: 12,
		124: 8,
		130: 8,
		142: 14,
		126: 10,
		132: 10,
		144: 16,
	}
	for item_id: int in confirmed_male_dress_features:
		var armor_entry: Dictionary = entries.get(str(item_id), {})
		var armor_world: Dictionary = armor_entry.get("worldWear", {})
		assert(armor_world.get("shapeEvidence", {}).get("confidence", "") == "user_confirmed_full_atlas_review")
		var male_armor: Dictionary = armor_world.get("appearancesByGender", {}).get("男", {})
		assert(int(male_armor.get("feature", -1)) == int(confirmed_male_dress_features[item_id]))
	assert(not bool(manifest.get("sourcePolicy", {}).get("crystalShapeDirectMapping", true)), "禁止 Crystal Shape 直接映射 classic Feature")
	assert(manifest.get("sourcePolicy", {}).get("noPlaceholderRule", false), "缺源装备不得制造占位")

	print("EQUIPMENT_VISUAL_CATALOG_TEST_PASS：175 件正式装备全图标、73 件纸娃娃、九人物武器/衣服八方向六动作通过")
	get_tree().quit(0)
