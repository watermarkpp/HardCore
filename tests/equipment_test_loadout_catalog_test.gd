extends Node

const LoadoutCatalog = preload("res://scripts/equipment_test_loadout_catalog.gd")
const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const PAPER_DOLL_PATH := "res://assets/data/warrior_paper_doll_sources.json"
const CATEGORY_BY_SLOT := {
	"武器": "武器",
	"衣服": "盔甲",
	"头盔": "头盔",
	"项链": "项链",
	"左手镯": "手镯",
	"右手镯": "手镯",
	"左戒指": "戒指",
	"右戒指": "戒指",
}
const VISUAL_SLOTS := ["武器", "衣服", "头盔"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := LoadoutCatalog.load_catalog()
	assert(str(catalog.get("contractId", "")) == LoadoutCatalog.CONTRACT_ID, "九测试人物装备契约ID错误")
	assert(catalog.get("supportedSlots", []) == LoadoutCatalog.REQUIRED_SLOTS, "装备测试清单没有覆盖正式八槽")
	var loadouts := LoadoutCatalog.loadouts()
	assert(loadouts.size() == 9, "测试装配必须为3职业×3档共9套")

	var paper_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PAPER_DOLL_PATH))
	assert(paper_parsed is Dictionary, "角色纸娃娃清单不可解析")
	var paper_mappings: Dictionary = paper_parsed.get("runtimeMappings", {})
	var historical_rejections := {}
	for rejected: Variant in paper_parsed.get("rejectedMappings", []):
		if rejected is Dictionary:
			historical_rejections[str(rejected.get("name", ""))] = rejected
	var seen_loadouts := {}
	var seen_profiles := {}
	var seen_pairs := {}
	var checked_items := 0
	for value: Variant in loadouts:
		assert(value is Dictionary, "测试装配记录必须是字典")
		var loadout: Dictionary = value
		var loadout_id := str(loadout.get("loadoutId", ""))
		var profile_id := str(loadout.get("profileId", ""))
		var profession := str(loadout.get("profession", ""))
		var gender := str(loadout.get("gender", ""))
		var tier_id := str(loadout.get("tierId", ""))
		assert(not loadout_id.is_empty() and not seen_loadouts.has(loadout_id), "测试装配ID缺失或重复：%s" % loadout_id)
		assert(not profile_id.is_empty() and not seen_profiles.has(profile_id), "测试人物ID缺失或重复：%s" % profile_id)
		assert(profession in LoadoutCatalog.PROFESSIONS and tier_id in LoadoutCatalog.TIERS, "职业或档位不受支持")
		assert(not seen_pairs.has("%s:%s" % [profession, tier_id]), "职业档位重复")
		seen_loadouts[loadout_id] = true
		seen_profiles[profile_id] = true
		seen_pairs["%s:%s" % [profession, tier_id]] = true

		var equipment: Variant = loadout.get("equipment", {})
		assert(equipment is Dictionary and equipment.keys().size() == LoadoutCatalog.REQUIRED_SLOTS.size(), "%s不是完整八槽装配" % loadout_id)
		for slot: String in LoadoutCatalog.REQUIRED_SLOTS:
			assert(equipment.has(slot), "%s缺少槽位%s" % [loadout_id, slot])
			var entry: Variant = equipment.get(slot, {})
			assert(entry is Dictionary, "%s槽位%s不是装备记录" % [loadout_id, slot])
			var item_name := str(entry.get("itemName", ""))
			var item_id := int(entry.get("itemId", -1))
			assert(not str(entry.get("selectionBasis", "")).is_empty(), "%s槽位%s缺少选装依据" % [loadout_id, slot])
			var item := GameData.get_item_record(item_name)
			assert(not item.is_empty(), "%s使用了不存在的正式物品%s" % [loadout_id, item_name])
			assert(int(item.get("itemId", -2)) == item_id, "%s的itemId与正式目录不一致" % item_name)
			assert(str(item.get("category", "")) == str(CATEGORY_BY_SLOT[slot]), "%s不能装入%s" % [item_name, slot])
			var item_profession := EquipmentRulesScript.effective_profession(item)
			assert(item_profession in ["", "通用", profession], "%s不能由%s穿戴" % [item_name, profession])
			var required_gender := EquipmentRulesScript.required_gender(item)
			assert(required_gender.is_empty() or required_gender == gender, "%s与测试人物性别不符" % item_name)
			assert(EquipmentRulesScript.requirement_error(item, int(loadout.get("level", 50)), {
				"attack_max": 999,
				"magic_max": 999,
				"tao_max": 999,
			}).is_empty(), "%s的正式需求未满足" % item_name)
			var art: Variant = item.get("art", {})
			assert(art is Dictionary, "%s缺少客户端美术映射" % item_name)
			for icon_field: String in ["inventoryIcon", "equippedIcon", "groundIcon"]:
				var icon: Variant = art.get(icon_field, {})
				assert(icon is Dictionary and ResourceLoader.exists(str(icon.get("path", ""))), "%s缺少%s资源" % [item_name, icon_field])
			if slot in VISUAL_SLOTS:
				var paper: Variant = paper_mappings.get(item_name, {})
				assert(paper is Dictionary and ResourceLoader.exists(str(paper.get("path", ""))), "%s缺少角色paper_doll资源" % item_name)
				var historical: Variant = historical_rejections.get(item_name, {})
				if historical is Dictionary and not historical.is_empty():
					assert(str(historical.get("status", "")) == "superseded_by_equipment_client_art_mapping_v1", "%s仍被标记为未解决纸娃娃映射" % item_name)
					assert(str(historical.get("resolvedRuntimePath", "")) == str(paper.get("path", "")), "%s纸娃娃历史拒绝记录没有指向当前资源" % item_name)
			checked_items += 1

	for profession: String in LoadoutCatalog.PROFESSIONS:
		for tier_id: String in LoadoutCatalog.TIERS:
			assert(not LoadoutCatalog.get_loadout(profession, tier_id).is_empty(), "缺少%s/%s测试装配" % [profession, tier_id])
	assert(checked_items == 72, "九套装配应准确覆盖72个槽位")
	print("EQUIPMENT_TEST_LOADOUT_CATALOG_PASS contract=%s loadouts=9 slots=72" % LoadoutCatalog.CONTRACT_ID)
	get_tree().quit(0)
