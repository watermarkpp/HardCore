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
const REQUIRED_WEAPON_IDENTITIES := {
	"80": [1, 2, "sword", "通用"],
	"82": [1, 2, "sword", "通用"],
	"88": [7, 14, "axe", "战士"],
	"99": [11, 22, "axe", "战士"],
	"105": [24, 48, "staff", "战士"],
	"107": [25, 50, "sword", "道士"],
	"108": [26, 52, "blade", "战士"],
	"109": [27, 54, "staff", "法师"],
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
	assert(int(coverage.get("exactFemaleWorldWear", 0)) == 12, "女性武器不得由男性管线生成")
	assert(int(coverage.get("unresolvedWorldShape", 0)) == 1, "世界 Shape 缺口必须只剩落魄神兵")
	assert(int(coverage.get("classicWeaponShapeRows", 0)) == 36, "1.76 StdItems 武器 Shape 覆盖错误")
	assert(int(coverage.get("visualWeaponClassAudited", 0)) == 36, "职业/视觉武器分类审计不完整")
	var source_policy: Dictionary = manifest.get("sourcePolicy", {})
	var shape_source: Dictionary = source_policy.get("classicWeaponShapeSource", {})
	assert(str(shape_source.get("path", "")).contains("mylgd_mir2server_176"), "武器 Shape 未使用 1.76 Paradox 源")
	assert(shape_source.get("sha256", "") == "7978a8164b950a96b47ae15c0414f2925fa2418661dc74a1ac4d0427b1c0372b", "1.76 StdItems.DB 哈希变化")
	assert(str(source_policy.get("classicWeaponShapeScope", "")).contains("Shape/Looks"), "1.76 StdItems 外观身份作用域未声明")
	assert(str(source_policy.get("classicWeaponShapeScope", "")).contains("does not replace profession"), "1.76 StdItems 不得覆盖运行装备规则")
	assert(str(source_policy.get("professionVisualClassSeparation", "")).contains("profession controls equip eligibility"), "profession/visualWeaponClass 未分离")
	var taxonomy: Dictionary = manifest.get("visualWeaponClassTaxonomy", {})
	var classes: Dictionary = taxonomy.get("classes", {})
	assert(classes.size() == 7, "视觉武器分类必须覆盖七类")
	assert(str(taxonomy.get("axis", "")).contains("independent from profession"), "视觉分类不得由职业决定")
	assert(str(classes.get("staff", {}).get("semantic", "")).contains("long-handled"), "staff 必须声明为长柄武器族")
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
	for item_id: String in entries:
		var entry: Dictionary = entries[item_id]
		assert(int(entry.get("itemId", -1)) == int(item_id), "item_id 键值不一致：%s" % item_id)
		var icons: Dictionary = entry.get("icons", {})
		_resource_exists(icons.get("inventory", {}), "%s 背包图" % entry.get("itemName", ""))
		_resource_exists(icons.get("equippedSlot", {}), "%s 装备槽图" % entry.get("itemName", ""))
		_resource_exists(icons.get("ground", {}), "%s 地面图" % entry.get("itemName", ""))
		if entry.get("category", "") in VISUAL_CATEGORIES:
			var paper: Dictionary = entry.get("paperDoll", {})
			assert(paper.get("status", "") == "exact_client_record", "%s 纸娃娃不得占位" % entry.get("itemName", ""))
			_resource_exists(paper, "%s 纸娃娃" % entry.get("itemName", ""))
		else:
			assert(entry.get("paperDoll", {}).get("status", "") == "slot_icon_only", "附件只能使用经典装备槽图")
		var world: Dictionary = entry.get("worldWear", {})
		if entry.get("category", "") == "武器":
			assert(entry.has("visualWeaponClass"), "%s 缺少视觉武器分类" % entry.get("itemName", ""))
			if str(world.get("status", "")) == "exact_client_animation":
				assert(entry.get("visualWeaponClassEvidence", {}).get("confidence", "") == "manually_verified", "%s 视觉武器分类未审计" % entry.get("itemName", ""))
		match str(world.get("status", "")):
			"exact_client_animation":
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
	for item_id: String in REQUIRED_WEAPON_IDENTITIES:
		var entry: Dictionary = entries.get(item_id, {})
		var expected: Array = REQUIRED_WEAPON_IDENTITIES[item_id]
		var world: Dictionary = entry.get("worldWear", {})
		var male: Dictionary = world.get("appearancesByGender", {}).get("男", {})
		assert(world.get("status", "") == "exact_client_animation", "%s 必须绘制世界武器" % entry.get("itemName", ""))
		assert(int(world.get("shape", -1)) == int(expected[0]))
		assert(int(male.get("feature", -1)) == int(expected[1]))
		assert(entry.get("visualWeaponClass", "") == expected[2])
		assert(entry.get("profession", "") == expected[3])
		assert(male.get("visualWeaponClass", "") == expected[2])
		var expected_profile := "weapon.hold.%s.source_hot.v1" % str(expected[2])
		assert(entry.get("weaponHoldAnchorProfile", "") == expected_profile)
		assert(male.get("holdAnchorProfile", "") == expected_profile)
	for user_item_id: String in ["80", "82", "88", "108", "109"]:
		assert(entries.get(user_item_id, {}).get("worldWear", {}).get("shapeEvidence", {}).has("userEvidence"), "%s 缺少用户原版实机证据记录" % user_item_id)

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
	assert(int(runtime.get("裁决之杖", {}).get("weaponAppearance", {}).get("feature", -1)) == 48, "战士已验收裁决 feature 不得回归")
	assert(source_policy.get("noPlaceholderRule", false), "缺源装备不得制造占位")

	print("EQUIPMENT_VISUAL_CATALOG_TEST_PASS：175 件正式装备全图标、73 件纸娃娃、九人物武器/衣服八方向六动作通过")
	get_tree().quit(0)
