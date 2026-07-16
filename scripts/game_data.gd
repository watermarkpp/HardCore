extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")

const DATA_PATH := "res://assets/data/legend176_data.json"
const SERVICE_REFERENCE_PATH := "res://assets/data/service_reference.json"
const EQUIPMENT_CUSTOMIZATION_PATH := "res://assets/data/equipment_customization.json"
const EQUIPMENT_ART_PATH := "res://assets/data/equipment_client_art_sources.json"
const WARRIOR_WEAR_PATH := "res://assets/data/warrior_wear_sources.json"
const WARRIOR_CLIENT_ART_PATH := "res://assets/data/warrior_client_art_sources.json"
const BICH_QUEST_CHAIN_PATH := "res://assets/data/bich_quest_chain.json"
const BICH_UNDEAD_ART_PATH := "res://assets/data/bich_undead_client_art_sources.json"
const BICH_COMMON_ART_PATH := "res://assets/data/bich_common_client_art_sources.json"
const BOSS_SERVICE_RULES_PATH := "res://assets/data/boss_service_rules.json"
const BICH_COMMUNITY_BASELINE_PATH := "res://assets/data/bich_community_baseline.json"
const SERVICE_ITEM_CATALOG_PATH := "res://assets/data/service_item_catalog.json"
const ITEM_ALIASES := {
	"布衣": "布衣(男)",
	"金疮药(小量)": "金创药(小量)",
	"金疮药(中量)": "金创药(中量)",
	"金疮药(大量)": "金创药(大量)",
	"金疮药(特大)": "金创药(特大)",
	"超级金疮药": "超级金创药",
	"强效金创药": "超级金创药",
	"强效魔法药": "超级魔法药",
}
# 服务端使用经典MAP代码，项目地图目录沿用资料站ID。别名必须显式保留，禁止改写原服务端值。
const SERVICE_RUNTIME_MAP_ALIASES := {0: 4}

var database: Dictionary = {}
var service_reference: Dictionary = {}
var equipment_customization: Dictionary = {}
var equipment_client_art: Dictionary = {}
var warrior_wear_art: Dictionary = {}
var warrior_client_art: Dictionary = {}
var bich_quest_chain: Dictionary = {}
var bich_undead_art: Dictionary = {}
var bich_common_art: Dictionary = {}
var boss_service_rules: Dictionary = {}
var bich_community_baseline: Dictionary = {}
var service_item_catalog: Dictionary = {}
var maps: Array = []
var monsters: Array = []
var bosses: Array = []
var items: Array = []
var skills: Array = []
var drops: Array = []
var tasks: Array = []
var item_catalog: Array = []
var load_error := ""

var _monsters_by_name: Dictionary = {}
var _items_by_name: Dictionary = {}
var _drops_by_boss_id: Dictionary = {}
var _maps_by_id: Dictionary = {}
var _maps_by_name: Dictionary = {}
var _catalog_by_name: Dictionary = {}
var _bich_quests_by_id: Dictionary = {}


func _ready() -> void:
	load_database()


func load_database() -> bool:
	var parsed: Variant = ContentLayers.build_merged_database()
	if not parsed is Dictionary or parsed.get("maps", []).is_empty():
		load_error = "五层内容注册表未能生成Merged Game Database"
		push_error(load_error)
		return false

	database = parsed
	maps = database.get("maps", [])
	_normalize_map_ids()
	monsters = database.get("monsters", [])
	bosses = database.get("bosses", [])
	_load_bich_community_baseline()
	monsters = apply_bich_community_overrides(monsters, bich_community_baseline)
	bosses = apply_bich_community_overrides(bosses, bich_community_baseline)
	items = database.get("items", [])
	_load_equipment_client_art()
	items = apply_equipment_art_mappings(items, equipment_client_art)
	_load_warrior_wear_art()
	_load_warrior_client_art()
	items = apply_equipment_wear_mappings(items, warrior_wear_art)
	_load_equipment_customization()
	items = apply_equipment_customization(items, equipment_customization)
	skills = database.get("skills", [])
	drops = database.get("drops", [])
	tasks = database.get("tasks", [])
	_load_bich_quest_chain()
	_load_bich_undead_art()
	_load_bich_common_art()
	_load_boss_service_rules()
	_load_service_reference()
	_load_service_item_catalog()
	_build_indexes()
	print("数据库载入完成：地图%d 怪物%d Boss%d 装备%d 技能等级%d 掉落槽%d 任务%d" % [
		maps.size(), monsters.size(), bosses.size(), items.size(), skills.size(), drops.size(), tasks.size()
	])
	return true


func _load_service_reference() -> void:
	service_reference.clear()
	if not FileAccess.file_exists(SERVICE_REFERENCE_PATH):
		push_warning("服务端参考文件不存在：%s" % SERVICE_REFERENCE_PATH)
		return
	var file := FileAccess.open(SERVICE_REFERENCE_PATH, FileAccess.READ)
	if file == null:
		push_warning("无法打开服务端参考文件：%s" % SERVICE_REFERENCE_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		service_reference = parsed
	else:
		push_warning("服务端参考文件不是有效JSON：%s" % SERVICE_REFERENCE_PATH)


func _load_service_item_catalog() -> void:
	service_item_catalog = {}
	if not FileAccess.file_exists(SERVICE_ITEM_CATALOG_PATH):
		push_error("完整物品目录不存在：%s" % SERVICE_ITEM_CATALOG_PATH)
		return
	var file := FileAccess.open(SERVICE_ITEM_CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		service_item_catalog = parsed
	else:
		push_error("完整物品目录不是有效JSON：%s" % SERVICE_ITEM_CATALOG_PATH)


func _load_bich_quest_chain() -> void:
	bich_quest_chain = {}
	_bich_quests_by_id.clear()
	if not FileAccess.file_exists(BICH_QUEST_CHAIN_PATH):
		push_warning("比奇任务链不存在：%s" % BICH_QUEST_CHAIN_PATH)
		return
	var file := FileAccess.open(BICH_QUEST_CHAIN_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		push_warning("比奇任务链不是有效JSON：%s" % BICH_QUEST_CHAIN_PATH)
		return
	bich_quest_chain = parsed
	for value: Variant in bich_quest_chain.get("quests", []):
		if value is Dictionary and not str(value.get("id", "")).is_empty():
			_bich_quests_by_id[str(value.get("id"))] = value


func _load_bich_undead_art() -> void:
	bich_undead_art = {}
	if not FileAccess.file_exists(BICH_UNDEAD_ART_PATH):
		return
	var file := FileAccess.open(BICH_UNDEAD_ART_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		bich_undead_art = parsed
	else:
		push_warning("比奇亡灵客户端美术映射不是有效JSON：%s" % BICH_UNDEAD_ART_PATH)


func _load_bich_common_art() -> void:
	bich_common_art = {}
	if not FileAccess.file_exists(BICH_COMMON_ART_PATH):
		return
	var file := FileAccess.open(BICH_COMMON_ART_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		bich_common_art = parsed
	else:
		push_warning("比奇常见怪物客户端美术映射不是有效JSON：%s" % BICH_COMMON_ART_PATH)


func _load_boss_service_rules() -> void:
	boss_service_rules = {}
	if not FileAccess.file_exists(BOSS_SERVICE_RULES_PATH):
		return
	var file := FileAccess.open(BOSS_SERVICE_RULES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		boss_service_rules = parsed
	else:
		push_warning("Boss服务端规则不是有效JSON：%s" % BOSS_SERVICE_RULES_PATH)


func _load_bich_community_baseline() -> void:
	bich_community_baseline = {}
	if not FileAccess.file_exists(BICH_COMMUNITY_BASELINE_PATH):
		return
	var file := FileAccess.open(BICH_COMMUNITY_BASELINE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		bich_community_baseline = parsed
	else:
		push_warning("比奇社区基准不是有效JSON：%s" % BICH_COMMUNITY_BASELINE_PATH)


func apply_bich_community_overrides(base_records: Array, baseline: Dictionary) -> Array:
	var result: Array = []
	var overrides: Dictionary = baseline.get("runtimeMonsterOverrides", {})
	for value: Variant in base_records:
		if not value is Dictionary:
			continue
		var record: Dictionary = value.duplicate(true)
		var entry: Variant = overrides.get(str(record.get("name", "")), {})
		if entry is Dictionary and not entry.is_empty():
			var fields: Variant = entry.get("fields", {})
			if fields is Dictionary:
				record.merge(fields, true)
			record["communitySource"] = str(entry.get("source", ""))
			record["communityAgreements"] = entry.get("agreements", {}).duplicate(true)
			record["communityConflicts"] = entry.get("conflicts", {}).duplicate(true)
		result.append(record)
	return result


func _load_equipment_customization() -> void:
	equipment_customization = {}
	if not FileAccess.file_exists(EQUIPMENT_CUSTOMIZATION_PATH):
		return
	var file := FileAccess.open(EQUIPMENT_CUSTOMIZATION_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		equipment_customization = parsed
	else:
		push_warning("装备自定义文件不是有效JSON：%s" % EQUIPMENT_CUSTOMIZATION_PATH)


func _load_equipment_client_art() -> void:
	equipment_client_art = {}
	if not FileAccess.file_exists(EQUIPMENT_ART_PATH):
		push_warning("装备客户端美术映射不存在：%s" % EQUIPMENT_ART_PATH)
		return
	var file := FileAccess.open(EQUIPMENT_ART_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		equipment_client_art = parsed
	else:
		push_warning("装备客户端美术映射不是有效JSON：%s" % EQUIPMENT_ART_PATH)


func apply_equipment_art_mappings(base_items: Array, art_manifest: Dictionary) -> Array:
	var result: Array = []
	var mappings: Dictionary = art_manifest.get("runtimeMappings", {})
	for value: Variant in base_items:
		if not value is Dictionary:
			continue
		var record: Dictionary = value.duplicate(true)
		var art: Variant = mappings.get(str(record.get("name", "")), {})
		if art is Dictionary and not art.is_empty():
			record["art"] = art.duplicate(true)
		result.append(record)
	return result


func _load_warrior_wear_art() -> void:
	warrior_wear_art = {}
	if not FileAccess.file_exists(WARRIOR_WEAR_PATH):
		return
	var file := FileAccess.open(WARRIOR_WEAR_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		warrior_wear_art = parsed
	else:
		push_warning("战士穿戴美术映射不是有效JSON：%s" % WARRIOR_WEAR_PATH)


func _load_warrior_client_art() -> void:
	warrior_client_art = {}
	if not FileAccess.file_exists(WARRIOR_CLIENT_ART_PATH):
		return
	var file := FileAccess.open(WARRIOR_CLIENT_ART_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		warrior_client_art = parsed
	else:
		push_warning("战士技能客户端美术映射不是有效JSON：%s" % WARRIOR_CLIENT_ART_PATH)


func apply_equipment_wear_mappings(base_items: Array, wear_manifest: Dictionary) -> Array:
	var result: Array = []
	var mappings: Dictionary = wear_manifest.get("runtimeMappings", {})
	for value: Variant in base_items:
		if not value is Dictionary:
			continue
		var record: Dictionary = value.duplicate(true)
		var wear: Variant = mappings.get(str(record.get("name", "")), {})
		if wear is Dictionary and not wear.is_empty():
			var art: Dictionary = record.get("art", {}).duplicate(true)
			art.merge(wear, true)
			record["art"] = art
		result.append(record)
	return result


func apply_equipment_customization(base_items: Array, customization: Dictionary) -> Array:
	var result: Array = []
	var overrides: Dictionary = customization.get("overrides", {})
	var known_names := {}
	for value: Variant in base_items:
		if not value is Dictionary:
			continue
		var record: Dictionary = value.duplicate(true)
		var item_name := str(record.get("name", ""))
		var override: Dictionary = overrides.get(item_name, {})
		if override.get("enabled", true) == false:
			continue
		var fields: Variant = override.get("fields", {})
		if fields is Dictionary:
			var merged_fields: Dictionary = fields.duplicate(true)
			if fields.get("art", null) is Dictionary and record.get("art", null) is Dictionary:
				var merged_art: Dictionary = record.get("art", {}).duplicate(true)
				merged_art.merge(fields.get("art", {}), true)
				merged_fields["art"] = merged_art
			record.merge(merged_fields, true)
			if not fields.is_empty():
				record["customized"] = true
				record["customizationSource"] = EQUIPMENT_CUSTOMIZATION_PATH
		result.append(record)
		known_names[item_name] = true
	for value: Variant in customization.get("newEquipment", []):
		if not value is Dictionary or value.get("enabled", true) == false:
			continue
		var record: Dictionary = value.duplicate(true)
		record.erase("enabled")
		var item_name := str(record.get("name", ""))
		if item_name.is_empty() or known_names.has(item_name):
			continue
		if str(record.get("category", "")) not in ["武器", "盔甲", "头盔", "项链", "手镯", "戒指"]:
			continue
		record["customized"] = true
		record["customizationSource"] = EQUIPMENT_CUSTOMIZATION_PATH
		result.append(record)
		known_names[item_name] = true
	return result


func _normalize_map_ids() -> void:
	for entry: Variant in maps:
		if not entry is Dictionary:
			continue
		var raw_id: Variant = entry.get("mapId", -1)
		if raw_id is String and str(raw_id).begins_with("LATE-"):
			entry["sourceMapId"] = raw_id
			entry["mapId"] = 900000 + int(str(raw_id).trim_prefix("LATE-"))


func _build_indexes() -> void:
	_monsters_by_name.clear()
	_items_by_name.clear()
	_drops_by_boss_id.clear()
	_maps_by_id.clear()
	_maps_by_name.clear()
	for entry: Variant in maps:
		if not entry is Dictionary:
			continue
		_maps_by_id[int(entry.get("mapId", -1))] = entry
		var map_name := str(entry.get("name", ""))
		if not _maps_by_name.has(map_name):
			_maps_by_name[map_name] = entry
	for entry: Variant in monsters:
		if entry is Dictionary and not _monsters_by_name.has(entry.get("name", "")):
			_monsters_by_name[entry.get("name", "")] = entry
	for entry: Variant in items:
		if entry is Dictionary:
			_items_by_name[entry.get("name", "")] = entry
	for entry: Variant in drops:
		if not entry is Dictionary:
			continue
		var boss_id := int(entry.get("bossId", 0))
		if not _drops_by_boss_id.has(boss_id):
			_drops_by_boss_id[boss_id] = []
		_drops_by_boss_id[boss_id].append(entry)
	_build_item_catalog()


func _build_item_catalog() -> void:
	item_catalog.clear()
	_catalog_by_name.clear()
	var skill_names := {}
	for skill: Variant in skills:
		if skill is Dictionary:
			skill_names[str(skill.get("skillName", ""))] = true
	for equipment: Variant in items:
		if not equipment is Dictionary:
			continue
		var record: Dictionary = EquipmentRulesScript.enrich_catalog_record(equipment)
		record["kind"] = "equipment"
		record["stackable"] = false
		if record.has("maxDurability"):
			record["maxDurability"] = maxi(1, int(record.get("maxDurability", 1)))
		elif record.has("serviceDuraMax"):
			record["maxDurability"] = maxi(1, int(record.get("serviceDuraMax", 1000)) / 1000)
		else:
			record["maxDurability"] = maxi(1, int(record.get("durability", 1) if record.get("durability", null) != null else 1))
		_register_catalog_item(record)
	for service_item: Variant in service_item_catalog.get("runtimeItems", []):
		if not service_item is Dictionary:
			continue
		var service_record: Dictionary = service_item.duplicate(true)
		if str(service_record.get("name", "")) in ["沃玛号角", "祖玛头像"]:
			service_record["kind"] = "quest_item"
			service_record["category"] = "任务物品"
		if str(service_record.get("kind", "")) == "skill_book" and not skill_names.has(str(service_record.get("name", ""))):
			service_record["usable"] = false
			service_record["useEffect"] = "skill_not_in_current_class_catalog"
		_register_catalog_item(service_record)
	for special_item: Variant in service_item_catalog.get("runtimeSpecials", {}).values():
		if special_item is Dictionary:
			_register_catalog_item(special_item.duplicate(true))
	var extra_names := {}
	for drop: Variant in drops:
		if drop is Dictionary:
			extra_names[str(drop.get("itemName", ""))] = true
	for drop_list: Variant in bich_community_baseline.get("runtimeDrops", {}).values():
		if not drop_list is Array:
			continue
		for drop: Variant in drop_list:
			if drop is Dictionary:
				extra_names[str(drop.get("name", ""))] = true
	for skill_name: String in skill_names.keys():
		extra_names[skill_name] = true
	for runtime_name: String in ["金币", "金创药(小量)", "魔法药(小量)"]:
		extra_names[runtime_name] = true
	for item_name: String in extra_names.keys():
		var canonical_name := str(ITEM_ALIASES.get(item_name, item_name))
		if item_name.is_empty() or _catalog_by_name.has(canonical_name):
			continue
		_register_catalog_item(_make_runtime_item(item_name, skill_names))


func _register_catalog_item(record: Dictionary) -> void:
	var item_name := str(record.get("name", ""))
	if item_name.is_empty() or _catalog_by_name.has(item_name):
		return
	_catalog_by_name[item_name] = record
	item_catalog.append(record)


func _make_runtime_item(item_name: String, skill_names: Dictionary) -> Dictionary:
	var record := {"name": item_name, "stackable": true, "maxStack": 999}
	if skill_names.has(item_name):
		record.merge({"kind": "skill_book", "category": "技能书", "maxStack": 20, "useEffect": "learn_skill"})
	elif item_name.begins_with("金币"):
		var parts := item_name.split(" ", false)
		var amount := int(parts[1]) if parts.size() > 1 else 10
		record.merge({"kind": "currency", "category": "货币", "currencyAmount": maxi(1, amount), "useEffect": "add_gold"})
	elif "金创药" in item_name or item_name in ["疗伤药", "万年雪霜"]:
		record.merge({"kind": "consumable", "category": "生命药品", "useEffect": "restore_health"})
	elif "魔法药" in item_name:
		record.merge({"kind": "consumable", "category": "魔法药品", "useEffect": "restore_mana"})
	elif "太阳水" in item_name:
		record.merge({"kind": "consumable", "category": "混合药品", "useEffect": "restore_both"})
	elif "神水" in item_name or item_name == "祝福油":
		record.merge({"kind": "consumable", "category": "增益药品", "useEffect": "temporary_buff"})
	elif "卷" in item_name:
		record.merge({"kind": "scroll", "category": "卷轴", "useEffect": "teleport"})
	elif item_name in ["沃玛号角", "祖玛头像"]:
		record.merge({"kind": "quest_item", "category": "任务物品", "maxStack": 20})
	else:
		record.merge({"kind": "material", "category": "材料"})
	var fallback_key: String = str({
		"currency": "material", "skill_book": "book", "consumable": "potion",
		"scroll": "scroll", "quest_item": "quest", "material": "material",
	}.get(str(record.get("kind", "material")), "material"))
	var fallback: Variant = service_item_catalog.get("runtimeFallbackArt", {}).get(fallback_key, {})
	if fallback is Dictionary and not fallback.is_empty():
		record["art"] = {
			"inventoryIcon": {"path": str(fallback.get("inventory", "")), "exact": false, "distribution": "project.category_fallback"},
			"stateIcon": {"path": str(fallback.get("inventory", "")), "exact": false, "distribution": "project.category_fallback"},
			"groundIcon": {"path": str(fallback.get("ground", "")), "exact": false, "distribution": "project.category_fallback"},
		}
	return record


func get_monster(monster_name: String) -> Dictionary:
	return _monsters_by_name.get(monster_name, {})


func get_monster_by_id(monster_id:int)->Dictionary:
	for monster:Variant in monsters:
		if monster is Dictionary and int(monster.get("monsterId",-1))==monster_id:return monster
	return {}


func get_map_by_id(map_id: int) -> Dictionary:
	return _maps_by_id.get(map_id, {})


func service_runtime_map_id(service_map_id: int) -> int:
	return int(SERVICE_RUNTIME_MAP_ALIASES.get(service_map_id, service_map_id))


func get_service_map_by_id(service_map_id: int) -> Dictionary:
	return get_map_by_id(service_runtime_map_id(service_map_id))


func get_map(map_name: String) -> Dictionary:
	return _maps_by_name.get(map_name, {})


func get_available_maps(include_later_content: bool) -> Array:
	var result: Array = []
	for entry: Variant in maps:
		if not entry is Dictionary:
			continue
		if bool(entry.get("availabilityDefault", true)) or include_later_content:
			result.append(entry)
	return result


func get_bosses_for_map(map_data: Dictionary) -> Array:
	var result: Array = []
	var map_name := str(map_data.get("name", ""))
	var map_group := str(map_data.get("mapGroup", ""))
	for boss: Variant in bosses:
		if not boss is Dictionary:
			continue
		var location := str(boss.get("location", ""))
		if location.is_empty() or location == "待核验":
			continue
		var matched := map_name in location or location in map_name
		if not matched and not map_group.is_empty():
			for segment: String in location.split("/", false):
				if segment in map_name or map_name in segment or segment in map_group or map_group in segment:
					matched = true
					break
		if matched:
			result.append(boss)
	return result


func get_item(item_name: String) -> Dictionary:
	return _items_by_name.get(str(ITEM_ALIASES.get(item_name, item_name)), {})


func get_item_record(item_name: String) -> Dictionary:
	return _catalog_by_name.get(str(ITEM_ALIASES.get(item_name, item_name)), {})


func get_item_kind(item_name: String) -> String:
	return str(get_item_record(item_name).get("kind", "unknown"))


func item_catalog_counts() -> Dictionary:
	var counts := {}
	for record: Variant in item_catalog:
		if not record is Dictionary:
			continue
		var kind := str(record.get("kind", "unknown"))
		counts[kind] = int(counts.get(kind, 0)) + 1
	return counts


func unresolved_drop_item_names() -> PackedStringArray:
	var missing := PackedStringArray()
	for drop: Variant in drops:
		if not drop is Dictionary:
			continue
		var item_name := str(drop.get("itemName", ""))
		var canonical_name := str(ITEM_ALIASES.get(item_name, item_name))
		if not item_name.is_empty() and not _catalog_by_name.has(canonical_name) and not missing.has(item_name):
			missing.append(item_name)
	return missing


func get_drops_for_boss(boss_id: int) -> Array:
	return _drops_by_boss_id.get(boss_id, [])


func get_calibrated_drops(monster_id: int, monster_name: String) -> Array:
	var community: Variant = bich_community_baseline.get("runtimeDrops", {}).get(monster_name, [])
	if community is Array and not community.is_empty():
		return community.duplicate(true)
	return get_drops_for_boss(monster_id)


func get_skill(skill_name: String, skill_level := 0) -> Dictionary:
	for entry: Variant in skills:
		if entry is Dictionary and entry.get("skillName", "") == skill_name and int(entry.get("skillLevel", -1)) == skill_level:
			return entry
	return {}


func get_bich_quest(quest_id: String) -> Dictionary:
	return _bich_quests_by_id.get(quest_id, {})


func get_bich_quests() -> Array:
	return bich_quest_chain.get("quests", [])


func bich_quest_count() -> int:
	return _bich_quests_by_id.size()


func service_setup_value(key: String, fallback: Variant = null) -> Variant:
	return service_reference.get("serviceSetup", {}).get(key, fallback)


func service_exp_to_next_level(level_value: int) -> int:
	var table: Dictionary = service_reference.get("serviceRuntimeExpTableLevel1To60", {})
	var key := str(maxi(1, level_value))
	if table.has(key):
		return int(table[key])
	return 300000 + maxi(0, level_value - 22) * 100000


func service_home_map_id(red_name := false) -> int:
	return int(service_setup_value("RedHomeMap" if red_name else "HomeMap", 0))


func service_home_runtime_map_id(red_name := false) -> int:
	return service_runtime_map_id(service_home_map_id(red_name))


func service_home_point(red_name := false) -> Vector2i:
	var prefix := "RedHome" if red_name else "Home"
	return Vector2i(
		int(service_setup_value("%sX" % prefix, 0)),
		int(service_setup_value("%sY" % prefix, 0))
	)


func service_profession_stats(profession_name: String, level_value: int) -> Dictionary:
	var n := maxi(1, level_value)
	if profession_name == ProfessionRules.PROFESSIONS[1]:
		var wizard_hp_divisor := float(service_setup_value("LevelValueOfWizardHP", 15))
		var wizard_hp_rate := float(service_setup_value("LevelValueOfWizardHPRate", 1.8))
		return {
			"max_hp": 14 + int(round(((float(n) / wizard_hp_divisor + wizard_hp_rate) * float(n)))),
			"max_mp": 13 + int(round((float(n) / 5.0 + 2.0) * 2.2 * float(n))),
			"attack_min": 1,
			"attack_max": 3,
		}
	if profession_name == ProfessionRules.PROFESSIONS[2]:
		var tao_hp_divisor := float(service_setup_value("LevelValueOfTaosHP", 6))
		var tao_hp_rate := float(service_setup_value("LevelValueOfTaosHPRate", 2.5))
		var tao_mp_divisor := float(service_setup_value("LevelValueOfTaosMP", 8))
		return {
			"max_hp": 14 + int(round(((float(n) / tao_hp_divisor + tao_hp_rate) * float(n)))),
			"max_mp": 13 + int(round(((float(n) / tao_mp_divisor) * 2.2 * float(n)))),
			"attack_min": 1,
			"attack_max": 4,
		}
	var warrior_hp_divisor := float(service_setup_value("LevelValueOfWarrHP", 4))
	var warrior_hp_rate := float(service_setup_value("LevelValueOfWarrHPRate", 4.5))
	return {
		"max_hp": 14 + int(round(((float(n) / warrior_hp_divisor + warrior_hp_rate + float(n) / 20.0) * float(n)))),
		"max_mp": 11 + int(round(float(n) * 3.5)),
		"attack_min": 2,
		"attack_max": 5,
	}


func get_profession_skills(profession: String) -> Array:
	var result: Array = []
	for entry: Variant in skills:
		if entry is Dictionary and entry.get("profession", "") == profession and int(entry.get("skillLevel", -1)) == 0:
			result.append(entry)
	return result


func summary_text() -> String:
	if not load_error.is_empty():
		return load_error
	return "地图 %d｜怪物 %d｜Boss %d｜物品 %d｜技能 %d｜掉落槽 %d" % [
		maps.size(), monsters.size(), bosses.size(), item_catalog.size(), skills.size(), drops.size()
	]
