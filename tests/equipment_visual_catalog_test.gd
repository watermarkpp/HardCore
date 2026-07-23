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
	assert(int(coverage.get("exactMaleWorldWear", 0)) == 44, "男性正式世界穿戴覆盖数错误")
	assert(int(coverage.get("exactFemaleWorldWear", 0)) == 43, "女性正式世界穿戴覆盖数错误")
	assert(int(coverage.get("unresolvedWorldShape", 0)) == 4, "缺少可靠 Shape 的正式装备必须稳定为 4 件")
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
		match str(world.get("status", "")):
			"exact_client_animation":
				for gender: String in world.get("appearancesByGender", {}):
					_validate_actions(world.get("appearancesByGender", {})[gender], "%s/%s" % [entry.get("itemName", ""), gender], false)
			"unresolved_no_placeholder":
				unresolved_names.append(str(entry.get("itemName", "")))
				assert(world.get("runtimePolicy", "").contains("hide this item layer"), "无 Shape 装备必须保留人物底图并隐藏物品层")
			"classic_client_hidden_weapon":
				for gender: String in world.get("appearancesByGender", {}):
					var hidden: Dictionary = world.get("appearancesByGender", {})[gender]
					assert(not bool(hidden.get("visible", true)) and hidden.get("actions", {}).is_empty(), "Shape 0 武器必须遵守经典隐藏规则")
			"classic_client_no_world_layer", "approved_project_extension":
				pass
			_:
				assert(false, "%s 世界穿戴策略未声明" % entry.get("itemName", ""))
	unresolved_names.sort()
	var expected_unresolved: Array[String] = ["嗜魂法杖", "罗刹", "落魄神兵", "鹤嘴锄"]
	expected_unresolved.sort()
	assert(unresolved_names == expected_unresolved, "世界穿戴缺口必须只保留有证据的四件，不得猜 Shape")
	for hidden_item_id: String in ["80", "82"]:
		assert(entries.get(hidden_item_id, {}).get("worldWear", {}).get("status", "") == "classic_client_hidden_weapon", "木剑/乌木剑必须保持 m_btWeapon<2 隐藏行为")

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
	assert(manifest.get("sourcePolicy", {}).get("noPlaceholderRule", false), "缺源装备不得制造占位")

	print("EQUIPMENT_VISUAL_CATALOG_TEST_PASS：175 件正式装备全图标、73 件纸娃娃、九人物武器/衣服八方向六动作通过")
	get_tree().quit(0)
