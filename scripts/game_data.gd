extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const PricingServiceScript = preload("res://scripts/pricing_service.gd")

signal database_reloaded
signal initial_load_finished(success: bool)

const DATA_PATH := "res://assets/data/legend176_data.json"
const SERVICE_REFERENCE_PATH := "res://assets/data/service_reference.json"
const EQUIPMENT_CUSTOMIZATION_PATH := "res://assets/data/equipment_customization.json"
const EQUIPMENT_ART_PATH := "res://assets/data/equipment_client_art_sources.json"
const EQUIPMENT_VISUAL_CATALOG_PATH := "res://assets/data/equipment_visual_catalog.json"
const WARRIOR_WEAR_PATH := "res://assets/data/warrior_wear_sources.json"
const WARRIOR_CLIENT_ART_PATH := "res://assets/data/warrior_client_art_sources.json"
const BICH_QUEST_CHAIN_PATH := "res://assets/data/bich_quest_chain.json"
const BICH_UNDEAD_ART_PATH := "res://assets/data/bich_undead_client_art_sources.json"
const BICH_COMMON_ART_PATH := "res://assets/data/bich_common_client_art_sources.json"
const BOSS_SERVICE_RULES_PATH := "res://assets/data/boss_service_rules.json"
const BICH_COMMUNITY_BASELINE_PATH := "res://assets/data/bich_community_baseline.json"
const SERVICE_ITEM_CATALOG_PATH := "res://assets/data/service_item_catalog.json"
const EQUIPMENT_PRICE_CANDIDATES_PATH := "res://assets/data/equipment_price_candidates_v1.json"
const MERCHANT_CATALOG_PATH := "res://assets/data/merchant_catalog_v1.json"
const CANONICAL_MONSTER_CATALOG_PATH := (
	"res://assets/data/runtime/canonical_monster_catalog.json"
)
const ITEM_RUNTIME_AUTHORITY_PATH := (
	"res://assets/data/item_runtime_authority_v1.json"
)
const DPV2_ITEM_TIER_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_item_tier_authority_v1.json"
)
const DPV2_MONSTER_ROLE_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_monster_role_authority_v1.json"
)
const DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_global_drop_rate_authority_v1.json"
)
const DPV2_DROP_RUNTIME_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_drop_runtime_authority_v1.json"
)

const ITEM_ALIASES := {
	"布衣": "布衣(男)",
	"金疮药(小量)": "金创药(小量)",
	"金疮药(中量)": "金创药(中量)",
	"金疮药(大量)": "金创药(大量)",
	"金疮药(特大)": "金创药(特大)",
	"超级金疮药": "超级金创药",
	"强效金创药": "超级金创药",
	"强效魔法药": "超级魔法药",
	# legacy monster drop exact aliases (audited; frozen canonical drop tokens
	# must resolve to the canonical item identity without fuzzy matching)
	"毒蜘蛛牙齿": "蜘蛛牙",
	"食人树叶": "食人花叶",
	"食人树的果实": "食人花果",
	"蝎子的尾巴": "蝎尾",

}
# 服务端使用经典MAP代码，项目地图目录沿用资料站ID。别名必须显式保留，禁止改写原服务端值。
const SERVICE_RUNTIME_MAP_ALIASES := {0: 4}
const PROFESSION_VISUAL_IDS := {
	"战士": "warrior",
	"法师": "wizard",
	"道士": "taoist",
}

var database: Dictionary = {}
var service_reference: Dictionary = {}
var equipment_customization: Dictionary = {}
var equipment_client_art: Dictionary = {}
var equipment_visual_catalog: Dictionary = {}
var warrior_wear_art: Dictionary = {}
var warrior_client_art: Dictionary = {}
var bich_quest_chain: Dictionary = {}
var bich_undead_art: Dictionary = {}
var bich_common_art: Dictionary = {}
var boss_service_rules: Dictionary = {}
var bich_community_baseline: Dictionary = {}
var service_item_catalog: Dictionary = {}
var equipment_price_candidates: Dictionary = {}
var merchant_catalog: Dictionary = {}
var canonical_monster_catalog: Dictionary = {}
var item_runtime_authority: Dictionary = {}
var dpv2_item_tier_authority: Dictionary = {}
var dpv2_monster_role_authority: Dictionary = {}
var dpv2_global_drop_rate_authority: Dictionary = {}
var dpv2_drop_runtime_authority: Dictionary = {}
var maps: Array = []
var monsters: Array = []
var bosses: Array = []
var items: Array = []
var skills: Array = []
var drops: Array = []
var tasks: Array = []
var item_catalog: Array = []
var load_error := ""
var initial_load_deferred := OS.get_name() == "Android"
var _initial_load_started := false
var _initial_load_complete := false

var _monsters_by_id: Dictionary = {}
var _monster_runtime_drop_closure: Dictionary = {}
var _items_by_name: Dictionary = {}
var _items_by_id: Dictionary = {}
var _maps_by_id: Dictionary = {}
var _maps_by_name: Dictionary = {}
var _catalog_by_name: Dictionary = {}
var _catalog_by_item_id: Dictionary = {}
var _catalog_by_service_index: Dictionary = {}
var _price_by_name: Dictionary = {}
var _price_by_item_id: Dictionary = {}
var _price_by_service_index: Dictionary = {}
var _bich_quests_by_id: Dictionary = {}
var _dpv2_item_tier_by_id: Dictionary = {}
var _dpv2_item_tier_by_name: Dictionary = {}
var _dpv2_monster_role_by_id: Dictionary = {}
var _dpv2_global_scale_by_preset: Dictionary = {}
var _dpv2_item_overflow_by_id: Dictionary = {}
var _dpv2_item_overflow_by_name: Dictionary = {}

const CANONICAL_MONSTER_COUNTS_CONTRACT_ID := (
	"monster.catalog.runtime_counts.v1"
)


func _ready() -> void:
	if not initial_load_deferred:
		ensure_loaded()


func is_loaded() -> bool:
	return _initial_load_complete


func ensure_loaded() -> bool:
	if _initial_load_complete:
		return true
	if _initial_load_started:
		return false
	if not ContentLayers.is_loaded():
		load_error = "content_layers_not_ready"
		return false
	_initial_load_started = true
	var success := load_database()
	_initial_load_complete = success
	_initial_load_started = false
	initial_load_finished.emit(success)
	return success


func load_database() -> bool:
	# Consumers that run during Android autoload construction must fail closed.
	# StartupLoading explicitly opens this gate only after the intro has drawn.
	if not ContentLayers.is_loaded():
		load_error = "content_layers_not_ready"
		return false
	# ContentLayers has already parsed and merged the authoritative tables at
	# this boundary. Keep GameData's private mutable copy without parsing every
	# base JSON table a second time during the same startup.
	var parsed: Variant = ContentLayers.merged_database.duplicate(true)
	if not parsed is Dictionary or parsed.get("maps", []).is_empty():
		load_error = "五层内容注册表未能生成Merged Game Database"
		push_error(load_error)
		return false

	database = parsed
	maps = database.get("maps", [])
	_normalize_map_ids()
	# The merged legacy database remains available for maps/items/tasks, but it
	# is no longer a monster authority.  Runtime monster identity, combat,
	# appearance and drops all come from the canonical ID-keyed catalog.
	monsters = []
	bosses = []
	if not _load_canonical_monster_catalog():
		return false
	_load_bich_community_baseline()
	items = database.get("items", [])
	_load_equipment_client_art()
	items = apply_equipment_art_mappings(items, equipment_client_art)
	_load_warrior_wear_art()
	_load_warrior_client_art()
	items = apply_equipment_wear_mappings(items, warrior_wear_art)
	_load_equipment_visual_catalog()
	items = apply_equipment_visual_mappings(items, equipment_visual_catalog)
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
	if not _load_item_runtime_authority():
		return false
	if not _load_dpv2_drop_authorities():
		return false
	_load_equipment_price_candidates()
	_load_merchant_catalog()
	_build_indexes()
	load_error = ""
	_initial_load_complete = true
	database_reloaded.emit()
	print("数据库载入完成：地图%d 怪物%d Boss%d 装备%d 技能等级%d 掉落槽%d 任务%d" % [
		maps.size(), monsters.size(), bosses.size(), items.size(), skills.size(), drops.size(), tasks.size()
	])
	return true


func _load_canonical_monster_catalog() -> bool:
	canonical_monster_catalog.clear()
	_monsters_by_id.clear()
	_monster_runtime_drop_closure.clear()
	monsters.clear()
	bosses.clear()
	if not FileAccess.file_exists(CANONICAL_MONSTER_CATALOG_PATH):
		load_error = "canonical_monster_catalog_missing"
		return false
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CANONICAL_MONSTER_CATALOG_PATH)
	)
	if not parsed is Dictionary:
		load_error = "canonical_monster_catalog_invalid"
		return false
	var entries_value: Variant = parsed.get("entries_by_id", {})
	if not entries_value is Dictionary or entries_value.is_empty():
		load_error = "canonical_monster_entries_missing"
		return false
	canonical_monster_catalog = parsed
	var entries_by_id: Dictionary = entries_value
	for raw_key: Variant in entries_by_id.keys():
		var key := str(raw_key)
		if not key.is_valid_int():
			load_error = "canonical_monster_id_key_invalid"
			return false
		var monster_id := int(key) if key.is_valid_int() else -1
		var raw_entry: Variant = entries_by_id.get(raw_key, {})
		if (
			monster_id <= 0
			or not raw_entry is Dictionary
			or int(raw_entry.get("monster_id", -1)) != monster_id
		):
			load_error = "canonical_monster_entry_identity_invalid"
			return false
		var entry: Dictionary = raw_entry.duplicate(true)
		# JSON numeric values arrive as floats in Godot.  Normalize the validated
		# identity once at the authority boundary; downstream runtime accepts only
		# the resulting integer monster_id.
		entry["monster_id"] = monster_id
		_monsters_by_id[monster_id] = entry
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


func _load_item_runtime_authority() -> bool:
	item_runtime_authority = {}
	if not FileAccess.file_exists(ITEM_RUNTIME_AUTHORITY_PATH):
		load_error = "item_runtime_authority_missing"
		return false

	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ITEM_RUNTIME_AUTHORITY_PATH)
	)

	if not parsed is Dictionary:
		load_error = "item_runtime_authority_invalid"
		return false

	if str(parsed.get("contractId", "")) != "item.runtime.authority.v1":
		load_error = "item_runtime_authority_contract_invalid"
		return false

	var aliases: Variant = parsed.get("aliases", {})
	if not aliases is Dictionary or aliases.size() != 5:
		load_error = "item_runtime_authority_aliases_invalid"
		return false

	var new_items: Variant = parsed.get("newItems", [])
	if not new_items is Array or new_items.size() != 13:
		load_error = "item_runtime_authority_new_items_count_invalid"
		return false

	var seen_ids := {}
	var seen_names := {}

	for raw_record: Variant in new_items:
		if not raw_record is Dictionary:
			load_error = "item_runtime_authority_new_item_record_invalid"
			return false

		var record: Dictionary = raw_record
		var item_id := _stable_item_id(record)
		var item_name := str(record.get("name", ""))

		if item_id <= 0 or item_name.is_empty() or seen_ids.has(item_id) or seen_names.has(item_name):
			load_error = "item_runtime_authority_identity_invalid"
			return false

		seen_ids[item_id] = true
		seen_names[item_name] = true

		# Collision check against service runtime items
		var service_runtime: Variant = service_item_catalog.get("runtimeItems", {})
		if service_runtime is Dictionary:
			for service_record: Variant in service_runtime.values():
				if service_record is Dictionary:
					var sid := _stable_item_id(service_record as Dictionary)
					if sid == item_id:
						load_error = "item_runtime_authority_item_id_collision"
						return false

	item_runtime_authority = parsed
	return true


func _load_dpv2_drop_authorities() -> bool:
	dpv2_item_tier_authority = {}
	dpv2_monster_role_authority = {}
	dpv2_global_drop_rate_authority = {}
	dpv2_drop_runtime_authority = {}
	_dpv2_item_tier_by_id.clear()
	_dpv2_item_tier_by_name.clear()
	_dpv2_monster_role_by_id.clear()
	_dpv2_global_scale_by_preset.clear()
	_dpv2_item_overflow_by_id.clear()
	_dpv2_item_overflow_by_name.clear()

	for path: String in [
		DPV2_ITEM_TIER_AUTHORITY_PATH,
		DPV2_MONSTER_ROLE_AUTHORITY_PATH,
		DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH,
		DPV2_DROP_RUNTIME_AUTHORITY_PATH,
	]:
		if not FileAccess.file_exists(path):
			load_error = "dpv2_drop_authority_missing:%s" % path
			return false

	var tier_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_ITEM_TIER_AUTHORITY_PATH)
	)
	var role_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_MONSTER_ROLE_AUTHORITY_PATH)
	)
	var global_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH)
	)
	var runtime_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_DROP_RUNTIME_AUTHORITY_PATH)
	)
	if (
		not tier_value is Dictionary
		or not role_value is Dictionary
		or not global_value is Dictionary
		or not runtime_value is Dictionary
	):
		load_error = "dpv2_drop_authority_invalid_json"
		return false

	var tier_authority: Dictionary = tier_value
	var role_authority: Dictionary = role_value
	var global_authority: Dictionary = global_value
	var runtime_authority: Dictionary = runtime_value
	var expected_source_authorities: Dictionary = {
		"item_tier": {
			"path": DPV2_ITEM_TIER_AUTHORITY_PATH,
			"schema": "hardcore.dpv2.item_tier_authority.v1",
		},
		"monster_role": {
			"path": DPV2_MONSTER_ROLE_AUTHORITY_PATH,
			"schema": "hardcore.dpv2.monster_role_authority.v1",
		},
		"global_scale": {
			"path": DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH,
			"schema": "hardcore.dpv2.global_drop_rate_authority.v1",
		},
	}
	var declared_source_authorities: Variant = runtime_authority.get(
		"source_authorities",
		null
	)
	if not declared_source_authorities is Dictionary:
		load_error = "dpv2_source_authorities_missing"
		return false
	for raw_key: Variant in expected_source_authorities.keys():
		var key := str(raw_key)
		var expected: Dictionary = expected_source_authorities[key]
		var declared_value: Variant = declared_source_authorities.get(key, null)
		if not declared_value is Dictionary:
			load_error = "dpv2_source_authority_missing:%s" % key
			return false
		var declared: Dictionary = declared_value
		var declared_path := str(declared.get("path", ""))
		var expected_path := str(expected.get("path", ""))
		var normalized_declared_path := declared_path.trim_prefix("res://")
		var normalized_expected_path := expected_path.trim_prefix("res://")
		var declared_schema := str(declared.get("schema", ""))
		var expected_schema := str(expected.get("schema", ""))
		var declared_sha := str(declared.get("sha256", "")).to_upper()
		var actual_sha := _sha256_lf_file(expected_path)
		if (
			normalized_declared_path != normalized_expected_path
			or declared_schema != expected_schema
			or actual_sha.is_empty()
			or declared_sha != actual_sha
		):
			load_error = "dpv2_source_authority_binding_invalid:%s" % key
			return false
	if (
		str(tier_authority.get("schema", ""))
			!= "hardcore.dpv2.item_tier_authority.v1"
	):
		load_error = "dpv2_item_tier_authority_contract_invalid"
		return false
	if (
		str(role_authority.get("schema", ""))
			!= "hardcore.dpv2.monster_role_authority.v1"
	):
		load_error = "dpv2_monster_role_authority_contract_invalid"
		return false
	if (
		str(runtime_authority.get("schema", ""))
			!= "hardcore.dpv2.drop_runtime_authority.v1"
		or not bool(runtime_authority.get("activation", {}).get("production_active", false))
		or int(runtime_authority.get("ground_overflow_policy", {}).get(
			"maximum_ground_slots", 0
		)) != 9
		or int(runtime_authority.get("source_slot_contract", {}).get(
			"canonical_source_slot_count", 0
		)) != 7032
		or bool(runtime_authority.get("source_slot_contract", {}).get(
			"source_slot_mutated", true
		))
		or int(runtime_authority.get("source_slot_contract", {}).get(
			"canonical_source_slots", 0
		)) != 7032
		or int(runtime_authority.get("source_slot_contract", {}).get(
			"drop_enabled_source_slots", -1
		)) != 5995
		or int(runtime_authority.get("source_slot_contract", {}).get(
			"drop_disabled_source_slots", -1
		)) != 1037
		or int(runtime_authority.get("source_slot_contract", {}).get(
			"reward_resolved_enabled_slots", -1
		)) != 5995
		or int(runtime_authority.get("source_slot_contract", {}).get(
			"probability_resolved_enabled_slots", -1
		)) != 5995
		or int(runtime_authority.get("source_slot_contract", {}).get(
			"rng_eligible_slots", -1
		)) != 5995
		or int(runtime_authority.get("source_slot_contract", {}).get(
			"rng_roll_count", -1
		)) != 5995
		or not bool(runtime_authority.get("source_slot_contract", {}).get(
			"all_enabled_resolved_slots_rng_before_overflow", false
		))
	):
		load_error = "dpv2_drop_runtime_authority_contract_invalid"
		return false
	if (
		str(global_authority.get("schema", ""))
			!= "hardcore.dpv2.global_drop_rate_authority.v1"
		or not bool(global_authority.get("activation", {}).get("production_active", false))
		or str(global_authority.get("authority", {}).get("control_key", ""))
			!= "global_drop_rate_scale"
	):
		load_error = "dpv2_global_drop_rate_authority_contract_invalid"
		return false

	var tier_records: Variant = tier_authority.get("records", [])
	if not tier_records is Array or tier_records.size() != 233:
		load_error = "dpv2_item_tier_authority_count_invalid"
		return false
	for raw_record: Variant in tier_records:
		if not raw_record is Dictionary:
			load_error = "dpv2_item_tier_record_invalid"
			return false
		var record: Dictionary = raw_record
		var item_id := int(record.get("canonical_item_id", -1))
		var item_name := str(record.get("canonical_name", ""))
		if (
			item_id <= 0
			or item_name.is_empty()
			or str(record.get("tier_status", "")) != "RESOLVED"
			or int(record.get("base_denominator", 0)) <= 0
			or record.get("denominator_override", null) != null
			or _dpv2_item_tier_by_id.has(item_id)
			or _dpv2_item_tier_by_name.has(item_name)
		):
			load_error = "dpv2_item_tier_record_identity_invalid"
			return false
		_dpv2_item_tier_by_id[item_id] = record.duplicate(true)
		_dpv2_item_tier_by_name[item_name] = record.duplicate(true)
	var overflow_records: Variant = runtime_authority.get("item_overflow_records", [])
	if not overflow_records is Array or overflow_records.size() != 233:
		load_error = "dpv2_item_overflow_authority_count_invalid"
		return false
	for raw_overflow: Variant in overflow_records:
		if not raw_overflow is Dictionary:
			load_error = "dpv2_item_overflow_record_invalid"
			return false
		var overflow_record: Dictionary = raw_overflow
		var overflow_item_id := int(overflow_record.get("canonical_item_id", -1))
		var overflow_name := str(overflow_record.get("canonical_name", ""))
		var overflow_tier := str(overflow_record.get("tier", ""))
		var priority := int(overflow_record.get("overflow_priority", 0))
		var tier_match: Variant = _dpv2_item_tier_by_id.get(overflow_item_id, {})
		var expected_overflow := _dpv2_expected_overflow_policy(overflow_tier)
		if (
			overflow_item_id <= 0
			or overflow_name.is_empty()
			or overflow_tier.is_empty()
			or priority not in [100, 200, 300, 400]
			or _dpv2_item_overflow_by_id.has(overflow_item_id)
			or _dpv2_item_overflow_by_name.has(overflow_name)
			or not tier_match is Dictionary
			or str(tier_match.get("canonical_name", "")) != overflow_name
			or str(tier_match.get("tier", "")) != overflow_tier
			or str(overflow_record.get("priority_band", ""))
				!= str(expected_overflow.get("priority_band", ""))
			or str(overflow_record.get("overflow_class", ""))
				!= str(expected_overflow.get("overflow_class", ""))
			or bool(overflow_record.get("protected_drop", false))
				!= bool(expected_overflow.get("protected_drop", false))
			or priority != int(expected_overflow.get("overflow_priority", 0))
		):
			load_error = "dpv2_item_overflow_identity_invalid"
			return false
		_dpv2_item_overflow_by_id[overflow_item_id] = overflow_record.duplicate(true)
		_dpv2_item_overflow_by_name[overflow_name] = overflow_record.duplicate(true)
	var gold_policy: Variant = runtime_authority.get("gold_policy", {})
	if (
		not gold_policy is Dictionary
		or str(gold_policy.get("tier", "")) != "GOLD_COMMON"
		or int(gold_policy.get("base_denominator", 0)) <= 0
		or int(gold_policy.get("overflow_priority", 0)) != 100
		or bool(gold_policy.get("protected_drop", true))
	):
		load_error = "dpv2_gold_tier_policy_invalid"
		return false

	var role_records: Variant = role_authority.get("monsters", [])
	if not role_records is Array or role_records.size() != 156:
		load_error = "dpv2_monster_role_authority_count_invalid"
		return false
	for raw_role: Variant in role_records:
		if not raw_role is Dictionary:
			load_error = "dpv2_monster_role_record_invalid"
			return false
		var role_record: Dictionary = raw_role
		var monster_id := int(role_record.get("canonical_monster_id", -1))
		var drop_enabled := bool(role_record.get("drop_enabled", false))
		var drop_role: Variant = role_record.get("drop_role", null)
		var role_factor: Variant = role_record.get("role_factor", null)
		if monster_id <= 0 or _dpv2_monster_role_by_id.has(monster_id):
			load_error = "dpv2_monster_role_identity_invalid"
			return false
		if drop_enabled:
			var role_ratio := _dpv2_role_ratio(str(drop_role))
			if (
				role_ratio.x <= 0
				or role_ratio.y <= 0
				or role_factor == null
				or not is_equal_approx(
					float(role_factor),
					float(role_ratio.x) / float(role_ratio.y)
				)
			):
				load_error = "dpv2_monster_probability_role_invalid"
				return false
		elif (
			drop_role != null
			or role_factor != null
			or str(role_record.get("reporting_label", "")) != "NON_LOOT"
		):
			load_error = "dpv2_non_loot_state_invalid"
			return false
		_dpv2_monster_role_by_id[monster_id] = role_record.duplicate(true)

	var expected_presets := {
		"0.5x": Vector2i(1, 2),
		"0.8x": Vector2i(4, 5),
		"1x": Vector2i(1, 1),
		"1.5x": Vector2i(3, 2),
		"2x": Vector2i(2, 1),
	}
	var presets: Variant = global_authority.get("presets", [])
	if not presets is Array or presets.size() != expected_presets.size():
		load_error = "dpv2_global_drop_rate_presets_invalid"
		return false
	for raw_preset: Variant in presets:
		if not raw_preset is Dictionary:
			load_error = "dpv2_global_drop_rate_preset_invalid"
			return false
		var preset: Dictionary = raw_preset
		var preset_name := str(preset.get("preset", ""))
		var ratio := Vector2i(
			int(preset.get("numerator", 0)),
			int(preset.get("denominator", 0))
		)
		if not expected_presets.has(preset_name) or ratio != expected_presets[preset_name]:
			load_error = "dpv2_global_drop_rate_preset_ratio_invalid"
			return false
		_dpv2_global_scale_by_preset[preset_name] = ratio
	var active_preset := str(global_authority.get("active_preset", ""))
	if not _dpv2_global_scale_by_preset.has(active_preset):
		load_error = "dpv2_global_drop_rate_active_preset_invalid"
		return false

	dpv2_item_tier_authority = tier_authority
	dpv2_monster_role_authority = role_authority
	dpv2_global_drop_rate_authority = global_authority
	dpv2_drop_runtime_authority = runtime_authority
	return true


func _sha256_lf_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var text := FileAccess.get_file_as_string(path)
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode().to_upper()


func _load_equipment_price_candidates() -> void:
	equipment_price_candidates = {}
	if not FileAccess.file_exists(EQUIPMENT_PRICE_CANDIDATES_PATH):
		return
	var file := FileAccess.open(EQUIPMENT_PRICE_CANDIDATES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		equipment_price_candidates = parsed
	else:
		push_warning("装备价格候选文件不是有效JSON：%s" % EQUIPMENT_PRICE_CANDIDATES_PATH)


func _load_merchant_catalog() -> void:
	merchant_catalog = {}
	if not FileAccess.file_exists(MERCHANT_CATALOG_PATH):
		push_error("正式商人目录不存在：%s" % MERCHANT_CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MERCHANT_CATALOG_PATH))
	if parsed is Dictionary and str(parsed.get("contractId", "")) == "gameplay.merchant_catalog.v1":
		merchant_catalog = parsed
	else:
		push_error("正式商人目录无效：%s" % MERCHANT_CATALOG_PATH)


func merchant_stock(stock_key: String) -> Array:
	var merchant: Dictionary = merchant_catalog.get("merchants", {}).get(stock_key, {})
	if merchant.is_empty():
		return []
	var result: Array = []
	for raw_offer: Variant in merchant.get("offers", []):
		if not raw_offer is Dictionary or not bool(raw_offer.get("resolved", false)):
			continue
		var offer: Dictionary = raw_offer
		var merchant_types: Array[int] = []
		for raw_type: Variant in merchant.get("types", []):
			merchant_types.append(int(raw_type))
		result.append({
			"name": str(offer.get("itemName", "")),
			"pack_count": maxi(1, int(offer.get("packCount", 1))),
			"offer_id": str(offer.get("offerId", "")),
			"merchant_id": str(merchant.get("merchantId", "")),
			"merchant_context": {
				"stock_key": stock_key,
				"merchant_id": str(merchant.get("merchantId", "")),
				"merchant_rate_bps": int(merchant.get("merchantRateBps", 10000)),
				"stock_markup_bps": int(merchant.get("stockMarkupBps", 11000)),
				"types": merchant_types,
				"supports_repair": bool(merchant.get("supportsRepair", false)),
			},
		})
	return result


func merchant_context(stock_key: String) -> Dictionary:
	var merchant: Dictionary = merchant_catalog.get("merchants", {}).get(stock_key, {})
	var merchant_types: Array[int] = []
	for raw_type: Variant in merchant.get("types", []):
		merchant_types.append(int(raw_type))
	return {
		"stock_key": stock_key,
		"merchant_id": str(merchant.get("merchantId", "")),
		"merchant_rate_bps": int(merchant.get("merchantRateBps", 10000)),
		"stock_markup_bps": int(merchant.get("stockMarkupBps", 11000)),
		"types": merchant_types,
		"supports_repair": bool(merchant.get("supportsRepair", false)),
	} if not merchant.is_empty() else {}


func item_usage_summary(item_name: String, player_level := -1) -> Dictionary:
	# Return canonical player-facing use values for a catalog item. The service
	# catalog is authoritative; UI must not guess from names or render equipment
	# template fields for consumables.
	var record := get_item_record(item_name)
	if record.is_empty():
		return {}
	var stats: Dictionary = record.get("stats", {}) if record.get("stats", {}) is Dictionary else {}
	var restore_health := int(record.get("restoreHealth", record.get("healthRestore", stats.get("HP", 0))))
	var restore_mana := int(record.get("restoreMana", record.get("manaRestore", stats.get("MP", 0))))
	var effect_type := str(record.get("useEffect", ""))
	var recovery := potion_recovery_profile(
		player_level if player_level >= 0 else int(PlayerState.level),
		restore_health,
		restore_mana,
		effect_type,
	)
	return {
		"item_name": str(record.get("name", item_name)),
		"kind": str(record.get("kind", "unknown")),
		"category": str(record.get("category", "")),
		"restore_health": maxi(0, restore_health),
		"restore_mana": maxi(0, restore_mana),
		"use_effect": effect_type,
		"effect_type": str(recovery.get("effect_type", "instant")),
		"total_restore_health": int(recovery.get("total_restore_health", 0)),
		"total_restore_mana": int(recovery.get("total_restore_mana", 0)),
		"total_restore": int(recovery.get("total_restore", 0)),
		"tick_amount": int(recovery.get("tick_amount", 0)),
		"tick_interval_seconds": float(recovery.get("tick_interval_seconds", 0.0)),
		"recovery_per_second": float(recovery.get("recovery_per_second", 0.0)),
		"duration_seconds": float(recovery.get("duration_seconds", 0.0)),
		"tick_count": int(recovery.get("tick_count", 0)),
		"player_level": int(recovery.get("player_level", 1)),
		"usable": bool(record.get("usable", str(record.get("kind", "")) == "consumable")),
		"stackable": bool(record.get("stackable", false)),
		"description": str(record.get("description", record.get("toolTip", ""))),
	}


func potion_recovery_profile(player_level: int, restore_health: int, restore_mana: int, use_effect: String) -> Dictionary:
	# Keep this display projection identical to Player._process_potion_restore:
	# interval=(600-min(400, level*10))/1000s; tick=5+floor(level/10).
	var level := maxi(1, player_level)
	var health_total := maxi(0, restore_health)
	var mana_total := maxi(0, restore_mana)
	var total_restore := health_total + mana_total
	var delayed := use_effect == "delayed_restore" and total_restore > 0
	if not delayed:
		return {
			"effect_type": "instant",
			"total_restore_health": health_total,
			"total_restore_mana": mana_total,
			"total_restore": total_restore,
			"tick_amount": 0,
			"tick_interval_seconds": 0.0,
			"recovery_per_second": 0.0,
			"duration_seconds": 0.0,
			"tick_count": 0,
			"player_level": level,
		}
	var tick_amount := 5 + int(level / 10)
	var tick_interval_seconds := float(600 - mini(400, level * 10)) / 1000.0
	var ticks := int(ceil(float(maxi(health_total, mana_total)) / float(tick_amount)))
	return {
		"effect_type": "delayed_restore",
		"total_restore_health": health_total,
		"total_restore_mana": mana_total,
		"total_restore": total_restore,
		"tick_amount": tick_amount,
		"tick_interval_seconds": tick_interval_seconds,
		"recovery_per_second": float(tick_amount) / tick_interval_seconds,
		# The first queued tick resolves immediately on the next process frame;
		# only the remaining ticks wait for the interval.
		"duration_seconds": float(maxi(0, ticks - 1)) * tick_interval_seconds,
		"tick_count": ticks,
		"player_level": level,
	}


func merchant_context_by_id(merchant_id: String) -> Dictionary:
	if merchant_id.is_empty():
		return {}
	for stock_key: String in (merchant_catalog.get("merchants", {}) as Dictionary).keys():
		var context := merchant_context(stock_key)
		if str(context.get("merchant_id", "")) == merchant_id:
			context["stock_key"] = stock_key
			return context
	return {}


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


func _load_equipment_visual_catalog() -> void:
	equipment_visual_catalog = {}
	if not FileAccess.file_exists(EQUIPMENT_VISUAL_CATALOG_PATH):
		push_warning("正式装备视觉目录不存在：%s" % EQUIPMENT_VISUAL_CATALOG_PATH)
		return
	var file := FileAccess.open(EQUIPMENT_VISUAL_CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		equipment_visual_catalog = parsed
	else:
		push_warning("正式装备视觉目录不是有效JSON：%s" % EQUIPMENT_VISUAL_CATALOG_PATH)


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


func apply_equipment_visual_mappings(base_items: Array, visual_catalog: Dictionary) -> Array:
	var result: Array = []
	var mappings: Dictionary = visual_catalog.get("runtimeMappings", {})
	for value: Variant in base_items:
		if not value is Dictionary:
			continue
		var record: Dictionary = value.duplicate(true)
		var mapping: Variant = mappings.get(str(record.get("name", "")), {})
		if mapping is Dictionary and not mapping.is_empty():
			var art: Dictionary = record.get("art", {}).duplicate(true)
			record["art"] = _deep_merge_dictionary(art, mapping)
		result.append(record)
	return result


func _deep_merge_dictionary(base: Dictionary, overlay: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key: Variant in overlay:
		var incoming: Variant = overlay[key]
		if incoming is Dictionary and result.get(key, null) is Dictionary:
			result[key] = _deep_merge_dictionary(result[key], incoming)
		else:
			result[key] = incoming.duplicate(true) if incoming is Dictionary or incoming is Array else incoming
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
	_items_by_name.clear()
	_items_by_id.clear()
	_maps_by_id.clear()
	_maps_by_name.clear()
	for entry: Variant in maps:
		if not entry is Dictionary:
			continue
		_maps_by_id[int(entry.get("mapId", -1))] = entry
		var map_name := str(entry.get("name", ""))
		if not _maps_by_name.has(map_name):
			_maps_by_name[map_name] = entry
	for entry: Variant in items:
		if entry is Dictionary:
			var item_name := str(entry.get("name", ""))
			_items_by_name[item_name] = entry
			var item_id := _stable_item_id(entry)
			if item_id >= 0:
				_items_by_id[item_id] = entry
	_build_item_catalog()
	_build_canonical_monster_runtime_drop_closure()


func _build_canonical_monster_runtime_drop_closure() -> void:
	_monster_runtime_drop_closure.clear()
	monsters.clear()
	bosses.clear()
	for raw_id: Variant in _monsters_by_id.keys():
		var monster_id := int(raw_id)
		var entry: Dictionary = _monsters_by_id.get(monster_id, {})
		if not bool(entry.get("runtime_allowed", false)):
			_monster_runtime_drop_closure[monster_id] = {
				"allowed": false,
				"reason": "catalog_runtime_disabled",
				"resolved_non_gold_count": 0,
				"resolved_gold_count": 0,
				"resolved_reward_count": 0,
				"requires_non_empty": false,
				"exemption_applied": false,
			}
			continue
		# Runtime drop requirement authority is the canonical drop_policy.
		# GameData must NOT re-derive hostile from classification.
		var drop_policy: Dictionary = entry.get("drop_policy", {})
		var requires_non_empty := bool(
			drop_policy.get("hostile_requires_non_empty", false)
		)
		var exemption_value: Variant = drop_policy.get("exemption", null)
		var exemption_valid := (
			exemption_value is Dictionary
			and bool(exemption_value.get("allowed", false))
			and not str(exemption_value.get("reason", "")).is_empty()
		)
		var profile := _canonical_drop_profile_unchecked(entry)
		var resolved_non_gold_count := 0
		var resolved_gold_count := 0
		for raw_drop: Variant in profile.get("entries", []):
			if not raw_drop is Dictionary:
				continue
			var reward := resolve_canonical_drop_reward(raw_drop)
			if not bool(reward.get("ok", false)):
				continue
			if str(reward.get("kind", "")) == "gold":
				resolved_gold_count += 1
			else:
				resolved_non_gold_count += 1
		var resolved_reward_count := resolved_non_gold_count + resolved_gold_count
		var allowed := (
			not requires_non_empty
			or exemption_valid
			or (not profile.is_empty() and resolved_reward_count > 0)
		)
		_monster_runtime_drop_closure[monster_id] = {
			"allowed": allowed,
			"reason": "" if allowed else "drop_items_unresolved",
			"resolved_non_gold_count": resolved_non_gold_count,
			"resolved_gold_count": resolved_gold_count,
			"resolved_reward_count": resolved_reward_count,
			"requires_non_empty": requires_non_empty,
			"exemption_applied": exemption_valid,
		}
		if allowed:
			monsters.append(entry.duplicate(true))
			if str(entry.get("classification", "")) == "boss":
				bosses.append(entry.duplicate(true))



func _apply_item_runtime_authority_overrides(record: Dictionary, skill_names: Dictionary) -> Dictionary:
	var result: Dictionary = record.duplicate(true)
	var name := str(result.get("name", ""))
	var kind := str(result.get("kind", ""))
	var service_index := int(result.get("serviceIndex", result.get("service_index", -1)))
	var policies: Dictionary = item_runtime_authority.get("policies", {})

	if kind == "skill_book" and skill_names.has(name):
		var book_policy: Variant = policies.get("vanillaSkillBook", {})
		if book_policy is Dictionary:
			if book_policy.has("stackable"):
				result["stackable"] = book_policy["stackable"]
			if book_policy.has("maxStack"):
				result["maxStack"] = book_policy["maxStack"]

	var overrides_by_index: Variant = policies.get("serviceOverridesByIndex", {})
	if overrides_by_index is Dictionary:
		var override_key := str(service_index)
		if overrides_by_index.has(override_key):
			var override_entry: Variant = overrides_by_index[override_key]
			if override_entry is Dictionary:
				for key: String in override_entry:
					result[key] = override_entry[key]

	return result
func _build_item_catalog() -> void:
	item_catalog.clear()
	_catalog_by_name.clear()
	_catalog_by_item_id.clear()
	_catalog_by_service_index.clear()
	_build_price_index()
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
		var override_record := _apply_item_runtime_authority_overrides(service_record, skill_names)
		_register_catalog_item(override_record)
	for special_item: Variant in service_item_catalog.get("runtimeSpecials", {}).values():
		if special_item is Dictionary:
			var override_special := _apply_item_runtime_authority_overrides(special_item.duplicate(true), skill_names)
			_register_catalog_item(override_special)



		# ITEM-P0C-FULL: register runtime authority newItems before fallback.
	for authority_item: Variant in item_runtime_authority.get("newItems", []):
		if authority_item is Dictionary:
			_register_catalog_item((authority_item as Dictionary).duplicate(true))

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
	# Catalog category/kind is the player-facing canonical classification. Price
	# records keep the database identity and adopt only these non-price fields.
	for item_name: String in _price_by_name.keys():
		var catalog: Dictionary = _catalog_by_name.get(item_name, {})
		if not catalog.is_empty():
			_price_by_name[item_name]["kind"] = str(catalog.get("kind", _price_by_name[item_name].get("kind", "unknown")))
			_price_by_name[item_name]["category"] = str(catalog.get("category", _price_by_name[item_name].get("category", "")))


func _build_price_index() -> void:
	_price_by_name.clear()
	_price_by_item_id.clear()
	_price_by_service_index.clear()
	for raw: Variant in service_item_catalog.get("serviceEquipmentReference", []):
		_register_price_record(raw)
	for raw: Variant in service_item_catalog.get("runtimeItems", []):
		_register_price_record(raw)
	for raw: Variant in service_item_catalog.get("runtimeSpecials", {}).values():
		_register_price_record(raw)
	# Primary database records always register first. These candidates are used
	# only for exact official items proven missing from every configured
	# server_data source; _register_price_record never overwrites an existing
	# primary record.
	for raw: Variant in equipment_price_candidates.get("records", []):
		_register_price_record(raw)


func _register_price_record(raw: Variant) -> void:
	if not raw is Dictionary:
		return
	var source_record: Dictionary = raw
	var source_name := str(source_record.get("name", source_record.get("serviceName", "")))
	var canonical_name := _canonical_item_name(source_name)
	var base_price := maxi(0, int(source_record.get("price", 0)))
	if canonical_name.is_empty() or base_price <= 0:
		return
	var service_index := _service_index(source_record)
	var item_id := _stable_item_id(source_record)
	# Candidate equipment records intentionally omit itemId because their source
	# only carries the official item name. Resolve that identity against the
	# already-loaded primary runtime item table; the candidate still supplies
	# only the missing price and never replaces an existing primary record.
	if item_id < 0:
		item_id = _item_id_for_name(canonical_name)
	if service_index < 0 and str(source_record.get("kind", "")) == "equipment" and item_id < 0:
		return
	if _price_by_name.has(canonical_name):
		return
	if service_index >= 0 and _price_by_service_index.has(service_index):
		return
	if item_id >= 0 and _price_by_item_id.has(item_id):
		return
	var price_record := {
		"item_key": (
			"service:%d" % service_index
			if service_index >= 0
			else "item:%d" % item_id
			if item_id >= 0
			else "name:%s" % canonical_name
		),
		"item_name": canonical_name,
		"item_id": item_id,
		"service_index": service_index,
		"service_type": int(source_record.get("serviceType", -1)),
		"base_price": base_price,
		"kind": str(source_record.get("kind", "unknown")),
		"category": str(source_record.get("category", "")),
		"source": (source_record.get("source", {}) as Dictionary).duplicate(true),
	}
	_price_by_name[canonical_name] = price_record
	if service_index >= 0:
		_price_by_service_index[service_index] = price_record
	if item_id >= 0:
		_price_by_item_id[item_id] = price_record


func _register_catalog_item(record: Dictionary) -> void:
	var item_name := str(record.get("name", ""))
	if item_name.is_empty() or _catalog_by_name.has(item_name):
		return
	_catalog_by_name[item_name] = record
	var item_id := _stable_item_id(record)
	if item_id >= 0 and not _catalog_by_item_id.has(item_id):
		_catalog_by_item_id[item_id] = record
	var service_index := _service_index(record)
	if service_index >= 0 and not _catalog_by_service_index.has(service_index):
		_catalog_by_service_index[service_index] = record
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


func canonical_monster_id(raw_value: Variant) -> int:
	if raw_value is int:
		return int(raw_value) if int(raw_value) > 0 else -1
	# Godot JSON numbers are floats.  Permit only a lossless positive integer
	# token at this boundary; numeric strings and every legacy transport form
	# remain rejected by the ID-only runtime API.
	if raw_value is float:
		var numeric_value := float(raw_value)
		if (
			is_finite(numeric_value)
			and numeric_value > 0.0
			and numeric_value == floorf(numeric_value)
			and numeric_value <= 9007199254740991.0
		):
			return int(numeric_value)
	return -1


func get_canonical_monster_entry(
	monster_id: int,
	use_context := "runtime"
) -> Dictionary:
	var resolved_id := canonical_monster_id(monster_id)
	if resolved_id <= 0:
		return {}
	var entry_value: Variant = _monsters_by_id.get(resolved_id, {})
	if not entry_value is Dictionary or entry_value.is_empty():
		return {}
	var entry: Dictionary = entry_value
	var context := str(use_context)
	if context not in ["catalog", "runtime", "spawn", "combat", "editor"]:
		return {}
	if context in ["runtime", "spawn", "combat"]:
		if not bool(entry.get("runtime_allowed", false)):
			return {}
		var closure: Dictionary = _monster_runtime_drop_closure.get(
			resolved_id, {}
		)
		if not bool(closure.get("allowed", false)):
			return {}
	elif context == "editor":
		if not bool(entry.get("editor_placement", {}).get("allowed", false)):
			return {}
	return entry.duplicate(true)


func get_monster_by_id(monster_id: int) -> Dictionary:
	return get_canonical_monster_entry(monster_id, "runtime")


func get_monster(_monster_name: String) -> Dictionary:
	# Name-only monster lookup is intentionally retired.  Keeping a fail-closed
	# method makes stale callers obvious without silently selecting a same-name
	# variant from the abandoned database.
	return {}


func get_canonical_monster_drop_profile(monster_id: int) -> Dictionary:
	var entry := get_canonical_monster_entry(monster_id, "runtime")
	if entry.is_empty():
		return {}
	return _canonical_drop_profile_unchecked(entry)


func canonical_monster_runtime_drop_closure(monster_id: int) -> Dictionary:
	var resolved_id := canonical_monster_id(monster_id)
	var value: Variant = _monster_runtime_drop_closure.get(resolved_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func canonical_monster_counts() -> Dictionary:
	var catalog_runtime_allowed_count := 0
	for raw_entry: Variant in _monsters_by_id.values():
		if raw_entry is Dictionary and bool(raw_entry.get("runtime_allowed", false)):
			catalog_runtime_allowed_count += 1
	return {
		"contract_id": CANONICAL_MONSTER_COUNTS_CONTRACT_ID,
		"catalog_identity_count": _monsters_by_id.size(),
		"catalog_runtime_allowed_count": catalog_runtime_allowed_count,
		"runtime_spawnable_count": monsters.size(),
		"runtime_rejected_count": (
			catalog_runtime_allowed_count - monsters.size()
		),
		"runtime_boss_count": bosses.size(),
	}


func _canonical_drop_profile_unchecked(entry: Dictionary) -> Dictionary:
	var profile_id := str(entry.get("drop_profile_id", ""))
	var profiles: Variant = canonical_monster_catalog.get("drop_profiles", {})
	if profile_id.is_empty() or not profiles is Dictionary:
		return {}
	var profile_value: Variant = profiles.get(profile_id, {})
	if not profile_value is Dictionary:
		return {}
	var profile: Dictionary = profile_value
	var drop_entries: Variant = profile.get("entries", [])
	# Empty drop profiles are only rejected when canonical policy actually
	# requires non-empty drops and no valid exemption applies. GameData must not
	# re-derive hostile from classification.
	var drop_policy: Dictionary = entry.get("drop_policy", {})
	var requires_non_empty := bool(
		drop_policy.get("hostile_requires_non_empty", false)
	)
	var exemption_value: Variant = drop_policy.get("exemption", null)
	var exemption_valid := (
		exemption_value is Dictionary
		and bool(exemption_value.get("allowed", false))
		and not str(exemption_value.get("reason", "")).is_empty()
	)
	if (
		requires_non_empty
		and not exemption_valid
		and (not drop_entries is Array or drop_entries.is_empty())
	):
		return {}
	return profile.duplicate(true)


func resolve_canonical_drop_item(drop_entry: Dictionary) -> Dictionary:
	var token := str(drop_entry.get("item", ""))
	if token.is_empty() or token != token.strip_edges():
		return {"ok": false, "reason": "invalid_item_token"}
	for index in range(token.length()):
		var codepoint := token.unicode_at(index)
		if codepoint < 32 or codepoint == 0x7f or codepoint == 0xfffd:
			return {"ok": false, "reason": "invalid_item_token"}
	# Gold rows carry an amount separate from their raw item token.  The current
	# ground-pickup contract has no quantity-bearing currency identity, so do not
	# silently collapse e.g. 15000 Gold into one coin.
	if drop_entry.has("gold"):
		return {"ok": false, "reason": "gold_amount_contract_unresolved"}
	var item := get_item_record(token)
	if item.is_empty():
		return {"ok": false, "reason": "unknown_item_token"}
	var canonical_name := _canonical_item_name(token)
	if str(item.get("name", "")) != canonical_name:
		return {"ok": false, "reason": "item_identity_mismatch"}
	var item_id := _stable_item_id(item)
	var service_index := _service_index(item)
	var source: Variant = item.get("source", {})
	if item_id < 0 and service_index < 0 and (
		not source is Dictionary or source.is_empty()
	):
		return {"ok": false, "reason": "item_authority_unresolved"}
	return {
		"ok": true,
		"reason": "",
		"item_name": canonical_name,
		"item_id": item_id,
		"service_index": service_index,
	}


## Canonical unified drop reward resolver: ordinary items OR quantity gold.
## Keeps resolve_canonical_drop_item() untouched as the item identity authority.
func resolve_canonical_drop_reward(drop_entry: Dictionary) -> Dictionary:
	if drop_entry.has("gold"):
		if str(drop_entry.get("item", "")) != "金币":
			return {"ok": false, "reason": "invalid_gold_token"}
		var amount := int(drop_entry.get("gold", 0))
		if amount <= 0:
			return {"ok": false, "reason": "invalid_gold_amount"}
		return {
			"ok": true,
			"reason": "",
			"kind": "gold",
			"item_name": "金币",
			"gold_amount": amount,
		}
	var item_result := resolve_canonical_drop_item(drop_entry)
	if not bool(item_result.get("ok", false)):
		return item_result
	var item_authority: Variant = _dpv2_item_tier_by_name.get(
		str(item_result.get("item_name", "")), {}
	)
	if not item_authority is Dictionary or item_authority.is_empty():
		return {"ok": false, "reason": "dpv2_item_tier_authority_unresolved"}
	item_result["canonical_item_id"] = int(
		item_authority.get("canonical_item_id", -1)
	)
	item_result["kind"] = "item"
	return item_result


func dpv2_monster_drop_state(monster_id: int) -> Dictionary:
	var resolved_id := canonical_monster_id(monster_id)
	var value: Variant = _dpv2_monster_role_by_id.get(resolved_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func dpv2_active_global_drop_rate() -> Dictionary:
	var preset := str(dpv2_global_drop_rate_authority.get("active_preset", ""))
	var ratio: Variant = _dpv2_global_scale_by_preset.get(preset, Vector2i.ZERO)
	if not ratio is Vector2i or ratio.x <= 0 or ratio.y <= 0:
		return {}
	return {
		"preset": preset,
		"numerator": ratio.x,
		"denominator": ratio.y,
	}


func dpv2_ground_slot_limit() -> int:
	return int(
		dpv2_drop_runtime_authority.get("ground_overflow_policy", {}).get(
			"maximum_ground_slots", 0
		)
	)


func _dpv2_expected_overflow_policy(tier: String) -> Dictionary:
	if tier == "BOSS_KEY_ITEM":
		return {
			"overflow_class": "PROTECTED_PROGRESS",
			"protected_drop": true,
			"overflow_priority": 400,
			"priority_band": "progress_key",
		}
	if tier in [
		"BOOK_35",
		"BOOK_HIGH",
		"REDMOON_SET",
		"NEW_CLOTHES",
		"LEGENDARY_WEAPON",
		"SPECIAL_RING",
		"ZUMA_GEAR",
		"HIGH_CLASS_WEAPON",
		"EXPANDED_HIGH_WEAPON",
		"MYSTERY_SIGNATURE",
		"PRAYER_MEMORY",
		"MAGICBLOOD_RAINBOW",
		"RARE_CONSUMABLE",
		"FUNCTIONAL_SPECIAL",
		"SOLAR_CONSUMABLE",
	]:
		return {
			"overflow_class": "PROTECTED_HIGH_VALUE",
			"protected_drop": true,
			"overflow_priority": 300,
			"priority_band": "high_value_tier",
		}
	if tier in ["EQUIP_LOW", "EQUIP_MID", "EQUIP_HIGH_MID", "WOOMA_GEAR"]:
		return {
			"overflow_class": "EQUIPMENT_STANDARD",
			"protected_drop": false,
			"overflow_priority": 200,
			"priority_band": "standard_equipment",
		}
	if tier in ["BOOK_LOW", "BOOK_MID"]:
		return {
			"overflow_class": "BOOK_STANDARD",
			"protected_drop": false,
			"overflow_priority": 200,
			"priority_band": "standard_book",
		}
	return {
		"overflow_class": "ORDINARY_CONSUMABLE",
		"protected_drop": false,
		"overflow_priority": 100,
		"priority_band": "ordinary",
	}


func dpv2_source_slot_gate() -> Dictionary:
	var contract: Variant = dpv2_drop_runtime_authority.get(
		"source_slot_contract",
		{}
	)
	return contract.duplicate(true) if contract is Dictionary else {}


func dpv2_resolve_reward_policy(monster_id: int, reward: Dictionary) -> Dictionary:
	var monster_state := dpv2_monster_drop_state(monster_id)
	if monster_state.is_empty():
		return {"ok": false, "reason": "monster_role_authority_unresolved"}
	if not bool(monster_state.get("drop_enabled", false)):
		return {
			"ok": false,
			"reason": "drop_disabled",
			"reporting_label": str(monster_state.get("reporting_label", "")),
		}
	var role := str(monster_state.get("drop_role", ""))
	var role_ratio := _dpv2_role_ratio(role)
	if role_ratio.x <= 0 or role_ratio.y <= 0:
		return {"ok": false, "reason": "monster_probability_role_invalid"}

	var reward_policy: Dictionary = {}
	var reward_kind := str(reward.get("kind", ""))
	if reward_kind == "gold":
		var gold_value: Variant = dpv2_drop_runtime_authority.get("gold_policy", {})
		if gold_value is Dictionary:
			reward_policy = gold_value.duplicate(true)
	elif reward_kind == "item":
		var item_name := str(reward.get("item_name", ""))
		var item_value: Variant = _dpv2_item_tier_by_name.get(item_name, {})
		if item_value is Dictionary:
			reward_policy = item_value.duplicate(true)
		var overflow_value: Variant = _dpv2_item_overflow_by_name.get(
			item_name, {}
		)
		if overflow_value is Dictionary:
			for key: Variant in overflow_value.keys():
				reward_policy[key] = overflow_value[key]
	else:
		return {"ok": false, "reason": "reward_kind_invalid"}
	if reward_policy.is_empty():
		return {"ok": false, "reason": "reward_tier_authority_unresolved"}

	var base_denominator := int(reward_policy.get("base_denominator", 0))
	var global_scale := dpv2_active_global_drop_rate()
	if base_denominator <= 0 or global_scale.is_empty():
		return {"ok": false, "reason": "drop_probability_authority_invalid"}
	var numerator := role_ratio.x * int(global_scale.get("numerator", 0))
	var denominator := (
		role_ratio.y
		* int(global_scale.get("denominator", 0))
		* base_denominator
	)
	if numerator <= 0 or denominator <= 0:
		return {"ok": false, "reason": "drop_probability_ratio_invalid"}
	if numerator >= denominator:
		numerator = 1
		denominator = 1
	else:
		var divisor := _positive_gcd(numerator, denominator)
		numerator /= divisor
		denominator /= divisor
	return {
		"ok": true,
		"reason": "",
		"role": role,
		"role_factor_numerator": role_ratio.x,
		"role_factor_denominator": role_ratio.y,
		"tier": str(reward_policy.get("tier", "")),
		"base_denominator": base_denominator,
		"global_preset": str(global_scale.get("preset", "")),
		"probability_numerator": numerator,
		"probability_denominator": denominator,
		"overflow_class": str(reward_policy.get("overflow_class", (
			"ORDINARY_CONSUMABLE" if reward_kind == "gold" else ""
		))),
		"protected_drop": bool(reward_policy.get("protected_drop", false)),
		"overflow_priority": int(reward_policy.get("overflow_priority", 0)),
		"canonical_item_id": int(reward_policy.get("canonical_item_id", -1)),
	}


func _dpv2_role_ratio(role: String) -> Vector2i:
	match role:
		"COMMON":
			return Vector2i(1, 1)
		"STRONG_COMMON":
			return Vector2i(3, 2)
		"ELITE":
			return Vector2i(3, 1)
		"OFFICIAL_JP":
			return Vector2i(4, 1)
		"OFFICIAL_SUPER_JP":
			return Vector2i(5, 1)
		"MINOR_BOSS":
			return Vector2i(6, 1)
		"BOSS":
			return Vector2i(8, 1)
		"MAJOR_BOSS":
			return Vector2i(12, 1)
		"ENDGAME_BOSS", "NEW_CLOTHES_BOSS":
			return Vector2i(16, 1)
	return Vector2i.ZERO


func _positive_gcd(left: int, right: int) -> int:
	var a := absi(left)
	var b := absi(right)
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return maxi(1, a)


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


func get_bosses_for_map(_map_data: Dictionary) -> Array:
	# Retired compatibility boundary. Boss placement is authored by the formal
	# map runtime and resolved from numeric monster_id; map/name substring
	# matching is deliberately unavailable.
	return []


func get_item(item_name: String) -> Dictionary:
	return _items_by_name.get(_canonical_item_name(item_name), {})


func player_base_appearance(profession: String, gender: String) -> Dictionary:
	var profession_id := str(PROFESSION_VISUAL_IDS.get(profession, ""))
	var manifests: Dictionary = equipment_visual_catalog.get("professionManifests", {})
	var manifest: Variant = manifests.get(profession_id, {})
	if not manifest is Dictionary:
		return {}
	var by_gender: Variant = manifest.get("worldBaseByGender", {})
	if not by_gender is Dictionary:
		return {}
	var resolved_gender := gender if gender in ["男", "女"] else "男"
	var appearance: Variant = by_gender.get(resolved_gender, by_gender.get("男", {}))
	return appearance.duplicate(true) if appearance is Dictionary else {}


func item_world_appearance(item_id: int, gender: String) -> Dictionary:
	var entries: Dictionary = equipment_visual_catalog.get("itemsById", {})
	var entry: Variant = entries.get(str(item_id), {})
	if not entry is Dictionary:
		return {}
	var world: Variant = entry.get("worldWear", {})
	if not world is Dictionary:
		return {}
	var appearance_type := str(world.get("appearanceType", ""))
	if appearance_type.is_empty():
		for candidate: String in ["weaponAppearance", "dressAppearance", "helmetAppearance"]:
			if world.get(candidate, null) is Dictionary:
				appearance_type = candidate
				break
	var appearance: Dictionary = {}
	var by_gender: Variant = world.get("appearancesByGender", {})
	var resolved_gender := gender if gender in ["男", "女"] else "男"
	if by_gender is Dictionary:
		var gender_value: Variant = by_gender.get(resolved_gender, by_gender.get("男", {}))
		if gender_value is Dictionary:
			appearance = gender_value.duplicate(true)
	if appearance.is_empty() and not appearance_type.is_empty():
		var direct: Variant = world.get(appearance_type, {})
		if direct is Dictionary:
			appearance = direct.duplicate(true)
	return {
		"itemId": item_id,
		"itemName": str(entry.get("itemName", "")),
		"status": str(world.get("status", "")),
		"appearanceType": appearance_type,
		"appearance": appearance,
	}


func get_item_record(item_ref: Variant) -> Dictionary:
	var identity := _stable_identity(item_ref)
	var item_id := int(identity.get("item_id", -1))
	if item_id >= 0 and _catalog_by_item_id.has(item_id):
		return (_catalog_by_item_id.get(item_id, {}) as Dictionary).duplicate(true)
	var service_index := int(identity.get("service_index", -1))
	if service_index >= 0 and _catalog_by_service_index.has(service_index):
		return (_catalog_by_service_index.get(service_index, {}) as Dictionary).duplicate(true)
	var canonical_name := _canonical_item_name(str(identity.get("name", "")))
	return (_catalog_by_name.get(canonical_name, {}) as Dictionary).duplicate(true)


func get_item_shop_price(item_name: String) -> int:
	return PricingServiceScript.adjusted_database_price(get_item_price_record(item_name))


func get_item_price_record(item_ref: Variant) -> Dictionary:
	_ensure_price_index()
	var identity := _stable_identity(item_ref)
	# Stable service identity is the strongest authority for a service record;
	# item identity is next. Names are deliberately only a compatibility fallback
	# for old saves that predate stable equipment IDs.
	var service_index := int(identity.get("service_index", -1))
	if service_index >= 0 and _price_by_service_index.has(service_index):
		return (_price_by_service_index.get(service_index, {}) as Dictionary).duplicate(true)
	var item_id := int(identity.get("item_id", -1))
	if item_id >= 0 and _price_by_item_id.has(item_id):
		return (_price_by_item_id.get(item_id, {}) as Dictionary).duplicate(true)
	var canonical_name := _canonical_item_name(str(identity.get("name", "")))
	# A late resource patch test (and a device hot patch) may remove only the
	# name index while retaining the stable identity index. Recover that record
	# without depending on the display text being re-registered.
	var name_item_id := _item_id_for_name(canonical_name)
	if name_item_id >= 0 and _price_by_item_id.has(name_item_id):
		return (_price_by_item_id.get(name_item_id, {}) as Dictionary).duplicate(true)
	return (_price_by_name.get(canonical_name, {}) as Dictionary).duplicate(true)


func _ensure_price_index() -> void:
	if _price_by_name.is_empty():
		if service_item_catalog.is_empty():
			_load_service_item_catalog()
		_build_price_index()
		return
	# Resource patches can add a pricing evidence file after the base APK's
	# catalog was constructed. Repair only the missing overlay in place; do not
	# rebuild or reload the complete gameplay database.
	if equipment_price_candidates.is_empty():
		_load_equipment_price_candidates()
	for raw: Variant in equipment_price_candidates.get("records", []):
		_register_price_record(raw)


func _canonical_item_name(item_name: String) -> String:
	var authority_aliases: Variant = item_runtime_authority.get("aliases", {})
	if authority_aliases is Dictionary and authority_aliases.has(item_name):
		return str(authority_aliases.get(item_name))
	return str(ITEM_ALIASES.get(item_name, item_name))


func _stable_identity(item_ref: Variant) -> Dictionary:
	var result := {"item_id": -1, "service_index": -1, "name": ""}
	if item_ref is Dictionary:
		var record: Dictionary = item_ref
		result["item_id"] = _stable_item_id(record)
		result["service_index"] = _service_index(record)
		result["name"] = str(record.get("name", record.get("item_name", record.get("itemName", ""))))
		if int(result["item_id"]) < 0 and int(result["service_index"]) < 0:
			var item_key := str(record.get("item_key", record.get("itemKey", "")))
			if item_key.begins_with("service:"):
				result["service_index"] = _parse_stable_number(item_key.trim_prefix("service:"))
			elif item_key.begins_with("item:"):
				result["item_id"] = _parse_stable_number(item_key.trim_prefix("item:"))
		return result
	if item_ref is int or item_ref is float:
		result["item_id"] = _parse_stable_number(item_ref)
		return result
	var text := str(item_ref)
	if text.begins_with("service:"):
		result["service_index"] = _parse_stable_number(text.trim_prefix("service:"))
	elif text.begins_with("item:"):
		result["item_id"] = _parse_stable_number(text.trim_prefix("item:"))
	elif text.is_valid_int():
		result["item_id"] = _parse_stable_number(text)
	else:
		result["name"] = text
	return result


func _stable_item_id(record: Dictionary) -> int:
	for key: String in ["item_id", "itemId", "stableItemId", "id"]:
		if not record.has(key):
			continue
		var value := _parse_stable_number(record.get(key, -1))
		if value >= 0:
			return value
	return -1


func _service_index(record: Dictionary) -> int:
	for key: String in ["service_index", "serviceIndex"]:
		if not record.has(key):
			continue
		var value := _parse_stable_number(record.get(key, -1))
		if value >= 0:
			return value
	return -1


func _parse_stable_number(value: Variant) -> int:
	if value is String:
		var text := value as String
		if not text.is_valid_int():
			return -1
	return maxi(-1, int(value))


func _item_id_for_name(item_name: String) -> int:
	var canonical_name := _canonical_item_name(item_name)
	var matches: Array[int] = []
	for raw_item: Variant in items:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		if _canonical_item_name(str(item.get("name", ""))) != canonical_name:
			continue
		var item_id := _stable_item_id(item)
		if item_id >= 0 and item_id not in matches:
			matches.append(item_id)
	# A candidate without an explicit stable ID is safe only when the runtime
	# table has one exact name-to-ID mapping. Refuse ambiguous same-name records
	# instead of pricing the wrong equipment.
	return matches[0] if matches.size() == 1 else -1


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
	# Retained for numeric-ID callers while the old merged drop table is retired.
	# The canonical per-monster profile is the only returned authority.
	return get_calibrated_drops(boss_id)


func get_calibrated_drops(monster_id: int, _retired_name := "") -> Array:
	var profile := get_canonical_monster_drop_profile(monster_id)
	var entries: Variant = profile.get("entries", [])
	return entries.duplicate(true) if entries is Array else []


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
