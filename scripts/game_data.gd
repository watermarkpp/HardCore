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
const DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_global_drop_rate_authority_v1.json"
)
const DPV2_DIRECT_BASELINE_MANIFEST_PATH := (
	"res://assets/data/drop/dpv2_direct_baseline_manifest_v2.json"
)
const DPV2_DIRECT_BASELINE_PATH := (
	"res://assets/data/drop/dpv2_direct_baseline_v2.json"
)
const DPV2_SINGLE_PLAYER_DROP_BOOST_PATH := (
	"res://assets/data/drop/dpv2_single_player_drop_boost_v1.json"
)
const DPV2_SINGLE_PLAYER_EFFECTIVE_PROBABILITY_PATH := (
	"res://assets/data/drop/dpv2_single_player_effective_probability_v1.json"
)
const DPV2_DIRECT_ITEM_MAPPING_PATH := (
	"res://assets/data/drop/dpv2_21cq_item_mapping_v1.json"
)
const DPV2_MONSTER_DROP_SEMANTIC_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_monster_drop_semantic_authority_v1.json"
)

# These are the user-frozen semantic decisions.  The formal semantic
# authority remains the data source, while these exact IDs/counts prevent a
# stale or substituted authority from silently changing the production set.
const DPV2_DIRECT_FROZEN_SOURCE_COUNTS := {
	79: 59, 81: 60, 83: 59, 85: 59, 87: 59,
	226: 1, 227: 36, 228: 51, 229: 36, 230: 64,
	231: 57, 232: 95, 233: 96, 234: 82,
}
const DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS := {
	59: 0, 78: 0, 145: 74, 146: 78, 147: 71,
	161: 0, 186: 0, 187: 0, 194: 0,
}
const DPV2_RUNTIME_DISABLED_IDS := {33: true, 183: true, 241: true}
const DPV2_PROJECT_EXTENSION_ID := 225
const DPV2_SPB_BASE_SHA := "98ea003b66915622b5c265602e54386f9213016c"
const DPV2_SPB_SOURCE_SHA256 := (
	"59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013"
)
const DPV2_SPB_DIRECT_BASELINE_SHA256 := (
	"9E9225DF113BDC94ECDA071388DC5FCFA92ED34BF8028519B06F205E06FF4DD0"
)
const DPV2_SPB_PROVENANCE_SHA256 := (
	"F48A033D5A33D80B795A838BE837AE84FA93469B6055FE012309ACC07082E347"
)
const DPV2_SPB_LEDGER_SHA256 := (
	"057F3664C2CE5376B2A937CB317E978769860AA1B3390D0EF038B512CD496B80"
)
const DPV2_EXPLICIT_NON_LOOT_REASON_CODES := {
	59: "INTERNAL_VERSION_DIFFERENCE_NO_SOURCE",
	78: "INTERNAL_VERSION_DIFFERENCE_NO_SOURCE",
	145: "SUMMON_OR_EVENT_COMBAT_ENTITY",
	146: "SUMMON_OR_EVENT_COMBAT_ENTITY",
	147: "SUMMON_OR_EVENT_COMBAT_ENTITY",
	161: "INTERNAL_VERSION_DIFFERENCE_NO_SOURCE",
	186: "TAMEABLE_CURRENT_EXEMPTION",
	187: "TAMEABLE_CURRENT_EXEMPTION",
	194: "GUARD_SCRIPT_CURRENT_EXEMPTION",
}

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
var dpv2_global_drop_rate_authority: Dictionary = {}
var dpv2_direct_baseline_manifest: Dictionary = {}
var dpv2_direct_baseline: Dictionary = {}
var dpv2_monster_drop_semantic_authority: Dictionary = {}
var dpv2_direct_baseline_loaded := false
var dpv2_single_player_drop_boost: Dictionary = {}
var dpv2_single_player_effective_probability: Dictionary = {}
var dpv2_single_player_drop_boost_loaded := false
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
var _dpv2_global_scale_by_preset: Dictionary = {}
var _dpv2_direct_profile_by_id: Dictionary = {}
var _dpv2_direct_slot_by_uid: Dictionary = {}
var _dpv2_spb_effective_by_uid: Dictionary = {}
var _dpv2_semantic_by_id: Dictionary = {}
var _dpv2_direct_item_by_id: Dictionary = {}
var _dpv2_direct_item_by_source_label: Dictionary = {}
var _dpv2_direct_item_by_name: Dictionary = {}

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
	# The direct V2 bundle is the sole Production drop authority. Load it
	# before building the canonical catalog closure so audit-only catalog rows
	# can resolve through the explicit item identity mapping without consulting
	# retired probability authorities.
	if not _load_dpv2_direct_baseline():
		return false
	if not _load_dpv2_single_player_drop_boost():
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


func _load_dpv2_direct_baseline() -> bool:
	dpv2_direct_baseline_manifest = {}
	dpv2_direct_baseline = {}
	dpv2_global_drop_rate_authority = {}
	dpv2_monster_drop_semantic_authority = {}
	dpv2_direct_baseline_loaded = false
	_dpv2_direct_profile_by_id.clear()
	_dpv2_direct_slot_by_uid.clear()
	_dpv2_semantic_by_id.clear()
	_dpv2_direct_item_by_id.clear()
	_dpv2_direct_item_by_source_label.clear()
	_dpv2_direct_item_by_name.clear()

	for path: String in [
		DPV2_DIRECT_BASELINE_MANIFEST_PATH,
		DPV2_DIRECT_BASELINE_PATH,
		DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH,
		DPV2_DIRECT_ITEM_MAPPING_PATH,
		DPV2_MONSTER_DROP_SEMANTIC_AUTHORITY_PATH,
	]:
		if not FileAccess.file_exists(path):
			load_error = "dpv2_direct_authority_missing:%s" % path
			return false

	var manifest_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_DIRECT_BASELINE_MANIFEST_PATH)
	)
	var baseline_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_DIRECT_BASELINE_PATH)
	)
	var global_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH)
	)
	var item_mapping_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_DIRECT_ITEM_MAPPING_PATH)
	)
	var semantic_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_MONSTER_DROP_SEMANTIC_AUTHORITY_PATH)
	)
	if (
		not manifest_value is Dictionary
		or not baseline_value is Dictionary
		or not global_value is Dictionary
		or not item_mapping_value is Dictionary
		or not semantic_value is Dictionary
	):
		load_error = "dpv2_direct_authority_invalid_json"
		return false

	var manifest: Dictionary = manifest_value
	var baseline: Dictionary = baseline_value
	var global_authority: Dictionary = global_value
	var item_mapping: Dictionary = item_mapping_value
	var semantic_authority: Dictionary = semantic_value
	if (
		str(manifest.get("schema", ""))
			!= "hardcore.dpv2.direct_baseline_manifest.v2"
		or str(manifest.get("manifest_id", ""))
			!= "dpv2.direct_baseline.manifest.v2"
		or str(manifest.get("status", ""))
			!= "REPRODUCIBLE_PRODUCTION_BUILD_PASS"
		or not bool(manifest.get("production_active", false))
	):
		load_error = "dpv2_direct_manifest_contract_invalid"
		return false
	if (
		str(baseline.get("schema", ""))
			!= "hardcore.dpv2.direct_monster_drop_baseline.v2"
		or str(baseline.get("authority_id", ""))
			!= "dpv2.direct_baseline.v2"
		or str(baseline.get("status", ""))
			!= "PRODUCTION_ACTIVE_DIRECT_BASELINE"
		or not bool(baseline.get("production_active", false))
		or str(baseline.get("production_runtime", ""))
			!= "V2_DIRECT_BASELINE"
	):
		load_error = "dpv2_direct_baseline_contract_invalid"
		return false
	if str(item_mapping.get("schema", "")) != "hardcore.dpv2.21cq_item_mapping.v1":
		load_error = "dpv2_direct_item_mapping_contract_invalid"
		return false
	if str(global_authority.get("schema", "")) != "hardcore.dpv2.global_drop_rate_authority.v1":
		load_error = "dpv2_direct_global_authority_contract_invalid"
		return false
	if not _validate_dpv2_semantic_authority(semantic_authority):
		return false

	var artifacts_value: Variant = manifest.get("artifacts", null)
	if not artifacts_value is Dictionary:
		load_error = "dpv2_direct_manifest_artifacts_missing"
		return false
	var artifacts: Dictionary = artifacts_value
	var required_artifacts := {
		"direct_baseline_authority": DPV2_DIRECT_BASELINE_PATH,
		"global_drop_rate_authority": DPV2_GLOBAL_DROP_RATE_AUTHORITY_PATH,
		"item_mapping": DPV2_DIRECT_ITEM_MAPPING_PATH,
		"semantic_authority": DPV2_MONSTER_DROP_SEMANTIC_AUTHORITY_PATH,
	}
	for raw_key: Variant in required_artifacts.keys():
		var key := str(raw_key)
		var descriptor_value: Variant = artifacts.get(key, null)
		if not descriptor_value is Dictionary:
			load_error = "dpv2_direct_manifest_artifact_missing:%s" % key
			return false
		var descriptor: Dictionary = descriptor_value
		var declared_path := str(descriptor.get("path", ""))
		var expected_path := str(required_artifacts[key])
		if (
			declared_path.trim_prefix("res://")
				!= expected_path.trim_prefix("res://")
			or str(descriptor.get("hash_normalization", "")) != "lf_text"
		):
			load_error = "dpv2_direct_manifest_artifact_binding_invalid:%s" % key
			return false
	# Runtime validates only the immutable Production outputs. The remaining
	# manifest entries are build provenance and must not pull retired source
	# authorities into the GameData load path.
	for raw_key: Variant in required_artifacts.keys():
		var key := str(raw_key)
		var descriptor_value: Variant = artifacts.get(key, null)
		if not descriptor_value is Dictionary:
			load_error = "dpv2_direct_manifest_artifact_invalid:%s" % key
			return false
		var descriptor: Dictionary = descriptor_value
		var relative_path := str(descriptor.get("path", ""))
		if relative_path.is_empty():
			load_error = "dpv2_direct_manifest_artifact_path_invalid:%s" % key
			return false
		var path := (
			relative_path if relative_path.begins_with("res://")
			else "res://" + relative_path
		)
		var declared_sha := str(descriptor.get("sha256", "")).to_upper()
		var actual_sha := _sha256_lf_file(path)
		if (
			declared_sha.is_empty()
			or actual_sha.is_empty()
			or declared_sha != actual_sha
		):
			load_error = "dpv2_direct_manifest_hash_mismatch:%s" % key
			return false

	var baseline_policy_value: Variant = baseline.get("probability_policy", null)
	if not baseline_policy_value is Dictionary:
		load_error = "dpv2_direct_probability_policy_missing"
		return false
	var baseline_policy: Dictionary = baseline_policy_value
	if (
		str(baseline.get("identity_key", "")) != "canonical_monster_id"
		or str(baseline_policy.get("base_authority", ""))
			!= "per_slot_base_numerator_over_base_denominator"
		or str(baseline_policy.get("effective_probability", ""))
			!= "min(1, base_numerator * scale_num / (base_denominator * scale_den))"
		or not bool(baseline_policy.get(
			"global_drop_rate_scale_is_only_multiplier", false
		))
		or not bool(baseline_policy.get("all_slots_rng_before_overflow", false))
		or _dpv2_json_integer(
			baseline_policy.get("post_rng_ground_slot_limit", null)
		) != 9
	):
		load_error = "dpv2_direct_probability_policy_invalid"
		return false
	var direct_global_contract: Dictionary = global_authority
	var global_meta_value: Variant = direct_global_contract.get("authority", null)
	var global_probability_value: Variant = direct_global_contract.get(
		"probability_contract",
		null,
	)
	var global_activation_value: Variant = direct_global_contract.get(
		"activation",
		null,
	)
	if (
		not global_meta_value is Dictionary
		or not global_probability_value is Dictionary
		or not global_activation_value is Dictionary
	):
		load_error = "dpv2_direct_global_authority_contract_invalid"
		return false
	var global_meta: Dictionary = global_meta_value
	var global_probability: Dictionary = global_probability_value
	var global_activation: Dictionary = global_activation_value
	if (
		str(direct_global_contract.get("schema", ""))
			!= "hardcore.dpv2.global_drop_rate_authority.v1"
		or str(direct_global_contract.get("authority_id", ""))
			!= "dpv2.global_drop_rate_scale.v1"
		or str(direct_global_contract.get("status", ""))
			!= "PRODUCTION_ACTIVE_DIRECT_BASELINE"
		or str(global_meta.get("kind", ""))
			!= "single_global_probability_control"
		or str(global_meta.get("control_key", ""))
			!= "global_drop_rate_scale"
		or not bool(global_meta.get("source_slot_mutation_forbidden", false))
		or not bool(global_meta.get("per_monster_multiplier_forbidden", false))
		or not bool(global_meta.get("per_item_multiplier_forbidden", false))
		or str(global_probability.get("formula", ""))
			!= "min(1, base_numerator * scale_num / (base_denominator * scale_den))"
		or str(global_probability.get("arithmetic", ""))
			!= "exact_positive_rational"
		or str(global_probability.get("base_probability_source", ""))
			!= "dpv2_direct_baseline_v2"
		or str(global_probability.get("base_probability_numerator_field", ""))
			!= "base_numerator"
		or str(global_probability.get("base_probability_denominator_field", ""))
			!= "base_denominator"
		or str(global_probability.get("global_scale_numerator_field", ""))
			!= "numerator"
		or str(global_probability.get("global_scale_denominator_field", ""))
			!= "denominator"
		or not bool(global_probability.get(
			"all_resolved_source_slots_rng_before_overflow", false
		))
		or not bool(global_activation.get("production_active", false))
		or str(global_activation.get("selected_authority", ""))
			!= "dpv2_direct_baseline_v2"
		or not bool(global_activation.get("fallback_forbidden", false))
	):
		load_error = "dpv2_direct_global_authority_contract_invalid"
		return false
	var direct_presets: Variant = direct_global_contract.get("presets", [])
	if not direct_presets is Array or direct_presets.size() != 5:
		load_error = "dpv2_direct_global_authority_count_invalid"
		return false
	var expected_global_presets := {
		"0.5x": Vector2i(1, 2),
		"0.8x": Vector2i(4, 5),
		"1x": Vector2i(1, 1),
		"1.5x": Vector2i(3, 2),
		"2x": Vector2i(2, 1),
	}
	var seen_global_presets: Dictionary = {}
	for raw_direct_preset: Variant in direct_presets:
		if not raw_direct_preset is Dictionary:
			load_error = "dpv2_direct_global_authority_preset_invalid"
			return false
		var direct_preset: Dictionary = raw_direct_preset
		var preset_name := str(direct_preset.get("preset", ""))
		var preset_ratio := Vector2i(
			_dpv2_json_integer(direct_preset.get("numerator", null)),
			_dpv2_json_integer(direct_preset.get("denominator", null)),
		)
		if (
			not expected_global_presets.has(preset_name)
			or seen_global_presets.has(preset_name)
			or preset_ratio != expected_global_presets[preset_name]
		):
			load_error = "dpv2_direct_global_authority_ratio_invalid"
			return false
		seen_global_presets[preset_name] = true
	if seen_global_presets.size() != expected_global_presets.size():
		load_error = "dpv2_direct_global_authority_count_invalid"
		return false
	if not expected_global_presets.has(str(direct_global_contract.get("active_preset", ""))):
		load_error = "dpv2_direct_global_authority_active_preset_invalid"
		return false

	var summary_value: Variant = baseline.get("summary", null)
	if not summary_value is Dictionary:
		load_error = "dpv2_direct_baseline_summary_missing"
		return false
	var summary: Dictionary = summary_value
	if (
		_dpv2_json_integer(summary.get("active_monsters", null)) != 156
		or _dpv2_json_integer(summary.get("runtime_allowed_monsters", null)) != 153
		or _dpv2_json_integer(summary.get("drop_enabled_monsters", null)) != 144
		or _dpv2_json_integer(summary.get("explicit_non_loot_monsters", null)) != 9
		or _dpv2_json_integer(summary.get("runtime_disabled_monsters", null)) != 3
		or _dpv2_json_integer(summary.get("non_loot_monsters", null)) != 9
		or _dpv2_json_integer(summary.get("compiled_slots", null)) != 6809
	):
		load_error = "dpv2_direct_baseline_summary_count_invalid"
		return false
	var origin_counts_value: Variant = summary.get("baseline_origin_counts", null)
	if not origin_counts_value is Dictionary:
		load_error = "dpv2_direct_baseline_origin_counts_invalid"
		return false
	var origin_counts: Dictionary = origin_counts_value
	if (
		_dpv2_json_integer(origin_counts.get("LEGACY_21CQ_MONITEMS", null)) != 6740
		or _dpv2_json_integer(origin_counts.get("PROJECT_EXTENSION", null)) != 69
	):
		load_error = "dpv2_direct_baseline_origin_counts_invalid"
		return false

	var item_records_value: Variant = item_mapping.get("records", null)
	if not item_records_value is Array or item_records_value.size() != 244:
		load_error = "dpv2_direct_item_mapping_count_invalid"
		return false
	var identity_ids: Dictionary = {}
	var identity_by_source_label: Dictionary = {}
	var identity_by_name: Dictionary = {}
	for raw_item: Variant in item_records_value:
		if not raw_item is Dictionary:
			load_error = "dpv2_direct_item_mapping_record_invalid"
			return false
		var item_record: Dictionary = raw_item
		var reward_kind := str(item_record.get("reward_kind", ""))
		var mapping_status := str(item_record.get("mapping_status", ""))
		if reward_kind == "retired_source_only":
			if (
				mapping_status != "RETIRED_SOURCE_ONLY_NOT_IN_CANONICAL_CATALOG"
				or item_record.get("canonical_item_id", null) != null
				or item_record.get("canonical_item_name", null) != null
			):
				load_error = "dpv2_direct_retired_item_mapping_invalid"
				return false
			continue
		if reward_kind == "gold":
			if (
				mapping_status.is_empty()
				or item_record.get("canonical_item_id", null) != null
				or item_record.get("canonical_item_name", null) != null
			):
				load_error = "dpv2_direct_gold_mapping_invalid"
				return false
			continue
		if reward_kind != "item" or mapping_status not in ["EXACT", "EXPLICIT_ALIAS"]:
			load_error = "dpv2_direct_item_mapping_kind_invalid"
			return false
		var item_id_value: Variant = item_record.get("canonical_item_id", null)
		var item_name := str(item_record.get("canonical_item_name", ""))
		if _dpv2_json_integer(item_id_value) <= 0 or item_name.is_empty():
			load_error = "dpv2_direct_item_mapping_identity_invalid"
			return false
		var item_id := _dpv2_json_integer(item_id_value)
		if identity_ids.has(item_id):
			var existing_identity: Dictionary = identity_ids[item_id]
			if str(existing_identity.get("canonical_item_name", "")) != item_name:
				load_error = "dpv2_direct_item_mapping_identity_conflict"
				return false
		else:
			identity_ids[item_id] = item_record.duplicate(true)
		var source_label := str(item_record.get("source_item_label", ""))
		var normalized_name := _canonical_item_name(item_name)
		var existing_source: Variant = identity_by_source_label.get(
			source_label,
			null,
		)
		if (
			source_label.is_empty()
			or existing_source != null
			and (
				str((existing_source as Dictionary).get("canonical_item_name", ""))
					!= item_name
				or _dpv2_json_integer(
					(existing_source as Dictionary).get("canonical_item_id", null)
				) != item_id
			)
		):
			load_error = "dpv2_direct_item_mapping_source_label_conflict"
			return false
		identity_by_source_label[source_label] = item_record.duplicate(true)
		var existing_name: Variant = identity_by_name.get(normalized_name, null)
		if (
			existing_name != null
			and (
				str((existing_name as Dictionary).get("canonical_item_name", ""))
					!= item_name
				or _dpv2_json_integer(
					(existing_name as Dictionary).get("canonical_item_id", null)
				) != item_id
			)
		):
			load_error = "dpv2_direct_item_mapping_name_conflict"
			return false
		identity_by_name[normalized_name] = item_record.duplicate(true)
	if identity_ids.size() != 233:
		load_error = "dpv2_direct_item_mapping_identity_count_invalid"
		return false

	var profiles_value: Variant = baseline.get("profiles", null)
	if not profiles_value is Array or profiles_value.size() != 156:
		load_error = "dpv2_direct_profile_count_invalid"
		return false
	var profile_ids: Dictionary = {}
	var slot_uids: Dictionary = {}
	var provenance_ids: Dictionary = {}
	var enabled_profile_count := 0
	var runtime_allowed_profile_count := 0
	var explicit_non_loot_profile_count := 0
	var runtime_disabled_profile_count := 0
	var compiled_slot_count := 0
	var origin_totals: Dictionary = {}
	for raw_profile: Variant in profiles_value:
		if not raw_profile is Dictionary:
			load_error = "dpv2_direct_profile_invalid"
			return false
		var profile: Dictionary = raw_profile
		var monster_id_value: Variant = profile.get("canonical_monster_id", null)
		var monster_id := _dpv2_json_integer(monster_id_value)
		var canonical_entry: Variant = _monsters_by_id.get(monster_id, null)
		if (
			monster_id <= 0
			or not canonical_entry is Dictionary
			or profile_ids.has(monster_id)
		):
			load_error = "dpv2_direct_profile_identity_invalid"
			return false
		var canonical_name := str((canonical_entry as Dictionary).get("canonical_name", ""))
		if str(profile.get("canonical_monster_name", "")) != canonical_name:
			load_error = "dpv2_direct_profile_name_invalid"
			return false
		var slots_value: Variant = profile.get("slots", null)
		if not slots_value is Array:
			load_error = "dpv2_direct_profile_slots_invalid"
			return false
		var profile_semantic_value: Variant = _dpv2_semantic_by_id.get(monster_id, null)
		if not profile_semantic_value is Dictionary:
			load_error = "dpv2_direct_profile_semantic_missing"
			return false
		var semantic_record: Dictionary = profile_semantic_value
		var semantic_status := str(semantic_record.get("drop_semantic_state", ""))
		var profile_runtime_allowed_value: Variant = profile.get("runtime_allowed", null)
		if not profile_runtime_allowed_value is bool:
			load_error = "dpv2_direct_profile_runtime_allowed_invalid"
			return false
		var profile_runtime_allowed := bool(profile_runtime_allowed_value)
		if (
			profile_runtime_allowed
			!= bool(semantic_record.get("runtime_allowed", false))
			or str(profile.get("semantic_status", "")) != semantic_status
		):
			load_error = "dpv2_direct_profile_semantic_mismatch"
			return false
		if profile_runtime_allowed:
			runtime_allowed_profile_count += 1
		if semantic_status == "EXPLICIT_NON_LOOT":
			explicit_non_loot_profile_count += 1
		elif semantic_status == "RUNTIME_DISABLED":
			runtime_disabled_profile_count += 1
		var drop_enabled := bool(profile.get("drop_enabled", false))
		var expected_drop_enabled := semantic_status in ["DIRECT_21CQ", "PROJECT_EXTENSION"]
		if drop_enabled != expected_drop_enabled:
			load_error = "dpv2_direct_profile_drop_state_mismatch"
			return false
		if drop_enabled:
			enabled_profile_count += 1
			if str(profile.get("drop_profile_id", "")).is_empty():
				load_error = "dpv2_direct_enabled_profile_id_invalid"
				return false
		else:
			if (
				profile.get("drop_profile_id", null) != null
				or str(profile.get("reporting_label", "")) != "NON_LOOT"
				or not slots_value.is_empty()
			):
				load_error = "dpv2_direct_non_loot_profile_invalid"
				return false
		profile_ids[monster_id] = true
		var profile_id := str(profile.get("drop_profile_id", ""))
		for raw_slot: Variant in slots_value:
			if not raw_slot is Dictionary:
				load_error = "dpv2_direct_slot_invalid"
				return false
			var slot: Dictionary = raw_slot
			var slot_uid := str(slot.get("slot_uid", ""))
			var provenance_id := str(slot.get("source_provenance_id", ""))
			var base_numerator: Variant = slot.get("base_numerator", null)
			var base_denominator: Variant = slot.get("base_denominator", null)
			var priority: Variant = slot.get("overflow_priority", null)
			var reward_key_count := int(slot.has("canonical_item_id")) + int(slot.has("gold_amount"))
			if (
				slot_uid.is_empty()
				or provenance_id.is_empty()
				or slot_uids.has(slot_uid)
				or provenance_ids.has(provenance_id)
				or _dpv2_json_integer(base_numerator) <= 0
				or _dpv2_json_integer(base_denominator) <= 0
				or _dpv2_json_integer(priority) < 0
				or not slot.get("protected_drop", null) is bool
				or reward_key_count != 1
			):
				load_error = "dpv2_direct_slot_contract_invalid"
				return false
			var allowed_slot_keys := {
				"slot_uid": true,
				"base_numerator": true,
				"base_denominator": true,
				"overflow_priority": true,
				"protected_drop": true,
				"baseline_origin": true,
				"source_provenance_id": true,
				"canonical_item_id": true,
				"gold_amount": true,
			}
			for raw_key: Variant in slot.keys():
				if not allowed_slot_keys.has(str(raw_key)):
					load_error = "dpv2_direct_slot_schema_field_invalid"
					return false
			if slot.has("canonical_item_id"):
				var item_id_value: Variant = slot.get("canonical_item_id", null)
				var item_id := _dpv2_json_integer(item_id_value)
				if item_id <= 0 or not identity_ids.has(item_id):
					load_error = "dpv2_direct_slot_item_identity_unresolved"
					return false
			else:
				var gold_amount: Variant = slot.get("gold_amount", null)
				if _dpv2_json_integer(gold_amount) <= 0:
					load_error = "dpv2_direct_slot_gold_invalid"
					return false
			var origin := str(slot.get("baseline_origin", ""))
			if origin not in ["LEGACY_21CQ_MONITEMS", "PROJECT_EXTENSION"]:
				load_error = "dpv2_direct_slot_origin_invalid"
				return false
			slot_uids[slot_uid] = true
			provenance_ids[provenance_id] = true
			origin_totals[origin] = int(origin_totals.get(origin, 0)) + 1
			_dpv2_direct_slot_by_uid[slot_uid] = {
				"canonical_monster_id": monster_id,
				"drop_profile_id": profile_id,
				"slot": slot.duplicate(true),
			}
			compiled_slot_count += 1
		_dpv2_direct_profile_by_id[monster_id] = profile.duplicate(true)
	if (
		profile_ids.size() != 156
		or runtime_allowed_profile_count != 153
		or enabled_profile_count != 144
		or explicit_non_loot_profile_count != 9
		or runtime_disabled_profile_count != 3
		or compiled_slot_count != 6809
		or origin_totals != {"LEGACY_21CQ_MONITEMS": 6740, "PROJECT_EXTENSION": 69}
	):
		load_error = "dpv2_direct_profile_closure_invalid"
		return false
	for raw_id: Variant in _monsters_by_id.keys():
		if not profile_ids.has(int(raw_id)):
			load_error = "dpv2_direct_profile_missing_monster"
			return false

	dpv2_direct_baseline_manifest = manifest
	dpv2_direct_baseline = baseline
	dpv2_global_drop_rate_authority = global_authority
	dpv2_monster_drop_semantic_authority = semantic_authority
	_dpv2_direct_item_by_id = identity_ids
	_dpv2_direct_item_by_source_label = identity_by_source_label
	_dpv2_direct_item_by_name = identity_by_name
	_dpv2_global_scale_by_preset.clear()
	for raw_preset: Variant in global_authority.get("presets", []):
		if raw_preset is Dictionary:
			var preset: Dictionary = raw_preset
			var preset_name := str(preset.get("preset", ""))
			var numerator := _dpv2_json_integer(preset.get("numerator", null))
			var denominator := _dpv2_json_integer(preset.get("denominator", null))
			if not preset_name.is_empty() and numerator > 0 and denominator > 0:
				_dpv2_global_scale_by_preset[preset_name] = Vector2i(
					numerator,
					denominator,
				)
	dpv2_direct_baseline_loaded = true
	return true


func _load_dpv2_single_player_drop_boost() -> bool:
	dpv2_single_player_drop_boost = {}
	dpv2_single_player_effective_probability = {}
	dpv2_single_player_drop_boost_loaded = false
	_dpv2_spb_effective_by_uid.clear()
	for path: String in [
		DPV2_SINGLE_PLAYER_DROP_BOOST_PATH,
		DPV2_SINGLE_PLAYER_EFFECTIVE_PROBABILITY_PATH,
	]:
		if not FileAccess.file_exists(path):
			load_error = "spb_effective_probability_authority_missing:%s" % path
			return false
	var authority_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_SINGLE_PLAYER_DROP_BOOST_PATH)
	)
	var effective_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_SINGLE_PLAYER_EFFECTIVE_PROBABILITY_PATH)
	)
	if not authority_value is Dictionary or not effective_value is Dictionary:
		load_error = "spb_effective_probability_authority_invalid_json"
		return false
	var authority: Dictionary = authority_value
	var effective: Dictionary = effective_value
	if (
		str(authority.get("schema", ""))
			!= "hardcore.dpv2.single_player_drop_boost.v1"
		or str(authority.get("authority_id", ""))
			!= "dpv2.single_player_drop_boost.v1"
		or str(authority.get("status", "")) != "PRODUCTION_ENABLED"
	):
		load_error = "spb_boost_authority_contract_invalid"
		return false
	if (
		str(effective.get("schema", ""))
			!= "hardcore.dpv2.single_player_effective_probability.v1"
		or str(effective.get("authority_id", ""))
			!= "dpv2.single_player_effective_probability.v1"
		or str(effective.get("status", "")) != "PRODUCTION_EFFECTIVE_LEDGER"
		or str(effective.get("source_authority", ""))
			!= "dpv2.single_player_drop_boost.v1"
		or str(effective.get("source_direct_baseline", ""))
			!= "dpv2.direct_baseline.v2"
	):
		load_error = "spb_effective_probability_contract_invalid"
		return false
	var production_value: Variant = authority.get("production", null)
	if not production_value is Dictionary:
		load_error = "spb_production_contract_missing"
		return false
	var production: Dictionary = production_value
	var enabled_value: Variant = production.get("enabled", null)
	var multiplier_value: Variant = production.get("boost_multiplier", null)
	var ceiling_value: Variant = production.get("auto_boost_ceiling", null)
	var gold_multiplier_value: Variant = production.get("gold_amount_multiplier", null)
	var global_value: Variant = production.get(
		"required_global_drop_rate_multiplier", null
	)
	if (
		not enabled_value is bool
		or not multiplier_value is Dictionary
		or not ceiling_value is Dictionary
		or not gold_multiplier_value is Dictionary
		or not global_value is Dictionary
		or _dpv2_json_integer(multiplier_value.get("numerator", null)) != 25
		or _dpv2_json_integer(multiplier_value.get("denominator", null)) != 1
		or _dpv2_json_integer(ceiling_value.get("numerator", null)) != 1
		or _dpv2_json_integer(ceiling_value.get("denominator", null)) != 20
		or _dpv2_json_integer(gold_multiplier_value.get("numerator", null)) != 10
		or _dpv2_json_integer(gold_multiplier_value.get("denominator", null)) != 1
		or str(production.get("required_global_drop_rate_preset", "")) != "1x"
		or _dpv2_json_integer(global_value.get("numerator", null)) != 1
		or _dpv2_json_integer(global_value.get("denominator", null)) != 1
		or str(production.get("disabled_mode", ""))
			!= "SELECT_BASE_NUMERATOR_AND_DENOMINATOR"
	):
		load_error = "spb_production_contract_invalid"
		return false
	for document: Dictionary in [authority, effective]:
		var bindings_value: Variant = document.get("source_bindings", null)
		if not bindings_value is Dictionary:
			load_error = "spb_source_bindings_missing"
			return false
		var bindings: Dictionary = bindings_value
		if (
			str(bindings.get("base_sha", "")) != DPV2_SPB_BASE_SHA
			or str(bindings.get("source_sha256_raw", "")).to_upper()
				!= DPV2_SPB_SOURCE_SHA256
			or str(bindings.get("direct_baseline_sha256_raw", "")).to_upper()
				!= DPV2_SPB_DIRECT_BASELINE_SHA256
			or str(bindings.get("source_provenance_sha256_raw", "")).to_upper()
				!= DPV2_SPB_PROVENANCE_SHA256
			or str(bindings.get("direct_slot_ledger_sha256", "")).to_upper()
				!= DPV2_SPB_LEDGER_SHA256
			or _dpv2_json_integer(bindings.get("direct_slot_count", null)) != 6809
			or _dpv2_json_integer(bindings.get("source_drift", null)) != 0
			or _dpv2_json_integer(bindings.get("base_probability_drift", null)) != 0
			or _dpv2_json_integer(bindings.get("slot_uid_drift", null)) != 0
			or _dpv2_json_integer(bindings.get("reward_identity_drift", null)) != 0
			or _dpv2_json_integer(bindings.get("provenance_drift", null)) != 0
			or _dpv2_json_integer(
				bindings.get("protected_priority_origin_drift", null)
			) != 0
			or _dpv2_json_integer(bindings.get("duplicate_slot_collapse", null)) != 0
		):
			load_error = "spb_source_bindings_invalid"
			return false
	var authority_summary_value: Variant = authority.get("summary", null)
	var effective_summary_value: Variant = effective.get("summary", null)
	if (
		not authority_summary_value is Dictionary
		or not effective_summary_value is Dictionary
	):
		load_error = "spb_summary_missing"
		return false
	var authority_summary: Dictionary = authority_summary_value
	var effective_summary: Dictionary = effective_summary_value
	var expected_policy_counts := {
		"AUTO_BOOST": 4537,
		"BYPASS_COMMON_RECOVERY": 1357,
		"BYPASS_GOLD": 128,
		"BYPASS_NEW_ARMOR_BOSS": 324,
		"BYPASS_UNCLASSIFIED": 463,
	}
	var expected_population_counts := {
		"gold_slots": 134,
		"common_recovery_slots": 1597,
		"new_armor_boss_slots": 324,
		"blessing_oil_slots": 22,
		"equipment_candidate_slots": 4311,
		"rare_consumable_candidate_slots": 268,
		"unclassified_candidate_slots": 499,
	}
	for summary: Dictionary in [authority_summary, effective_summary]:
		var policy_counts_value: Variant = summary.get("effective_policy_counts", null)
		var populations_value: Variant = summary.get("overlapping_population_counts", null)
		if not policy_counts_value is Dictionary or not populations_value is Dictionary:
			load_error = "spb_summary_counts_missing"
			return false
		for key: String in expected_policy_counts:
			if _dpv2_json_integer(policy_counts_value.get(key, null)) != expected_policy_counts[key]:
				load_error = "spb_policy_count_invalid:%s" % key
				return false
		for key: String in expected_population_counts:
			if _dpv2_json_integer(populations_value.get(key, null)) != expected_population_counts[key]:
				load_error = "spb_population_count_invalid:%s" % key
		if (
			_dpv2_json_integer(summary.get("ceiling_applied_slots", null)) != 2203
			or _dpv2_json_integer(summary.get("disabled_counterfactual_mismatch", null)) != 0
			or _dpv2_json_integer(summary.get("probability_decreases", null)) != 0
			or _dpv2_json_integer(summary.get("ceiling_violations", null)) != 0
			or _dpv2_json_integer(summary.get("boost_formula_mismatch", null)) != 0
			or _dpv2_json_integer(summary.get("bypass_probability_mismatch", null)) != 0
			or _dpv2_json_integer(summary.get("duplicate_slot_collapse", null)) != 0
			or _dpv2_json_integer(summary.get("gold_amount_slots", null)) != 134
			or _dpv2_json_integer(summary.get("gold_amount_mismatch", null)) != 0
			or _dpv2_json_integer(
				summary.get("disabled_gold_amount_mismatch", null)
			) != 0
		):
			load_error = "spb_summary_invariant_invalid"
			return false
		var summary_gold_multiplier: Variant = summary.get("gold_amount_multiplier", null)
		if (
			not summary_gold_multiplier is Dictionary
			or _dpv2_json_integer(summary_gold_multiplier.get("numerator", null)) != 10
			or _dpv2_json_integer(summary_gold_multiplier.get("denominator", null)) != 1
		):
			load_error = "spb_gold_amount_summary_invalid"
			return false
	if (
		_dpv2_json_integer(authority_summary.get("production_slots", null)) != 6809
		or _dpv2_json_integer(authority_summary.get("equipment_item_ids", null)) != 167
		or _dpv2_json_integer(
			authority_summary.get("rare_functional_consumable_item_ids", null)
		) != 13
		or _dpv2_json_integer(authority_summary.get("auto_boost_item_ids", null)) != 180
		or _dpv2_json_integer(effective_summary.get("records", null)) != 6809
		or _dpv2_json_integer(
			effective_summary.get("disabled_counterfactual_records", null)
		) != 6809
		or _dpv2_json_integer(effective_summary.get("base_mirror_mismatch", null)) != 0
	):
		load_error = "spb_summary_cardinality_invalid"
		return false
	var records_value: Variant = effective.get("records", null)
	if not records_value is Array or records_value.size() != 6809:
		load_error = "spb_effective_probability_cardinality_invalid"
		return false
	var allowed_policies := {
		"AUTO_BOOST": true,
		"BYPASS_COMMON_RECOVERY": true,
		"BYPASS_GOLD": true,
		"BYPASS_NEW_ARMOR_BOSS": true,
		"BYPASS_UNCLASSIFIED": true,
	}
	var policy_counts: Dictionary = {}
	var ceiling_count := 0
	for raw_record: Variant in records_value:
		if not raw_record is Dictionary:
			load_error = "spb_effective_probability_record_invalid"
			return false
		var record: Dictionary = raw_record
		var slot_uid := str(record.get("slot_uid", ""))
		var indexed_value: Variant = _dpv2_direct_slot_by_uid.get(slot_uid, null)
		if slot_uid.is_empty() or _dpv2_spb_effective_by_uid.has(slot_uid):
			load_error = "spb_effective_probability_slot_uid_invalid"
			return false
		if not indexed_value is Dictionary:
			load_error = "spb_effective_probability_direct_slot_missing"
			return false
		var indexed: Dictionary = indexed_value
		var direct_slot_value: Variant = indexed.get("slot", null)
		if not direct_slot_value is Dictionary:
			load_error = "spb_effective_probability_direct_slot_invalid"
			return false
		var direct_slot: Dictionary = direct_slot_value
		if _dpv2_json_integer(record.get("canonical_monster_id", null)) != int(
			indexed.get("canonical_monster_id", -1)
		):
			load_error = "spb_effective_probability_monster_mismatch"
			return false
		for field: String in [
			"base_numerator", "base_denominator", "source_provenance_id",
			"protected_drop", "overflow_priority", "baseline_origin",
			"canonical_item_id", "gold_amount",
		]:
			if record.has(field) != direct_slot.has(field):
				load_error = "spb_effective_probability_mirror_field_mismatch:%s" % field
				return false
			if record.has(field) and record.get(field) != direct_slot.get(field):
				load_error = "spb_effective_probability_mirror_value_mismatch:%s" % field
				return false
		var expected_reward_kind := "ITEM" if direct_slot.has("canonical_item_id") else "GOLD"
		if str(record.get("reward_kind", "")) != expected_reward_kind:
			load_error = "spb_effective_probability_reward_kind_mismatch"
			return false
		if expected_reward_kind == "GOLD":
			var base_gold_amount := _dpv2_json_integer(
				record.get("base_gold_amount", null)
			)
			var effective_gold_amount := _dpv2_json_integer(
				record.get("effective_gold_amount", null)
			)
			if (
				base_gold_amount != _dpv2_json_integer(direct_slot.get("gold_amount", null))
				or effective_gold_amount != base_gold_amount * 10
			):
				load_error = "spb_effective_gold_amount_mismatch"
				return false
		elif record.has("base_gold_amount") or record.has("effective_gold_amount"):
			load_error = "spb_non_gold_amount_overlay_invalid"
			return false
		var base_numerator := _dpv2_json_integer(record.get("base_numerator", null))
		var base_denominator := _dpv2_json_integer(record.get("base_denominator", null))
		var effective_numerator := _dpv2_json_integer(record.get("effective_numerator", null))
		var effective_denominator := _dpv2_json_integer(record.get("effective_denominator", null))
		var policy := str(record.get("boost_policy", ""))
		if (
			base_numerator <= 0 or base_denominator <= 0
			or effective_numerator <= 0 or effective_denominator <= 0
			or not allowed_policies.has(policy)
			or str(record.get("reason_code", "")).is_empty()
			or str(record.get("formula_reason_code", "")).is_empty()
			or not record.get("ceiling_applied", null) is bool
			or _dpv2_json_integer(
				record.get("auto_boost_ceiling_numerator", null)
			) != 1
			or _dpv2_json_integer(
				record.get("auto_boost_ceiling_denominator", null)
			) != 20
		):
			load_error = "spb_effective_probability_record_contract_invalid"
			return false
		var is_auto := policy == "AUTO_BOOST"
		if (
			_dpv2_json_integer(record.get("boost_multiplier_numerator", null))
				!= (25 if is_auto else 1)
			or _dpv2_json_integer(record.get("boost_multiplier_denominator", null)) != 1
		):
			load_error = "spb_effective_probability_multiplier_invalid"
			return false
		var expected := dpv2_single_player_boost_formula(
			base_numerator, base_denominator, is_auto
		)
		var expected_numerator := int(expected.get("numerator", 0))
		var expected_denominator := int(expected.get("denominator", 0))
		var expected_ceiling := bool(expected.get("ceiling_applied", false))
		if (
			effective_numerator != expected_numerator
			or effective_denominator != expected_denominator
			or bool(record.get("ceiling_applied", false)) != expected_ceiling
			or _positive_gcd(effective_numerator, effective_denominator) != 1
		):
			load_error = "spb_effective_probability_formula_mismatch"
			return false
		policy_counts[policy] = int(policy_counts.get(policy, 0)) + 1
		ceiling_count += int(expected_ceiling)
		_dpv2_spb_effective_by_uid[slot_uid] = record.duplicate(true)
	if (
		_dpv2_spb_effective_by_uid.size() != _dpv2_direct_slot_by_uid.size()
		or _dpv2_spb_effective_by_uid.size() != 6809
		or ceiling_count != 2203
	):
		load_error = "spb_effective_probability_closure_invalid"
		return false
	for key: String in expected_policy_counts:
		if int(policy_counts.get(key, 0)) != expected_policy_counts[key]:
			load_error = "spb_effective_probability_policy_closure_invalid:%s" % key
			return false
	dpv2_single_player_drop_boost = authority
	dpv2_single_player_effective_probability = effective
	dpv2_single_player_drop_boost_loaded = true
	return true


func _validate_dpv2_semantic_authority(authority: Dictionary) -> bool:
	if (
		str(authority.get("schema", ""))
			!= "hardcore.dpv2.monster_drop_semantic_authority.v1"
		or str(authority.get("authority_id", ""))
			!= "dpv2.monster_drop_semantic.v1"
		or str(authority.get("status", ""))
			!= "SEMANTIC_AUTHORITY_COMPLETE"
		or not bool(authority.get("production_active", false))
		or str(authority.get("identity_key", "")) != "canonical_monster_id"
	):
		load_error = "dpv2_semantic_authority_contract_invalid"
		return false
	var policy_value: Variant = authority.get("policy", null)
	if not policy_value is Dictionary:
		load_error = "dpv2_semantic_authority_policy_invalid"
		return false
	var policy: Dictionary = policy_value
	if (
		str(policy.get("runtime_eligibility", ""))
			!= "catalog_runtime_allowed_only"
		or bool(policy.get("name_fallback", true))
		or bool(policy.get("fuzzy_matching", true))
		or not bool(policy.get("source_rows_retained_when_excluded", false))
		or not bool(policy.get("excluded_rows_never_compiled", false))
	):
		load_error = "dpv2_semantic_authority_policy_invalid"
		return false

	var summary_value: Variant = authority.get("summary", null)
	if not summary_value is Dictionary:
		load_error = "dpv2_semantic_authority_summary_invalid"
		return false
	var summary: Dictionary = summary_value
	var expected_summary := {
		"canonical_monsters": 156,
		"runtime_allowed": 153,
		"drop_enabled": 144,
		"explicit_non_loot": 9,
		"runtime_disabled": 3,
		"direct_21cq": 143,
		"project_extension": 1,
		"production_slots": 6809,
	}
	for raw_key: Variant in expected_summary.keys():
		var key := str(raw_key)
		if _dpv2_json_integer(summary.get(key, null)) != int(expected_summary[key]):
			load_error = "dpv2_semantic_authority_summary_count_invalid"
			return false
	var source_accounting_value: Variant = summary.get(
		"source_accounting",
		null,
	)
	if not source_accounting_value is Dictionary:
		load_error = "dpv2_semantic_authority_source_accounting_invalid"
		return false
	var source_accounting: Dictionary = source_accounting_value
	var expected_source_accounting := {
		"LEGACY_21CQ_COMPILED": 6740,
		"PROJECT_EXTENSION_COMPILED": 69,
		"EXPLICIT_NON_LOOT_EXCLUDED": 223,
		"RETIRED_OUT_OF_RUNTIME": 2558,
	}
	for raw_key: Variant in expected_source_accounting.keys():
		var key := str(raw_key)
		if _dpv2_json_integer(source_accounting.get(key, null)) != int(expected_source_accounting[key]):
			load_error = "dpv2_semantic_authority_source_accounting_invalid"
			return false

	# Validate the frozen decision lists as data, but also assert their exact
	# user-approved IDs/counts so a stale authority cannot redefine production.
	var frozen_value: Variant = authority.get("frozen_decisions", null)
	if not frozen_value is Dictionary:
		load_error = "dpv2_semantic_authority_frozen_decisions_invalid"
		return false
	var frozen: Dictionary = frozen_value
	var direct_frozen_value: Variant = frozen.get("direct_21cq", null)
	if not direct_frozen_value is Array:
		load_error = "dpv2_semantic_authority_frozen_direct_invalid"
		return false
	var direct_frozen: Array = direct_frozen_value
	if direct_frozen.size() != DPV2_DIRECT_FROZEN_SOURCE_COUNTS.size():
		load_error = "dpv2_semantic_authority_frozen_direct_count_invalid"
		return false
	var seen_direct_frozen: Dictionary = {}
	for raw_frozen: Variant in direct_frozen:
		if not raw_frozen is Dictionary:
			load_error = "dpv2_semantic_authority_frozen_direct_record_invalid"
			return false
		var frozen_record: Dictionary = raw_frozen
		var frozen_id := _dpv2_json_integer(
			frozen_record.get("canonical_monster_id", null)
		)
		var frozen_count := _dpv2_json_integer(
			frozen_record.get("source_row_count", null)
		)
		if (
			not DPV2_DIRECT_FROZEN_SOURCE_COUNTS.has(frozen_id)
			or seen_direct_frozen.has(frozen_id)
			or frozen_count != int(DPV2_DIRECT_FROZEN_SOURCE_COUNTS[frozen_id])
		):
			load_error = "dpv2_semantic_authority_frozen_direct_mismatch"
			return false
		seen_direct_frozen[frozen_id] = true
	if seen_direct_frozen.size() != DPV2_DIRECT_FROZEN_SOURCE_COUNTS.size():
		load_error = "dpv2_semantic_authority_frozen_direct_mismatch"
		return false
	var explicit_frozen_value: Variant = frozen.get("explicit_non_loot", null)
	if not explicit_frozen_value is Array:
		load_error = "dpv2_semantic_authority_frozen_explicit_invalid"
		return false
	var explicit_frozen: Array = explicit_frozen_value
	if explicit_frozen.size() != DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS.size():
		load_error = "dpv2_semantic_authority_frozen_explicit_count_invalid"
		return false
	var seen_explicit_frozen: Dictionary = {}
	for raw_frozen: Variant in explicit_frozen:
		if not raw_frozen is Dictionary:
			load_error = "dpv2_semantic_authority_frozen_explicit_record_invalid"
			return false
		var frozen_record: Dictionary = raw_frozen
		var frozen_id := _dpv2_json_integer(
			frozen_record.get("canonical_monster_id", null)
		)
		var frozen_count := _dpv2_json_integer(
			frozen_record.get("source_row_count", null)
		)
		if (
			not DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS.has(frozen_id)
			or seen_explicit_frozen.has(frozen_id)
			or frozen_count != int(DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS[frozen_id])
			or not bool(frozen_record.get("exemption_required", false))
		):
			load_error = "dpv2_semantic_authority_frozen_explicit_mismatch"
			return false
		seen_explicit_frozen[frozen_id] = true
	if seen_explicit_frozen.size() != DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS.size():
		load_error = "dpv2_semantic_authority_frozen_explicit_mismatch"
		return false
	var disabled_frozen_value: Variant = frozen.get("runtime_disabled", null)
	if not disabled_frozen_value is Array:
		load_error = "dpv2_semantic_authority_frozen_disabled_invalid"
		return false
	var seen_disabled_frozen: Dictionary = {}
	for raw_id: Variant in disabled_frozen_value:
		var disabled_id := _dpv2_json_integer(raw_id)
		if not DPV2_RUNTIME_DISABLED_IDS.has(disabled_id) or seen_disabled_frozen.has(disabled_id):
			load_error = "dpv2_semantic_authority_frozen_disabled_mismatch"
			return false
		seen_disabled_frozen[disabled_id] = true
	if seen_disabled_frozen.size() != DPV2_RUNTIME_DISABLED_IDS.size():
		load_error = "dpv2_semantic_authority_frozen_disabled_mismatch"
		return false
	var extension_value: Variant = frozen.get("project_extension", null)
	if (
		not extension_value is Dictionary
		or _dpv2_json_integer((extension_value as Dictionary).get("canonical_monster_id", null))
			!= DPV2_PROJECT_EXTENSION_ID
		or _dpv2_json_integer((extension_value as Dictionary).get("source_row_count", null)) != 69
	):
		load_error = "dpv2_semantic_authority_frozen_extension_invalid"
		return false

	var records_value: Variant = authority.get("records", null)
	if not records_value is Array or (records_value as Array).size() != 156:
		load_error = "dpv2_semantic_authority_record_count_invalid"
		return false
	var records: Array = records_value
	var seen_ids: Dictionary = {}
	var runtime_allowed_count := 0
	var direct_count := 0
	var project_count := 0
	var explicit_count := 0
	var disabled_count := 0
	var production_slot_count := 0
	for raw_record: Variant in records:
		if not raw_record is Dictionary:
			load_error = "dpv2_semantic_authority_record_invalid"
			return false
		var record: Dictionary = raw_record
		var monster_id := _dpv2_json_integer(record.get("canonical_monster_id", null))
		var canonical_entry: Variant = _monsters_by_id.get(monster_id, null)
		if (
			monster_id <= 0
			or not canonical_entry is Dictionary
			or seen_ids.has(monster_id)
		):
			load_error = "dpv2_semantic_authority_record_identity_invalid"
			return false
		seen_ids[monster_id] = true
		var entry: Dictionary = canonical_entry
		if str(record.get("canonical_monster_name", "")) != str(entry.get("canonical_name", "")):
			load_error = "dpv2_semantic_authority_record_name_invalid"
			return false
		var runtime_allowed_value: Variant = record.get("runtime_allowed", null)
		if not runtime_allowed_value is bool:
			load_error = "dpv2_semantic_authority_runtime_allowed_invalid"
			return false
		var runtime_allowed := bool(runtime_allowed_value)
		if runtime_allowed != bool(entry.get("runtime_allowed", false)):
			load_error = "dpv2_semantic_authority_runtime_allowed_mismatch"
			return false
		if runtime_allowed:
			runtime_allowed_count += 1
		var status := str(record.get("semantic_status", ""))
		var state := str(record.get("drop_semantic_state", ""))
		if state.is_empty() or state != status:
			load_error = "dpv2_semantic_authority_state_invalid"
			return false
		var expected_status := "DIRECT_21CQ"
		if DPV2_RUNTIME_DISABLED_IDS.has(monster_id):
			expected_status = "RUNTIME_DISABLED"
		elif DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS.has(monster_id):
			expected_status = "EXPLICIT_NON_LOOT"
		elif monster_id == DPV2_PROJECT_EXTENSION_ID:
			expected_status = "PROJECT_EXTENSION"
		if status != expected_status:
			load_error = "dpv2_semantic_authority_status_mismatch"
			return false
		var source_row_count := _dpv2_json_integer(record.get("source_row_count", null))
		if source_row_count < 0:
			load_error = "dpv2_semantic_authority_source_row_count_invalid"
			return false
		var expected_source_count := source_row_count
		if DPV2_DIRECT_FROZEN_SOURCE_COUNTS.has(monster_id):
			expected_source_count = int(DPV2_DIRECT_FROZEN_SOURCE_COUNTS[monster_id])
		elif DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS.has(monster_id):
			expected_source_count = int(DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS[monster_id])
		elif monster_id == DPV2_PROJECT_EXTENSION_ID:
			expected_source_count = 69
		elif DPV2_RUNTIME_DISABLED_IDS.has(monster_id):
			expected_source_count = 0
		if source_row_count != expected_source_count:
			load_error = "dpv2_semantic_authority_frozen_source_count_mismatch"
			return false
		var reason_code := str(record.get("reason_code", ""))
		var expected_reason := "DIRECT_CATALOG_SOURCE_EXACT"
		var expected_human_frozen := false
		if DPV2_RUNTIME_DISABLED_IDS.has(monster_id):
			expected_reason = "RUNTIME_DISABLED"
			expected_human_frozen = true
		elif DPV2_EXPLICIT_NON_LOOT_SOURCE_COUNTS.has(monster_id):
			expected_reason = str(DPV2_EXPLICIT_NON_LOOT_REASON_CODES[monster_id])
			expected_human_frozen = true
		elif monster_id == DPV2_PROJECT_EXTENSION_ID:
			expected_reason = "PROJECT_EXTENSION"
			expected_human_frozen = true
		elif DPV2_DIRECT_FROZEN_SOURCE_COUNTS.has(monster_id):
			expected_reason = "HUMAN_FROZEN_DIRECT_21CQ"
			expected_human_frozen = true
		var human_frozen_value: Variant = record.get("human_frozen", null)
		if (
			not human_frozen_value is bool
			or bool(human_frozen_value) != expected_human_frozen
		):
			load_error = "dpv2_semantic_authority_decision_metadata_invalid"
			return false
		var reason_lower := reason_code.to_lower()
		for forbidden_reason: String in [
			"a0.7", "a07", "a0_7", "legacy" + "_role",
			"drop" + "_role", "role" + "_factor",
		]:
			if reason_lower.contains(forbidden_reason):
				load_error = "dpv2_semantic_authority_legacy_reason_forbidden"
				return false
		var evidence_value: Variant = record.get("evidence", null)
		if not evidence_value is Dictionary or (evidence_value as Dictionary).is_empty():
			load_error = "dpv2_semantic_authority_evidence_invalid"
			return false
		var evidence: Dictionary = evidence_value
		var current_user_decision := str(evidence.get("current_user_decision", ""))
		if (
			not current_user_decision.begins_with("CURRENT_USER_DECISION:")
			or current_user_decision.trim_prefix("CURRENT_USER_DECISION:").strip_edges().is_empty()
			or str(evidence.get("catalog_path", "")) != "assets/data/runtime/canonical_monster_catalog.json"
			or str(evidence.get("classification_path", "")).is_empty()
			or str(evidence.get("source_row_path", "")).is_empty()
		):
			load_error = "dpv2_semantic_authority_evidence_path_invalid"
			return false
		var source_row_value: Variant = evidence.get("source_row", null)
		var evidence_catalog_value: Variant = evidence.get("catalog", null)
		if not source_row_value is Dictionary or not evidence_catalog_value is Dictionary:
			load_error = "dpv2_semantic_authority_evidence_detail_invalid"
			return false
		var evidence_source_row: Dictionary = source_row_value
		var evidence_catalog: Dictionary = evidence_catalog_value
		if (
			_dpv2_json_integer(evidence_source_row.get("count", null)) != source_row_count
			or str(evidence_source_row.get("path", "")).is_empty()
			or str(evidence_source_row.get("selector", "")).is_empty()
			or not evidence_catalog.get("runtime_allowed", null) is bool
			or bool(evidence_catalog.get("runtime_allowed", false)) != runtime_allowed
			or str(evidence_catalog.get("runtime_allowed_path", "")).is_empty()
		):
			load_error = "dpv2_semantic_authority_evidence_detail_invalid"
			return false
		if DPV2_RUNTIME_DISABLED_IDS.has(monster_id):
			var runtime_evidence_value: Variant = evidence.get("runtime_evidence", null)
			if not runtime_evidence_value is Dictionary:
				load_error = "dpv2_semantic_authority_runtime_evidence_missing"
				return false
			var runtime_evidence: Dictionary = runtime_evidence_value
			for runtime_key: String in ["script_path", "effect_path", "runtime_path"]:
				if str(runtime_evidence.get(runtime_key, "")).is_empty():
					load_error = "dpv2_semantic_authority_runtime_evidence_invalid"
					return false
			if runtime_evidence.get("runtime_allowed", null) != false:
				load_error = "dpv2_semantic_authority_runtime_evidence_invalid"
				return false
		if status == "EXPLICIT_NON_LOOT":
			var exemption_value: Variant = record.get("exemption", null)
			if not exemption_value is Dictionary:
				load_error = "dpv2_semantic_authority_exemption_missing"
				return false
			var exemption: Dictionary = exemption_value
			if (
				not bool(exemption.get("required", false))
				or str(exemption.get("kind", "")) != "EXPLICIT_NON_LOOT"
				or str(exemption.get("reason_code", "")) != reason_code
				or str(exemption.get("reason", "")).is_empty()
			):
				load_error = "dpv2_semantic_authority_exemption_invalid"
				return false
		else:
			if record.get("exemption", null) != null:
				load_error = "dpv2_semantic_authority_unexpected_exemption"
				return false
		var expected_drop_enabled := status in ["DIRECT_21CQ", "PROJECT_EXTENSION"]
		if expected_drop_enabled:
			direct_count += int(status == "DIRECT_21CQ")
			project_count += int(status == "PROJECT_EXTENSION")
			production_slot_count += source_row_count
		elif status == "EXPLICIT_NON_LOOT":
			explicit_count += 1
		else:
			disabled_count += 1
		if (str(record.get("slot_policy", "")) == "COMPILE_DIRECT") != expected_drop_enabled:
			load_error = "dpv2_semantic_authority_slot_policy_invalid"
			return false
		if expected_drop_enabled:
			if str(record.get("drop_profile_id", "")).is_empty():
				load_error = "dpv2_semantic_authority_profile_id_invalid"
				return false
		else:
			if record.get("drop_profile_id", null) != null:
				load_error = "dpv2_semantic_authority_profile_id_invalid"
				return false
		_dpv2_semantic_by_id[monster_id] = record.duplicate(true)
	if (
		seen_ids.size() != 156
		or runtime_allowed_count != 153
		or direct_count != 143
		or project_count != 1
		or explicit_count != 9
		or disabled_count != 3
		or production_slot_count != 6809
	):
		load_error = "dpv2_semantic_authority_record_summary_invalid"
		return false
	dpv2_monster_drop_semantic_authority = authority
	return true


func _dpv2_json_integer(value: Variant) -> int:
	# JSON.parse_string represents all numeric literals as floats in this
	# runtime. Accept only finite integral values so IDs and rational fields
	# cannot silently truncate a malformed decimal.
	if value is int:
		return int(value)
	if value is float:
		var numeric := float(value)
		if numeric == floor(numeric) and abs(numeric) <= 2147483647.0:
			return int(numeric)
	return -1


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
## Keeps resolve_canonical_drop_item() as the generic item identity guard, then
## applies the explicit direct source-label mapping when one is available.
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
	var token := str(drop_entry.get("item", ""))
	var canonical_name := str(item_result.get("item_name", ""))
	var direct_identity: Dictionary = {}
	var source_identity: Variant = _dpv2_direct_item_by_source_label.get(
		token,
		null,
	)
	if source_identity is Dictionary:
		direct_identity = (source_identity as Dictionary).duplicate(true)
	else:
		var name_identity: Variant = _dpv2_direct_item_by_name.get(
			_canonical_item_name(canonical_name),
			null,
		)
		if name_identity is Dictionary:
			direct_identity = (name_identity as Dictionary).duplicate(true)
	var canonical_item_id := -1
	if not direct_identity.is_empty():
		canonical_item_id = _dpv2_json_integer(
			direct_identity.get("canonical_item_id", null)
		)
		var direct_name := str(direct_identity.get("canonical_item_name", ""))
		if (
			canonical_item_id <= 0
			or direct_name.is_empty()
			or _canonical_item_name(direct_name)
				!= _canonical_item_name(canonical_name)
		):
			return {"ok": false, "reason": "canonical_item_identity_mismatch"}
	else:
		# Generic canonical catalog identity remains a valid audit fallback for
		# rows outside the direct source bundle. It is never used by
		# LootRuntime's V2 probability path.
		canonical_item_id = _dpv2_json_integer(item_result.get("item_id", null))
		if canonical_item_id <= 0:
			return {"ok": false, "reason": "canonical_item_identity_unresolved"}
	item_result["canonical_item_id"] = canonical_item_id
	item_result["kind"] = "item"
	return item_result


func is_dpv2_direct_baseline_loaded() -> bool:
	return dpv2_direct_baseline_loaded


func dpv2_direct_profile(monster_id: Variant) -> Dictionary:
	if not dpv2_direct_baseline_loaded:
		return {}
	var resolved_id := canonical_monster_id(monster_id)
	var value: Variant = _dpv2_direct_profile_by_id.get(resolved_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func get_dpv2_direct_profile(monster_id: Variant) -> Dictionary:
	return dpv2_direct_profile(monster_id)


func dpv2_direct_profile_slots(monster_id: Variant) -> Array:
	var profile := dpv2_direct_profile(monster_id)
	var slots: Variant = profile.get("slots", [])
	return slots.duplicate(true) if slots is Array else []


func get_dpv2_direct_slots(monster_id: Variant) -> Array:
	return dpv2_direct_profile_slots(monster_id)


func dpv2_direct_slot(slot_uid: String) -> Dictionary:
	if not dpv2_direct_baseline_loaded or slot_uid.is_empty():
		return {}
	var value: Variant = _dpv2_direct_slot_by_uid.get(slot_uid, {})
	if not value is Dictionary or (value as Dictionary).is_empty():
		return {}
	var indexed: Dictionary = value
	var slot: Variant = indexed.get("slot", {})
	if not slot is Dictionary:
		return {}
	var result: Dictionary = (slot as Dictionary).duplicate(true)
	result["canonical_monster_id"] = int(indexed.get("canonical_monster_id", -1))
	result["drop_profile_id"] = str(indexed.get("drop_profile_id", ""))
	return result


func get_dpv2_direct_slot(slot_uid: String) -> Dictionary:
	return dpv2_direct_slot(slot_uid)


func dpv2_direct_item_identity(canonical_item_id: Variant) -> Dictionary:
	var item_id := _dpv2_json_integer(canonical_item_id)
	if not dpv2_direct_baseline_loaded or item_id <= 0:
		return {}
	var value: Variant = _dpv2_direct_item_by_id.get(item_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func dpv2_direct_resolve_slot_reward(slot: Dictionary) -> Dictionary:
	if not dpv2_direct_baseline_loaded:
		return {"ok": false, "reason": "dpv2_direct_baseline_unavailable"}
	var has_item := slot.has("canonical_item_id")
	var has_gold := slot.has("gold_amount")
	if int(has_item) + int(has_gold) != 1:
		return {"ok": false, "reason": "dpv2_direct_reward_identity_invalid"}
	if has_gold:
		var gold_amount: Variant = slot.get("gold_amount", null)
		var resolved_gold_amount := _dpv2_json_integer(gold_amount)
		if resolved_gold_amount <= 0:
			return {"ok": false, "reason": "dpv2_direct_gold_amount_invalid"}
		return {
			"ok": true,
			"reason": "",
			"kind": "gold",
			"gold_amount": resolved_gold_amount,
		}
	var item_id_value: Variant = slot.get("canonical_item_id", null)
	var item_id := _dpv2_json_integer(item_id_value)
	if item_id <= 0:
		return {"ok": false, "reason": "dpv2_direct_item_id_invalid"}
	var identity := dpv2_direct_item_identity(item_id)
	var canonical_name := str(identity.get("canonical_item_name", ""))
	if identity.is_empty() or canonical_name.is_empty():
		return {"ok": false, "reason": "dpv2_direct_item_identity_unresolved"}
	# The canonical ID is authoritative. Name lookup is deliberately delayed
	# until after that ID has been validated against the direct identity map.
	var item := get_item_record(canonical_name)
	if item.is_empty():
		return {"ok": false, "reason": "dpv2_direct_item_name_unresolved"}
	var resolved_name := str(item.get("name", ""))
	if resolved_name.is_empty() or _canonical_item_name(resolved_name) != _canonical_item_name(canonical_name):
		return {"ok": false, "reason": "dpv2_direct_item_identity_mismatch"}
	return {
		"ok": true,
		"reason": "",
		"kind": "item",
		"canonical_item_id": item_id,
		"item_name": resolved_name,
	}


func dpv2_direct_slot_probability(
	monster_id: Variant,
	slot_uid: String
) -> Dictionary:
	if not dpv2_direct_baseline_loaded:
		return {"ok": false, "reason": "dpv2_direct_baseline_unavailable"}
	var resolved_id := canonical_monster_id(monster_id)
	var indexed_value: Variant = _dpv2_direct_slot_by_uid.get(slot_uid, {})
	if resolved_id <= 0 or not indexed_value is Dictionary:
		return {"ok": false, "reason": "dpv2_direct_slot_unresolved"}
	var indexed: Dictionary = indexed_value
	if int(indexed.get("canonical_monster_id", -1)) != resolved_id:
		return {"ok": false, "reason": "dpv2_direct_slot_monster_mismatch"}
	var slot_value: Variant = indexed.get("slot", {})
	if not slot_value is Dictionary:
		return {"ok": false, "reason": "dpv2_direct_slot_invalid"}
	var slot: Dictionary = slot_value
	var base_numerator: Variant = slot.get("base_numerator", null)
	var base_denominator: Variant = slot.get("base_denominator", null)
	var resolved_base_numerator := _dpv2_json_integer(base_numerator)
	var resolved_base_denominator := _dpv2_json_integer(base_denominator)
	if (
		resolved_base_numerator <= 0
		or resolved_base_denominator <= 0
	):
		return {"ok": false, "reason": "dpv2_direct_probability_invalid"}
	var global_scale := dpv2_active_global_drop_rate()
	var scale_numerator: Variant = global_scale.get("numerator", null)
	var scale_denominator: Variant = global_scale.get("denominator", null)
	var resolved_scale_numerator := _dpv2_json_integer(scale_numerator)
	var resolved_scale_denominator := _dpv2_json_integer(scale_denominator)
	if (
		resolved_scale_numerator <= 0
		or resolved_scale_denominator <= 0
	):
		return {"ok": false, "reason": "dpv2_global_scale_invalid"}
	var raw_numerator := resolved_base_numerator * resolved_scale_numerator
	var raw_denominator := resolved_base_denominator * resolved_scale_denominator
	if raw_numerator <= 0 or raw_denominator <= 0:
		return {"ok": false, "reason": "dpv2_probability_ratio_invalid"}
	var final_numerator := raw_numerator
	var final_denominator := raw_denominator
	if final_numerator >= final_denominator:
		final_numerator = 1
		final_denominator = 1
	else:
		var divisor := _positive_gcd(final_numerator, final_denominator)
		final_numerator /= divisor
		final_denominator /= divisor
	var final_probability := float(final_numerator) / float(final_denominator)
	return {
		"ok": true,
		"reason": "",
		"slot_uid": slot_uid,
		"canonical_monster_id": resolved_id,
		"canonical_item_id": _dpv2_json_integer(slot.get("canonical_item_id", -1)),
		"gold_amount": _dpv2_json_integer(slot.get("gold_amount", -1)),
		"reward_kind": "item" if slot.has("canonical_item_id") else "gold",
		"base_numerator": resolved_base_numerator,
		"base_denominator": resolved_base_denominator,
		"base_probability": float(resolved_base_numerator) / float(resolved_base_denominator),
		"global_preset": str(global_scale.get("preset", "")),
		"global_scale_numerator": resolved_scale_numerator,
		"global_scale_denominator": resolved_scale_denominator,
		"global_scale": float(resolved_scale_numerator) / float(resolved_scale_denominator),
		"unreduced_final_numerator": raw_numerator,
		"unreduced_final_denominator": raw_denominator,
		"final_numerator": final_numerator,
		"final_denominator": final_denominator,
		"final_probability": final_probability,
		"probability_numerator": final_numerator,
		"probability_denominator": final_denominator,
		"overflow_priority": int(slot.get("overflow_priority", 0)),
		"protected_drop": bool(slot.get("protected_drop", false)),
		"baseline_origin": str(slot.get("baseline_origin", "")),
		"source_provenance_id": str(slot.get("source_provenance_id", "")),
	}


func get_dpv2_direct_slot_probability(
	monster_id: Variant,
	slot_uid: String
) -> Dictionary:
	return dpv2_direct_slot_probability(monster_id, slot_uid)


func is_dpv2_single_player_drop_boost_loaded() -> bool:
	return dpv2_single_player_drop_boost_loaded


func dpv2_single_player_boost_formula(
	base_numerator: int,
	base_denominator: int,
	auto_boost: bool = true
) -> Dictionary:
	if base_numerator <= 0 or base_denominator <= 0:
		return {"ok": false, "reason": "spb_base_probability_invalid"}
	var base_divisor := _positive_gcd(base_numerator, base_denominator)
	var reduced_numerator := base_numerator / base_divisor
	var reduced_denominator := base_denominator / base_divisor
	if not auto_boost or reduced_numerator * 20 >= reduced_denominator:
		return {
			"ok": true,
			"numerator": reduced_numerator,
			"denominator": reduced_denominator,
			"ceiling_applied": false,
		}
	var boosted_numerator := reduced_numerator * 25
	if boosted_numerator * 20 > reduced_denominator:
		return {
			"ok": true,
			"numerator": 1,
			"denominator": 20,
			"ceiling_applied": true,
		}
	var boosted_divisor := _positive_gcd(boosted_numerator, reduced_denominator)
	return {
		"ok": true,
		"numerator": boosted_numerator / boosted_divisor,
		"denominator": reduced_denominator / boosted_divisor,
		"ceiling_applied": false,
	}


func dpv2_effective_slot_probability(
	monster_id: Variant,
	slot_uid: String
) -> Dictionary:
	if not dpv2_direct_baseline_loaded:
		return {"ok": false, "reason": "spb_direct_baseline_unavailable"}
	if (
		not dpv2_single_player_drop_boost_loaded
		or dpv2_single_player_drop_boost.is_empty()
		or dpv2_single_player_effective_probability.is_empty()
	):
		return {"ok": false, "reason": "spb_effective_probability_unavailable"}
	var resolved_id := canonical_monster_id(monster_id)
	var direct_indexed_value: Variant = _dpv2_direct_slot_by_uid.get(slot_uid, null)
	var effective_value: Variant = _dpv2_spb_effective_by_uid.get(slot_uid, null)
	if not direct_indexed_value is Dictionary or not effective_value is Dictionary:
		return {"ok": false, "reason": "spb_effective_probability_unresolved"}
	var direct_indexed: Dictionary = direct_indexed_value
	var effective: Dictionary = effective_value
	if (
		resolved_id <= 0
		or int(direct_indexed.get("canonical_monster_id", -1)) != resolved_id
		or _dpv2_json_integer(effective.get("canonical_monster_id", null)) != resolved_id
	):
		return {"ok": false, "reason": "spb_effective_probability_monster_mismatch"}
	var direct_slot_value: Variant = direct_indexed.get("slot", null)
	if not direct_slot_value is Dictionary:
		return {"ok": false, "reason": "spb_direct_slot_invalid"}
	var direct_slot: Dictionary = direct_slot_value
	for field: String in [
		"base_numerator", "base_denominator", "source_provenance_id",
		"protected_drop", "overflow_priority", "baseline_origin",
		"canonical_item_id", "gold_amount",
	]:
		if (
			effective.has(field) != direct_slot.has(field)
			or effective.has(field) and effective.get(field) != direct_slot.get(field)
		):
			return {
				"ok": false,
				"reason": "spb_effective_probability_mirror_mismatch:%s" % field,
			}
	var production_value: Variant = dpv2_single_player_drop_boost.get(
		"production", null
	)
	if not production_value is Dictionary:
		return {"ok": false, "reason": "spb_boost_authority_unavailable"}
	var production: Dictionary = production_value
	var enabled_value: Variant = production.get("enabled", null)
	if not enabled_value is bool:
		return {"ok": false, "reason": "spb_enabled_flag_invalid"}
	var spb_enabled := bool(enabled_value)
	var global_scale := dpv2_active_global_drop_rate()
	var scale_numerator := _dpv2_json_integer(global_scale.get("numerator", null))
	var scale_denominator := _dpv2_json_integer(global_scale.get("denominator", null))
	if scale_numerator <= 0 or scale_denominator <= 0:
		return {"ok": false, "reason": "spb_global_scale_invalid"}
	if spb_enabled and (
		str(global_scale.get("preset", "")) != "1x"
		or scale_numerator != 1
		or scale_denominator != 1
	):
		return {"ok": false, "reason": "spb_enabled_requires_global_1x"}
	var base_numerator := _dpv2_json_integer(effective.get("base_numerator", null))
	var base_denominator := _dpv2_json_integer(effective.get("base_denominator", null))
	var table_effective_numerator := _dpv2_json_integer(
		effective.get("effective_numerator", null)
	)
	var table_effective_denominator := _dpv2_json_integer(
		effective.get("effective_denominator", null)
	)
	if (
		base_numerator <= 0 or base_denominator <= 0
		or table_effective_numerator <= 0 or table_effective_denominator <= 0
	):
		return {"ok": false, "reason": "spb_effective_probability_invalid"}
	var selected_numerator := (
		table_effective_numerator if spb_enabled else base_numerator
	)
	var selected_denominator := (
		table_effective_denominator if spb_enabled else base_denominator
	)
	var raw_numerator := selected_numerator * scale_numerator
	var raw_denominator := selected_denominator * scale_denominator
	if raw_numerator <= 0 or raw_denominator <= 0:
		return {"ok": false, "reason": "spb_final_probability_invalid"}
	var final_numerator := raw_numerator
	var final_denominator := raw_denominator
	if final_numerator >= final_denominator:
		final_numerator = 1
		final_denominator = 1
	else:
		var divisor := _positive_gcd(final_numerator, final_denominator)
		final_numerator /= divisor
		final_denominator /= divisor
	var result := {
		"ok": true,
		"reason": "",
		"slot_uid": slot_uid,
		"canonical_monster_id": resolved_id,
		"canonical_item_id": _dpv2_json_integer(effective.get("canonical_item_id", -1)),
		"gold_amount": _dpv2_json_integer(effective.get("gold_amount", -1)),
		"reward_kind": "item" if effective.has("canonical_item_id") else "gold",
		"spb_enabled": spb_enabled,
		"spb_selected_source": "effective" if spb_enabled else "base",
		"boost_policy": str(effective.get("boost_policy", "")),
		"boost_reason_code": str(effective.get("reason_code", "")),
		"boost_formula_reason_code": str(effective.get("formula_reason_code", "")),
		"boost_multiplier_numerator": _dpv2_json_integer(
			effective.get("boost_multiplier_numerator", null)
		),
		"boost_multiplier_denominator": _dpv2_json_integer(
			effective.get("boost_multiplier_denominator", null)
		),
		"ceiling_numerator": _dpv2_json_integer(
			effective.get("auto_boost_ceiling_numerator", null)
		),
		"ceiling_denominator": _dpv2_json_integer(
			effective.get("auto_boost_ceiling_denominator", null)
		),
		"ceiling_applied": bool(effective.get("ceiling_applied", false)),
		"base_numerator": base_numerator,
		"base_denominator": base_denominator,
		"base_probability": float(base_numerator) / float(base_denominator),
		"effective_numerator": table_effective_numerator,
		"effective_denominator": table_effective_denominator,
		"effective_probability": (
			float(table_effective_numerator) / float(table_effective_denominator)
		),
		"selected_numerator": selected_numerator,
		"selected_denominator": selected_denominator,
		"global_preset": str(global_scale.get("preset", "")),
		"global_scale_numerator": scale_numerator,
		"global_scale_denominator": scale_denominator,
		"global_scale": float(scale_numerator) / float(scale_denominator),
		"unreduced_final_numerator": raw_numerator,
		"unreduced_final_denominator": raw_denominator,
		"final_numerator": final_numerator,
		"final_denominator": final_denominator,
		"final_probability": float(final_numerator) / float(final_denominator),
		"probability_numerator": final_numerator,
		"probability_denominator": final_denominator,
		"overflow_priority": int(effective.get("overflow_priority", 0)),
		"protected_drop": bool(effective.get("protected_drop", false)),
		"baseline_origin": str(effective.get("baseline_origin", "")),
		"source_provenance_id": str(effective.get("source_provenance_id", "")),
	}
	if effective.has("gold_amount"):
		var base_gold_amount := _dpv2_json_integer(
			effective.get("base_gold_amount", null)
		)
		var effective_gold_amount := _dpv2_json_integer(
			effective.get("effective_gold_amount", null)
		)
		if (
			base_gold_amount <= 0
			or effective_gold_amount != base_gold_amount * 10
			or base_gold_amount != _dpv2_json_integer(effective.get("gold_amount", null))
		):
			return {"ok": false, "reason": "spb_effective_gold_amount_mismatch"}
		result["base_gold_amount"] = base_gold_amount
		result["effective_gold_amount"] = effective_gold_amount
		result["final_gold_amount"] = (
			effective_gold_amount if spb_enabled else base_gold_amount
		)
	return result


func get_dpv2_effective_slot_probability(
	monster_id: Variant,
	slot_uid: String
) -> Dictionary:
	return dpv2_effective_slot_probability(monster_id, slot_uid)


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
	if not dpv2_direct_baseline_loaded:
		return 0
	var policy: Variant = dpv2_direct_baseline.get("probability_policy", {})
	if not policy is Dictionary:
		return 0
	return maxi(0, _dpv2_json_integer(
		(policy as Dictionary).get("post_rng_ground_slot_limit", 0)
	))


func dpv2_source_slot_gate() -> Dictionary:
	if not dpv2_direct_baseline_loaded:
		return {
			"authority": "dpv2.direct_baseline.v2",
			"available": false,
			"compiled_slots": 0,
			"logical_source_rows": 0,
			"explicit_non_loot_source_rows": 0,
			"retired_source_rows": 0,
			"excluded_source_rows": 0,
		}
	var summary: Variant = dpv2_direct_baseline.get("summary", {})
	var semantic_summary: Variant = dpv2_monster_drop_semantic_authority.get(
		"summary",
		{},
	)
	var semantic_accounting: Variant = (
		semantic_summary.get("source_accounting", {})
		if semantic_summary is Dictionary
		else {}
	)
	var tracked_source: Variant = dpv2_direct_baseline_manifest.get(
		"tracked_logical_source", {}
	)
	var logical_rows := 0
	if tracked_source is Dictionary:
		logical_rows = _dpv2_json_integer(
			(tracked_source as Dictionary).get("logical_rows", 0)
		)
	var compiled_slots := 0
	var enabled_monsters := 0
	var non_loot_monsters := 0
	var runtime_allowed_monsters := 0
	var explicit_non_loot_monsters := 0
	var runtime_disabled_monsters := 0
	var explicit_non_loot_source_rows := 0
	var retired_source_rows := 0
	if summary is Dictionary:
		compiled_slots = _dpv2_json_integer(
			(summary as Dictionary).get("compiled_slots", 0)
		)
		enabled_monsters = _dpv2_json_integer(
			(summary as Dictionary).get("drop_enabled_monsters", 0)
		)
		non_loot_monsters = _dpv2_json_integer(
			(summary as Dictionary).get("non_loot_monsters", 0)
		)
	if semantic_summary is Dictionary:
		runtime_allowed_monsters = _dpv2_json_integer(
			(semantic_summary as Dictionary).get("runtime_allowed", 0)
		)
		explicit_non_loot_monsters = _dpv2_json_integer(
			(semantic_summary as Dictionary).get("explicit_non_loot", 0)
		)
		runtime_disabled_monsters = _dpv2_json_integer(
			(semantic_summary as Dictionary).get("runtime_disabled", 0)
		)
	if semantic_accounting is Dictionary:
		explicit_non_loot_source_rows = _dpv2_json_integer(
			(semantic_accounting as Dictionary).get("EXPLICIT_NON_LOOT_EXCLUDED", 0)
		)
		retired_source_rows = _dpv2_json_integer(
			(semantic_accounting as Dictionary).get("RETIRED_OUT_OF_RUNTIME", 0)
		)
	return {
		"authority": "dpv2.direct_baseline.v2",
		"available": true,
		"identity_key": "canonical_monster_id",
		"logical_source_rows": logical_rows,
		"compiled_slots": compiled_slots,
		"canonical_source_slots": compiled_slots,
		"drop_enabled_source_slots": compiled_slots,
		"drop_disabled_source_slots": explicit_non_loot_source_rows + retired_source_rows,
		"explicit_non_loot_source_rows": explicit_non_loot_source_rows,
		"retired_source_rows": retired_source_rows,
		"excluded_source_rows": explicit_non_loot_source_rows + retired_source_rows,
		"source_accounting": semantic_accounting.duplicate(true) if semantic_accounting is Dictionary else {},
		"canonical_monster_profiles": _dpv2_json_integer(
			(semantic_summary as Dictionary).get("canonical_monsters", 0)
			if semantic_summary is Dictionary else 0
		),
		"runtime_allowed_monsters": runtime_allowed_monsters,
		"drop_enabled_monsters": enabled_monsters,
		"explicit_non_loot_monsters": explicit_non_loot_monsters,
		"runtime_disabled_monsters": runtime_disabled_monsters,
		"non_loot_monsters": non_loot_monsters,
		"reward_resolved_enabled_slots": compiled_slots,
		"probability_resolved_enabled_slots": compiled_slots,
		"rng_eligible_slots": compiled_slots,
		"rng_roll_count": compiled_slots,
		"all_enabled_resolved_slots_rng_before_overflow": true,
		"overflow_stage": "after_all_probability_rolls",
		"maximum_ground_slots": dpv2_ground_slot_limit(),
	}


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
