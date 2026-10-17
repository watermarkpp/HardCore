extends Node

const ContentQueries := preload("res://scripts/gameplay/content/content_query_core.gd")
const LegacyContentFields := preload("res://scripts/gameplay/content/legacy_content_fields.gd")
const ContentGraph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const CatalogGate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
var _content_queries: ContentQueries
var _query_content_port: ContentQueries.ContentPort
var profession_growth_source_path: String:
	get:
		return str(ContentLayers.vanilla_dataset("professionGrowth"))

# Main callback depth only. No new gameplay/IO owner or timer.
var _original_main_callback_ledger: Dictionary = {}


func content_query_core() -> ContentQueries:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return null
	if _content_queries == null:
		if not ContentQueries.prepare_factory(ContentQueries): return null
		_content_queries = ContentQueries.new(LegacyContentFields.new(self))
		_query_content_port = ContentQueries.ContentPort.new(_content_queries)
		_content_queries.bind_content_port(_query_content_port)
	return _content_queries

func publish_content_snapshot(catalog_lease: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not CatalogGate.is_active(catalog_lease): return {}
	if not is_loaded() or _database_build_in_progress: return {}
	var fields: Dictionary = {}
	for field: String in ContentQueries.STATE_FIELDS: fields[field] = get(field)
	var captured := ContentGraph.capture(fields)
	if not captured.success: return {}
	# Fields already own a recursively read-only capture. Freeze only the new
	# envelope; cloning this full graph again adds no ownership protection.
	var snapshot := {"contract_id": "content.query.snapshot.v1",
		"database_revision": database_revision, "fields": captured.value,
		"fields_sha256": ContentGraph.fingerprint(captured.value),
		"catalog_lease": ContentGraph.capture(catalog_lease).value}
	snapshot.make_read_only()
	return snapshot


const DPV2RepairV5 = preload("res://scripts/drop/dpv2_repair_v5_contract.gd")
const EntityRegistry := preload("res://scripts/identity/entity_registry.gd")
const ItemCategories := preload("res://scripts/identity/item_category_identity.gd")
const ItemExtensionCodec := preload("res://scripts/items/item_extension_codec.gd")
const SocketGemRules := preload("res://scripts/items/socket_gem_rules.gd")
const RuneItemRules := preload("res://scripts/items/rune_item_rules.gd")
const CanonicalSkills := preload("res://scripts/skills/skill_data_loader.gd")
const EquipmentGrantedSkillRules := preload("res://scripts/equipment_granted_skill_rules.gd")

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const PricingServiceScript = preload("res://scripts/pricing_service.gd")
const EnhancementBlackIron := preload("res://scripts/layers/rules/equipment_enhancement_black_iron.gd")
const AncientRelicFragmentScript := preload("res://scripts/layers/rules/ancient_relic_fragment.gd")
const RelicSynthesisRulesScript := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")

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
const FORMAL_MAP_IDENTITY_REGISTRY_PATH := (
	"res://assets/data/map_design/map_identity_registry.json"
)
const SERVICE_ITEM_CATALOG_PATH = ContentQueries.SERVICE_ITEM_CATALOG_PATH
const EQUIPMENT_PRICE_CANDIDATES_PATH = ContentQueries.EQUIPMENT_PRICE_CANDIDATES_PATH
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
const DPV2_SINGLE_PLAYER_ITEM_BOOST_CLASSIFICATION_PATH := (
	"res://assets/data/drop/dpv2_single_player_item_boost_classification_v1.json"
)
const DPV2_SINGLE_PLAYER_EFFECTIVE_PROBABILITY_PATH := (
	"res://assets/data/drop/dpv2_single_player_effective_probability_v1.json"
)
## RV15-J3 narrow test seam: the decoupling test points the legacy SPB
## probability ledger at an unavailable location to prove the activated
## sheet mode boots and drops without it. Production never sets this; when
## empty the three real paths above are used.
static var spb_ledger_paths_override: PackedStringArray = PackedStringArray()
const DPV2_DIRECT_ITEM_MAPPING_PATH := (
	"res://assets/data/drop/dpv2_21cq_item_mapping_v1.json"
)
const DPV2_MONSTER_DROP_SEMANTIC_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_monster_drop_semantic_authority_v1.json"
)
const DPV2_VERIFIED_PROFILE_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_21cq_verified_profile_authority_v1.json"
)
const MONSTER_GROUND_SLOT_GROUP_POLICY_PATH := (
	"res://assets/data/drop/monster_ground_slot_group_policy.runtime.json"
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
# Historical drop-ledger status, not a restriction on monster spawning.
const DPV2_RUNTIME_DISABLED_IDS := {33: true, 183: true, 241: true}
const DPV2_PROJECT_EXTENSION_ID := 225
const DPV2_SPB_BASE_SHA := "342891ab884150c0e81084c932df8205484e6388"
const DPV2_SPB_SOURCE_SHA256 := "1F5240EEB01CC0D488DE08D570EE3E794EA13F7CA31A639677800B7AE44AB515"
const DPV2_SPB_DIRECT_BASELINE_SHA256 := DPV2RepairV5.BASELINE_SHA256
const DPV2_SPB_PROVENANCE_SHA256 := "E7E57BF197A960F988B0FF60897CFBFC20884DE420C300366A665FC41EF14F01"
const DPV2_SPB_LEDGER_SHA256 := "B3BCFB22ED285A8EA39E2A86BF522ECADABAC801F9BA4EB27BA784F3F8FF5C3A"
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

const ITEM_ALIASES = ContentQueries.ITEM_ALIASES
# 服务端使用经典MAP代码；正式地图运行时使用冻结 canonical IDs。
# 别名必须显式保留，禁止用名称或数组顺序推导。
const SERVICE_RUNTIME_MAP_ALIASES := ContentQueries.SERVICE_RUNTIME_MAP_ALIASES
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
var monster_ground_slot_group_policy: Dictionary = {}
var dpv2_direct_baseline_loaded := false
var dpv2_single_player_drop_boost: Dictionary = {}
var dpv2_single_player_item_boost_classification: Dictionary = {}
var dpv2_single_player_effective_probability: Dictionary = {}
var dpv2_single_player_drop_boost_loaded := false
## RV15-J3: when the legacy SPB probability ledger cannot be loaded this
## carries the exact load_error for history-audit diagnostics. It is empty
## whenever the ledger loaded normally. Sheet-mode startup and drops do not
## consult this; see load_database.
var spb_ledger_audit_error := ""
var maps: Array = []
var monsters: Array = []
var bosses: Array = []
var items: Array = []
var skills: Array = []
var drops: Array = []
var tasks: Array = []
var item_catalog: Array = []
var load_error := ""
var _item_category_error := ""
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
var _catalog_by_currency_id: Dictionary = {}
var _skill_books_by_skill: Dictionary = {}
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

var database_revision := 0
var _database_build_in_progress := false
## Only database-owned data is adopted. Autoload construction, direct-load
## guards, and the shared immutable rule caches retain their existing owners.
const DATABASE_STATE_FIELDS := [
	"database", "service_reference", "equipment_customization", "equipment_client_art",
	"equipment_visual_catalog", "warrior_wear_art", "warrior_client_art", "bich_quest_chain",
	"bich_undead_art", "bich_common_art", "boss_service_rules", "bich_community_baseline",
	"service_item_catalog", "equipment_price_candidates", "merchant_catalog",
	"canonical_monster_catalog", "item_runtime_authority", "dpv2_global_drop_rate_authority",
	"dpv2_direct_baseline_manifest", "dpv2_direct_baseline", "dpv2_monster_drop_semantic_authority",
	"monster_ground_slot_group_policy", "dpv2_direct_baseline_loaded",
	"dpv2_single_player_drop_boost", "dpv2_single_player_item_boost_classification",
	"dpv2_single_player_effective_probability", "dpv2_single_player_drop_boost_loaded",
	"spb_ledger_audit_error", "maps", "monsters", "bosses", "items", "skills", "drops", "tasks",
	"item_catalog", "load_error", "_item_category_error", "_monsters_by_id",
	"_monster_runtime_drop_closure", "_items_by_name", "_items_by_id", "_maps_by_id", "_maps_by_name",
	"_catalog_by_name", "_catalog_by_item_id", "_catalog_by_service_index", "_catalog_by_currency_id",
	"_skill_books_by_skill", "_price_by_name", "_price_by_item_id", "_price_by_service_index",
	"_bich_quests_by_id", "_dpv2_global_scale_by_preset", "_dpv2_direct_profile_by_id",
	"_dpv2_direct_slot_by_uid", "_dpv2_spb_effective_by_uid", "_dpv2_semantic_by_id",
	"_dpv2_direct_item_by_id", "_dpv2_direct_item_by_source_label", "_dpv2_direct_item_by_name",
]

const CANONICAL_MONSTER_COUNTS_CONTRACT_ID := (
	"monster.catalog.runtime_counts.v1"
)


func _ready() -> void:
	_original_main_callback_ledger["_ready"] = int(_original_main_callback_ledger.get("_ready",0)) + 1
	_original_source_game_data__ready()
	_original_main_callback_ledger["_ready"] -= 1


func _original_source_game_data__ready() -> void:
	if not initial_load_deferred:
		ensure_loaded()


func is_loaded() -> bool:
	return content_query_core().is_loaded()


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
	# Direct reload callers do not pass through ensure_loaded().  Clear the
	# published state before any reload work so a failed reload cannot leave a
	# previous successful database advertised through is_loaded().
	_initial_load_complete = false
	# Consumers that run during Android autoload construction must fail closed.
	# StartupLoading explicitly opens this gate only after the intro has drawn.
	if not ContentLayers.is_loaded():
		_discard_database_state("content_layers_not_ready")
		return false
	if not _load_database_tables(ContentLayers.merged_database, true):
		_discard_database_state(load_error)
		return false
	database_revision += 1
	announce_database_reload()
	return true


func prepare_database_candidate(merged: Dictionary) -> Dictionary:
	if not ContentLayers.is_loaded():
		return {"success": false, "error": "content_layers_not_ready"}
	var candidate: Node = get_script().new()
	# The same formal parsing/validation path builds unpublished data. Its
	# failure cannot clear the live catalog, loaded flag, or existing indexes.
	if not candidate._load_database_tables(merged, false):
		var error: String = candidate.load_error
		candidate.free()
		return {"success": false, "error": error}
	return {"success": true, "candidate": candidate}


func adopt_database_candidate(candidate: Node) -> bool:
	if not is_instance_valid(candidate) or candidate == self or candidate.is_inside_tree():
		return false
	if candidate.get_script() != get_script() or not candidate.is_loaded():
		return false
	for field: String in DATABASE_STATE_FIELDS:
		set(field, candidate.get(field))
	_initial_load_complete = true
	database_revision += 1
	return true


func _load_database_tables(merged: Dictionary, report_error: bool) -> bool:
	_database_build_in_progress = true
	var success := _parse_database_tables(merged, report_error)
	_database_build_in_progress = false
	return success


func _discard_database_state(error: String) -> void:
	# A refused direct reload is explicitly unavailable. Drop every published
	# catalog/index together; no public lookup may observe a partial old/new mix.
	for field: String in DATABASE_STATE_FIELDS:
		match typeof(get(field)):
			TYPE_DICTIONARY:
				set(field, {})
			TYPE_ARRAY:
				set(field, [])
			TYPE_BOOL:
				set(field, false)
			TYPE_STRING:
				set(field, "")
	_initial_load_complete = false
	load_error = error


func _parse_database_tables(merged: Dictionary, report_error: bool) -> bool:
	_initial_load_complete = false
	# ContentLayers already parsed the source tables; this is one private copy
	# for the active owner or its short-lived, unpublished preparation.
	var parsed: Dictionary = merged.duplicate(true)
	if not parsed is Dictionary or parsed.get("maps", []).is_empty():
		load_error = "五层内容注册表未能生成Merged Game Database"
		if report_error:
			push_error(load_error)
		return false

	database = parsed
	maps = database.get("maps", [])
	_normalize_map_ids()
	if not _append_formal_map_identities():
		return false
	# The merged legacy database remains available for maps/items/tasks, but it
	# is no longer a monster authority.  Runtime monster identity, combat,
	# appearance and drops all come from the canonical ID-keyed catalog.
	monsters = []
	bosses = []
	if not _load_canonical_monster_catalog():
		return false
	if not _load_monster_ground_slot_group_policy():
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
	# RV15-J3: the legacy SPB probability ledger is history-audit-only. The
	# activated sheet mode boots on the user loot sheet authority plus the
	# direct baseline identity/overflow authority; a missing or invalid SPB
	# ledger is recorded for audit and no longer blocks startup or production
	# drops. Its loaded flag keeps its real value for audit consumers, and
	# there is deliberately no fallback from the sheet authority to the old
	# ledger probabilities.
	if not _load_dpv2_single_player_drop_boost():
		spb_ledger_audit_error = load_error
		push_warning(
			"SPB ledger unavailable (history audit only): " + load_error
		)
	else:
		spb_ledger_audit_error = ""
	_load_equipment_price_candidates()
	_load_merchant_catalog()
	if not _build_indexes():
		return false
	if not ItemDropInstanceRules.prepare_runtime():
		load_error = "item_drop_affix_rules_not_ready"
		return false
	load_error = ""
	_initial_load_complete = true
	return true


func announce_database_reload() -> void:
	database_reloaded.emit()
	print("数据库载入完成：地图%d 怪物%d Boss%d 装备%d 技能等级%d 掉落槽%d 任务%d" % [
		maps.size(), monsters.size(), bosses.size(), items.size(), skills.size(), drops.size(), tasks.size()
	])


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


func _load_monster_ground_slot_group_policy() -> bool:
	monster_ground_slot_group_policy = {}
	if not FileAccess.file_exists(MONSTER_GROUND_SLOT_GROUP_POLICY_PATH):
		load_error = "monster_ground_slot_group_policy_missing"
		return false
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(MONSTER_GROUND_SLOT_GROUP_POLICY_PATH)
	)
	if not parsed is Dictionary:
		load_error = "monster_ground_slot_group_policy_invalid_json"
		return false
	var policy: Dictionary = parsed
	if (
		str(policy.get("schema", "")) != "hardcore.monster_ground_slot_group_policy.runtime.v1"
		or str(policy.get("authority_id", "")) != "monster.ground_slot_groups.runtime.v1"
		or str(policy.get("status", "")) != "PRODUCTION_ACTIVE"
		or not bool(policy.get("production_active", false))
		or str(policy.get("identity_key", "")) != "canonical_monster_classification"
	):
		load_error = "monster_ground_slot_group_policy_contract_invalid"
		return false
	var groups_value: Variant = policy.get("groups", null)
	if not groups_value is Dictionary:
		load_error = "monster_ground_slot_group_policy_groups_invalid"
		return false
	var groups: Dictionary = groups_value
	for expected: Dictionary in [
		{"name": "ordinary", "limit": 6},
		{"name": "elite", "limit": 9},
		{"name": "boss", "limit": 12},
	]:
		var group_value: Variant = groups.get(expected.name, null)
		if (
			not group_value is Dictionary
			or _dpv2_json_integer(group_value.get("ground_slot_limit", null)) != expected.limit
		):
			load_error = "monster_ground_slot_group_policy_limit_invalid:%s" % expected.name
			return false
	if groups.size() != 3:
		load_error = "monster_ground_slot_group_policy_group_set_invalid"
		return false
	if policy.get("resolution_order", null) != ["canonical_monster_id_override", "canonical_monster_classification"]:
		load_error = "monster_ground_slot_group_policy_resolution_order_invalid"
		return false
	var overrides_value: Variant = policy.get("exact_id_group_overrides", null)
	if not overrides_value is Dictionary:
		load_error = "monster_ground_slot_group_policy_overrides_invalid"
		return false
	for raw_id: Variant in overrides_value:
		var id_text := str(raw_id)
		var group_value: Variant = overrides_value[raw_id]
		if (not raw_id is String or not id_text.is_valid_int()
			or str(int(id_text)) != id_text or not _monsters_by_id.has(int(id_text))
			or not group_value is String or not groups.has(group_value)):
			load_error = "monster_ground_slot_group_policy_override_invalid:%s" % id_text
			return false
	var source_authority: Variant = policy.get("source_authority", null)
	if not source_authority is Dictionary:
		load_error = "monster_ground_slot_group_policy_source_authority_invalid"
		return false
	if (
		str(source_authority.get("path", ""))
			!= "assets/data/drop/monster_ground_slot_group_policy.source.json"
		or str(source_authority.get("schema", ""))
			!= "hardcore.monster_ground_slot_group_policy.source.v1"
		or str(source_authority.get("sha256_lf", "")).to_upper()
			!= _sha256_lf_file("res://assets/data/drop/monster_ground_slot_group_policy.source.json")
	):
		load_error = "monster_ground_slot_group_policy_source_hash_invalid"
		return false
	monster_ground_slot_group_policy = policy
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
	content_query_core()._load_service_item_catalog()


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
		DPV2_VERIFIED_PROFILE_AUTHORITY_PATH,
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
		"verified_profile_authority": DPV2_VERIFIED_PROFILE_AUTHORITY_PATH,
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
		) != 15
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
		or _dpv2_json_integer(summary.get("compiled_slots", null)) != 7611
	):
		load_error = "dpv2_direct_baseline_summary_count_invalid"
		return false
	var origin_counts_value: Variant = summary.get("baseline_origin_counts", null)
	if not origin_counts_value is Dictionary:
		load_error = "dpv2_direct_baseline_origin_counts_invalid"
		return false
	var origin_counts: Dictionary = origin_counts_value
	if (
		origin_counts.size() != 3
		or _dpv2_json_integer(origin_counts.get("VERIFIED_21CQ_PROFILE_V505", null)) != 7352
		or _dpv2_json_integer(origin_counts.get("LEGACY_21CQ_MONITEMS", null)) != 190
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
			if origin not in ["VERIFIED_21CQ_PROFILE_V505", "LEGACY_21CQ_MONITEMS", "PROJECT_EXTENSION"]:
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
		or compiled_slot_count != 7611
		or origin_totals != {"VERIFIED_21CQ_PROFILE_V505": 7352, "LEGACY_21CQ_MONITEMS": 190, "PROJECT_EXTENSION": 69}
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
	dpv2_single_player_item_boost_classification = {}
	dpv2_single_player_effective_probability = {}
	dpv2_single_player_drop_boost_loaded = false
	_dpv2_spb_effective_by_uid.clear()
	var ledger_paths := (
		spb_ledger_paths_override
		if not spb_ledger_paths_override.is_empty()
		else PackedStringArray([
			DPV2_SINGLE_PLAYER_DROP_BOOST_PATH,
			DPV2_SINGLE_PLAYER_ITEM_BOOST_CLASSIFICATION_PATH,
			DPV2_SINGLE_PLAYER_EFFECTIVE_PROBABILITY_PATH,
		])
	)
	for path: String in ledger_paths:
		if not FileAccess.file_exists(path):
			load_error = "spb_effective_probability_authority_missing:%s" % path
			return false
	var authority_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_SINGLE_PLAYER_DROP_BOOST_PATH)
	)
	var classification_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_SINGLE_PLAYER_ITEM_BOOST_CLASSIFICATION_PATH)
	)
	var effective_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(DPV2_SINGLE_PLAYER_EFFECTIVE_PROBABILITY_PATH)
	)
	if (
		not authority_value is Dictionary
		or not classification_value is Dictionary
		or not effective_value is Dictionary
	):
		load_error = "spb_effective_probability_authority_invalid_json"
		return false
	var authority: Dictionary = authority_value
	var classification_authority: Dictionary = classification_value
	var effective: Dictionary = effective_value
	if not DPV2RepairV5.verify_documents(authority, effective):
		load_error = "spb_v5_sealed_documents_mismatch"
		return false
	if (
		str(classification_authority.get("schema", ""))
			!= "hardcore.dpv2.single_player_item_boost_classification.v1"
		or str(classification_authority.get("authority_id", ""))
			!= "dpv2.single_player_item_boost_classification.v1"
		or str(classification_authority.get("status", ""))
			!= "PRODUCTION_CLASSIFICATION_AUTHORITY"
		or not bool(classification_authority.get("production_active", false))
		or str(classification_authority.get("identity_key", "")) != "canonical_item_id"
	):
		load_error = "spb_item_boost_classification_contract_invalid"
		return false
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
	var classification_records_value: Variant = classification_authority.get(
		"records", null
	)
	if not classification_records_value is Array or classification_records_value.size() != 233:
		load_error = "spb_item_boost_classification_cardinality_invalid"
		return false
	var expected_classification_counts := {
		"EQUIPMENT": 167,
		"RARE_FUNCTIONAL_CONSUMABLE": 14,
		"COMMON_RECOVERY": 10,
		"BYPASS_UNCLASSIFIED": 42,
	}
	var classification_counts: Dictionary = {}
	var classification_by_id: Dictionary = {}
	for raw_classification: Variant in classification_records_value:
		if not raw_classification is Dictionary:
			load_error = "spb_item_boost_classification_record_invalid"
			return false
		var classification_record: Dictionary = raw_classification
		var item_id := _dpv2_json_integer(
			classification_record.get("canonical_item_id", null)
		)
		var classification_name := str(classification_record.get("classification", ""))
		var evidence_value: Variant = classification_record.get("evidence", null)
		var human_frozen_value: Variant = classification_record.get("human_frozen", null)
		if (
			item_id <= 0
			or classification_by_id.has(item_id)
			or not expected_classification_counts.has(classification_name)
			or str(classification_record.get("canonical_item_name", "")).is_empty()
			or str(classification_record.get("reason", "")).is_empty()
			or not evidence_value is Array
			or evidence_value.is_empty()
			or not human_frozen_value is bool
			or not bool(human_frozen_value)
		):
			load_error = "spb_item_boost_classification_record_invalid"
			return false
		for evidence_entry: Variant in evidence_value:
			if str(evidence_entry).is_empty():
				load_error = "spb_item_boost_classification_evidence_invalid"
				return false
		classification_by_id[item_id] = classification_record
		classification_counts[classification_name] = (
			int(classification_counts.get(classification_name, 0)) + 1
		)
	var direct_item_ids: Dictionary = {}
	for indexed_value: Variant in _dpv2_direct_slot_by_uid.values():
		if not indexed_value is Dictionary:
			continue
		var indexed_slot_value: Variant = indexed_value.get("slot", null)
		if indexed_slot_value is Dictionary and indexed_slot_value.has("canonical_item_id"):
			direct_item_ids[_dpv2_json_integer(indexed_slot_value.canonical_item_id)] = true
	# V5.0.5b: classification authority is canonical-item-wide.
	# The current monster-drop baseline may use only a subset of canonical items.
	if classification_by_id.size() != _dpv2_direct_item_by_id.size():
		load_error = "spb_item_boost_classification_identity_closure_invalid"
		return false
	for item_id: Variant in classification_by_id:
		if not _dpv2_direct_item_by_id.has(item_id):
			load_error = "spb_item_boost_classification_identity_closure_invalid"
			return false
	for item_id: Variant in direct_item_ids:
		if not classification_by_id.has(item_id):
			load_error = "spb_item_boost_classification_identity_closure_invalid"
			return false
	for key: String in expected_classification_counts:
		if int(classification_counts.get(key, 0)) != expected_classification_counts[key]:
			load_error = "spb_item_boost_classification_count_invalid:%s" % key
			return false
	var classification_summary_value: Variant = classification_authority.get("summary", null)
	if not classification_summary_value is Dictionary:
		load_error = "spb_item_boost_classification_summary_invalid"
		return false
	var classification_summary: Dictionary = classification_summary_value
	var declared_classification_counts: Variant = classification_summary.get(
		"classification_counts", null
	)
	if (
		_dpv2_json_integer(classification_summary.get("canonical_items", null)) != 233
		or _dpv2_json_integer(
			classification_summary.get("duplicate_canonical_item_ids", null)
		) != 0
		or _dpv2_json_integer(
			classification_summary.get("human_frozen_records", null)
		) != 233
		or not declared_classification_counts is Dictionary
	):
		load_error = "spb_item_boost_classification_summary_invalid"
		return false
	for key: String in expected_classification_counts:
		if (
			_dpv2_json_integer(declared_classification_counts.get(key, null))
				!= expected_classification_counts[key]
		):
			load_error = "spb_item_boost_classification_summary_count_invalid:%s" % key
			return false
	if (
		str((classification_by_id.get(920019, {}) as Dictionary).get("classification", ""))
			!= "RARE_FUNCTIONAL_CONSUMABLE"
		or str((classification_by_id.get(920007, {}) as Dictionary).get("classification", ""))
			!= "BYPASS_UNCLASSIFIED"
	):
		load_error = "spb_item_boost_classification_anchor_invalid"
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
		or _dpv2_json_integer(gold_multiplier_value.get("numerator", null)) != 5
		or _dpv2_json_integer(gold_multiplier_value.get("denominator", null)) != 1
		or str(production.get("required_global_drop_rate_preset", "")) != "1x"
		or _dpv2_json_integer(global_value.get("numerator", null)) != 1
		or _dpv2_json_integer(global_value.get("denominator", null)) != 1
		or str(production.get("disabled_mode", ""))
			!= "SELECT_BASE_NUMERATOR_AND_DENOMINATOR"
	):
		load_error = "spb_production_contract_invalid"
		return false
	var classification_relative_path := (
		DPV2_SINGLE_PLAYER_ITEM_BOOST_CLASSIFICATION_PATH.trim_prefix("res://")
	)
	var classification_sha256 := _sha256_lf_file(
		DPV2_SINGLE_PLAYER_ITEM_BOOST_CLASSIFICATION_PATH
	)
	if classification_sha256.is_empty():
		load_error = "spb_item_boost_classification_hash_unavailable"
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
			or str(bindings.get("item_boost_classification_path", ""))
				!= classification_relative_path
			or str(
				bindings.get("item_boost_classification_sha256_raw", "")
			).to_upper() != classification_sha256
			or _dpv2_json_integer(bindings.get("direct_slot_count", null)) != 7611
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
		"AUTO_BOOST": 5075,
		"BYPASS_COMMON_RECOVERY": 1529,
		"BYPASS_GOLD": 135,
		"BYPASS_NEW_ARMOR_BOSS": 324,
		"BYPASS_UNCLASSIFIED": 548
	}
	var expected_population_counts := {
		"blessing_oil_slots": 30,
		"common_recovery_slots": 1769,
		"equipment_candidate_slots": 4791,
		"gold_slots": 141,
		"new_armor_boss_slots": 324,
		"rare_consumable_candidate_slots": 326,
		"unclassified_candidate_slots": 584
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
			_dpv2_json_integer(summary.get("ceiling_applied_slots", null)) != 1435
			or _dpv2_json_integer(summary.get("disabled_counterfactual_mismatch", null)) != 0
			or _dpv2_json_integer(summary.get("probability_decreases", null)) != 0
			or _dpv2_json_integer(summary.get("ceiling_violations", null)) != 0
			or _dpv2_json_integer(summary.get("boost_formula_mismatch", null)) != 0
			or _dpv2_json_integer(summary.get("bypass_probability_mismatch", null)) != 0
			or _dpv2_json_integer(summary.get("duplicate_slot_collapse", null)) != 0
			or _dpv2_json_integer(summary.get("gold_amount_slots", null)) != 141
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
			or _dpv2_json_integer(summary_gold_multiplier.get("numerator", null)) != 5
			or _dpv2_json_integer(summary_gold_multiplier.get("denominator", null)) != 1
		):
			load_error = "spb_gold_amount_summary_invalid"
			return false
	if (
		_dpv2_json_integer(authority_summary.get("production_slots", null)) != 7611
		or _dpv2_json_integer(authority_summary.get("equipment_item_ids", null)) != 167
		or _dpv2_json_integer(
			authority_summary.get("rare_functional_consumable_item_ids", null)
		) != 14
		or _dpv2_json_integer(authority_summary.get("auto_boost_item_ids", null)) != 181
		or _dpv2_json_integer(effective_summary.get("records", null)) != 7611
		or _dpv2_json_integer(
			effective_summary.get("disabled_counterfactual_records", null)
		) != 7611
		or _dpv2_json_integer(effective_summary.get("base_mirror_mismatch", null)) != 0
	):
		load_error = "spb_summary_cardinality_invalid"
		return false
	var records_value: Variant = effective.get("records", null)
	if not records_value is Array or records_value.size() != 7611:
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
				or effective_gold_amount != base_gold_amount * 5
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
		var base_stage_expected := dpv2_single_player_boost_formula(
			base_numerator, base_denominator, is_auto
		)
		var expected := DPV2RepairV5.final_formula(
			record, authority.get("repair_v5_contract", {}), base_stage_expected,
			DPV2RepairV5.historical_classification(
				_dpv2_json_integer(record.get("canonical_monster_id", null)),
				canonical_monster_classification(_dpv2_json_integer(record.get("canonical_monster_id", null)))
			)
		)
		if not bool(expected.get("ok", false)):
			load_error = "spb_v5_formula_contract_invalid"
			return false
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
		or _dpv2_spb_effective_by_uid.size() != 7611
		or ceiling_count != 1435
	):
		load_error = "spb_effective_probability_closure_invalid"
		return false
	for key: String in expected_policy_counts:
		if int(policy_counts.get(key, 0)) != expected_policy_counts[key]:
			load_error = "spb_effective_probability_policy_closure_invalid:%s" % key
			return false
	dpv2_single_player_drop_boost = authority
	dpv2_single_player_item_boost_classification = classification_authority
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
		# This frozen ledger describes drop eligibility when it was compiled.
		# Empty-drop monsters may now spawn; that must not invent drop slots.
		if runtime_allowed == DPV2_RUNTIME_DISABLED_IDS.has(monster_id):
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
	return content_query_core()._dpv2_json_integer(value)


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


func _sha256_raw_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(file.get_buffer(file.get_length()))
	return context.finish().hex_encode().to_upper()


func _load_equipment_price_candidates() -> void:
	content_query_core()._load_equipment_price_candidates()


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
	return content_query_core().merchant_stock(stock_key)


func merchant_context(stock_key: String) -> Dictionary:
	return content_query_core().merchant_context(stock_key)


func item_usage_summary(item_name: String, player_level := -1) -> Dictionary:
	# Return canonical player-facing use values for a catalog item. The service
	# catalog is authoritative; UI must not guess from names or render equipment
	# template fields for consumables.
	_original_main_callback_ledger["item_usage_summary"] = int(_original_main_callback_ledger.get("item_usage_summary",0)) + 1
	var original_result: Variant = _original_source_game_data_item_usage_summary(item_name,player_level)
	_original_main_callback_ledger["item_usage_summary"] -= 1
	return original_result


func _original_source_game_data_item_usage_summary(item_name: String, player_level := -1) -> Dictionary:
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
	return content_query_core().potion_recovery_profile(player_level, restore_health, restore_mana, use_effect)


func merchant_context_by_id(merchant_id: String) -> Dictionary:
	return content_query_core().merchant_context_by_id(merchant_id)


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


func _append_formal_map_identities() -> bool:
	if not FileAccess.file_exists(FORMAL_MAP_IDENTITY_REGISTRY_PATH):
		load_error = "formal_map_identity_registry_missing"
		return false
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(FORMAL_MAP_IDENTITY_REGISTRY_PATH)
	)
	if (
		not parsed is Dictionary
		or str(parsed.get("contract_id", ""))
			!= "hardcore.formal_map_identity.v1"
	):
		load_error = "formal_map_identity_registry_invalid"
		return false
	var identity_maps: Variant = parsed.get("maps", null)
	if not identity_maps is Array or identity_maps.size() != 67:
		load_error = "formal_map_identity_count_invalid"
		return false
	var occupied_ids: Dictionary = {}
	var formal_keys: Dictionary = {}
	for raw_map: Variant in maps:
		if raw_map is Dictionary:
			occupied_ids[int(raw_map.get("mapId", -1))] = true
	for raw_identity: Variant in identity_maps:
		if not raw_identity is Dictionary:
			load_error = "formal_map_identity_entry_invalid"
			return false
		var identity: Dictionary = raw_identity
		var map_key := str(identity.get("map_id", ""))
		var runtime_map_id := int(identity.get("runtime_map_id", -1))
		var display_name := str(identity.get("display_name", "")).strip_edges()
		if (
			map_key.is_empty()
			or display_name.is_empty()
			or runtime_map_id < 910001
			or runtime_map_id > 918006
			or occupied_ids.has(runtime_map_id)
			or formal_keys.has(map_key)
		):
			load_error = "formal_map_identity_collision"
			return false
		maps.append({
			"mapId": runtime_map_id,
			"name": display_name,
			"formalMapKey": map_key,
			"legacyMapId": str(identity.get("legacy_map_id", "")),
			"legacyRuntimeMapId": int(
				identity.get("legacy_runtime_map_id", -1)
			),
			"availabilityDefault": true,
			"runtimeAuthority": "hardcore.formal_map_identity.v1",
		})
		occupied_ids[runtime_map_id] = true
		formal_keys[map_key] = true
	database["maps"] = maps
	return true


func _build_indexes() -> bool:
	# Explicit detached index construction uses the same local lookup owner as
	# the full loader. Public reads remain closed after construction/failure.
	var previous_build_state := _database_build_in_progress
	_database_build_in_progress = true
	var success := _build_database_indexes()
	_database_build_in_progress = previous_build_state
	return success


func _build_database_indexes() -> bool:
	_item_category_error = ""
	if not ItemCategories.ensure_loaded():
		load_error = "item_category_authority_not_ready:" + ItemCategories.last_error
		return false
	_items_by_name.clear()
	_items_by_id.clear()
	_maps_by_id.clear()
	_maps_by_name.clear()
	for entry: Variant in maps:
		if not entry is Dictionary:
			continue
		_maps_by_id[int(entry.get("mapId", -1))] = entry
		var map_name := str(entry.get("name", ""))
		if (
			not _maps_by_name.has(map_name)
			or not str(entry.get("formalMapKey", "")).is_empty()
		):
			_maps_by_name[map_name] = entry
	for entry: Variant in items:
		if entry is Dictionary:
			if not ItemCategories.attach_source_category(entry):
				_item_category_error = "unknown_primary_equipment_category"
				continue
			var item_name := str(entry.get("name", ""))
			_items_by_name[item_name] = entry
			var item_id := _stable_item_id(entry)
			if item_id >= 0:
				_items_by_id[item_id] = entry
	if not _build_item_catalog():
		# A skill-book rejection must not leave the catalog or its lookup maps
		# visible as a partially published index.  The caller will return the
		# stable load_error set by _build_skill_book_index().
		_items_by_name.clear()
		_items_by_id.clear()
		item_catalog.clear()
		_catalog_by_name.clear()
		_catalog_by_item_id.clear()
		_catalog_by_service_index.clear()
		_catalog_by_currency_id.clear()
		_price_by_name.clear()
		_price_by_item_id.clear()
		_price_by_service_index.clear()
		if load_error.is_empty():
			load_error = "item_catalog_build_invalid"
		return false
	for relic: Dictionary in RelicSynthesisRulesScript.records():
		if not ItemCategories.attach_source_category(relic):
			_item_category_error = "unknown_relic_category"
			continue
		var relic_id := int(relic.itemId)
		var relic_name := str(relic.name)
		if _items_by_id.has(relic_id) or _items_by_name.has(relic_name):
			push_error("圣物身份与原有装备冲突：%d" % relic_id)
			continue
		_items_by_id[relic_id] = relic
		_items_by_name[relic_name] = relic
	if not _item_category_error.is_empty():
		_items_by_name.clear()
		_items_by_id.clear()
		item_catalog.clear()
		_catalog_by_name.clear()
		_catalog_by_item_id.clear()
		_catalog_by_service_index.clear()
		_catalog_by_currency_id.clear()
		_price_by_name.clear()
		_price_by_item_id.clear()
		_price_by_service_index.clear()
		load_error = _item_category_error
		return false
	_build_canonical_monster_runtime_drop_closure()
	return true


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
		# Keep the drop-closure diagnostics, but do not use loot to gate birth.
		monsters.append(entry.duplicate(true))
		if str(entry.get("classification", "")) == "boss":
			bosses.append(entry.duplicate(true))



func _apply_item_runtime_authority_overrides(record: Dictionary, _skill_names: Dictionary) -> Dictionary:
	var result: Dictionary = record.duplicate(true)
	var kind := str(result.get("kind", ""))
	var service_index := int(result.get("serviceIndex", result.get("service_index", -1)))
	var policies: Dictionary = item_runtime_authority.get("policies", {})

	if kind == "skill_book":
		var book_policy: Variant = policies.get("vanillaSkillBook", {})
		if book_policy is Dictionary:
			if book_policy.has("stackable"):
				result["stackable"] = book_policy["stackable"]
			if book_policy.has("maxStack"):
				result["maxStack"] = book_policy["maxStack"]
			var description_suffix := str(book_policy.get("descriptionSuffix", ""))
			if not description_suffix.is_empty():
				var description := str(result.get("description", "")).strip_edges()
				if description_suffix not in description:
					result["description"] = (
						description_suffix
						if description.is_empty()
						else "%s\n%s" % [description, description_suffix]
					)

	var overrides_by_index: Variant = policies.get("serviceOverridesByIndex", {})
	if overrides_by_index is Dictionary:
		var override_key := str(service_index)
		if overrides_by_index.has(override_key):
			var override_entry: Variant = overrides_by_index[override_key]
			if override_entry is Dictionary:
				for key: String in override_entry:
					result[key] = override_entry[key]

	return result
func _build_item_catalog() -> bool:
	item_catalog.clear()
	_catalog_by_name.clear()
	_catalog_by_item_id.clear()
	_catalog_by_service_index.clear()
	_catalog_by_currency_id.clear()
	_build_price_index()
	var skill_names := {}
	for skill: Variant in skills:
		if skill is Dictionary:
			skill_names[str(skill.get("skillName", ""))] = true
	for equipment: Variant in items:
		if not equipment is Dictionary:
			continue
		var record: Dictionary = EquipmentRulesScript.enrich_catalog_record(equipment, get_item_shop_price)
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
		if int(service_item.get("serviceIndex", -1)) == 828 and str(service_item.get("name", "")) == "黑铁矿":
			continue
		var service_record: Dictionary = service_item.duplicate(true)
		if str(service_record.get("name", "")) in ["沃玛号角", "祖玛头像"]:
			service_record["kind"] = "quest_item"
			service_record["category"] = "任务物品"
		var override_record := _apply_item_runtime_authority_overrides(service_record, skill_names)
		if str(override_record.get("kind", "")) == "skill_book":
			var target: Variant = override_record.get("learnSkillId", "")
			if not target is String or EntityRegistry.resolve(target, "skill").is_empty():
				override_record["usable"] = false
				override_record["useEffect"] = "skill_not_in_current_class_catalog"
		_register_catalog_item(override_record)
	for special_item: Variant in service_item_catalog.get("runtimeSpecials", {}).values():
		if special_item is Dictionary:
			var override_special := _apply_item_runtime_authority_overrides(special_item.duplicate(true), skill_names)
			_register_catalog_item(override_special)



		# ITEM-P0C-FULL: register runtime authority newItems before fallback.
	for authority_item: Variant in item_runtime_authority.get("newItems", []):
		if authority_item is Dictionary:
			_register_catalog_item((authority_item as Dictionary).duplicate(true))
	# Purity is a stable numeric identity. Keep all eleven entries ID-addressed;
	# a name-only lookup must never choose an arbitrary purity or the retired ore.
	for black_iron: Dictionary in EnhancementBlackIron.records():
		if not ItemCategories.attach_source_category(black_iron):
			_item_category_error = "unknown_black_iron_category"
			continue
		var iron_id := int(black_iron.itemId)
		if _catalog_by_item_id.has(iron_id):
			push_error("锻造黑铁矿 ID 与现有物品冲突：%d" % iron_id)
			continue
		_catalog_by_item_id[iron_id] = black_iron
		item_catalog.append(black_iron)
	var relic_fragment := AncientRelicFragmentScript.record()
	if not relic_fragment.is_empty():
		if _catalog_by_item_id.has(AncientRelicFragmentScript.ITEM_ID) or _catalog_by_name.has(AncientRelicFragmentScript.ITEM_NAME):
			push_error("远古圣物碎片身份与现有物品冲突：%d" % AncientRelicFragmentScript.ITEM_ID)
		else:
			_register_catalog_item(relic_fragment)
	for relic: Dictionary in RelicSynthesisRulesScript.records():
		var relic_id := int(relic.itemId)
		if _catalog_by_item_id.has(relic_id) or _catalog_by_name.has(str(relic.name)):
			push_error("圣物目录身份冲突：%d" % relic_id)
			continue
		_register_catalog_item(relic)

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
		if item_name.is_empty() or canonical_name == "黑铁矿" or _catalog_by_name.has(canonical_name):
			continue
		_register_catalog_item(_make_runtime_item(item_name, skill_names))
	# Catalog category/kind is the player-facing canonical classification. Price
	# records keep the database identity and adopt only these non-price fields.
	for item_name: String in _price_by_name.keys():
		var catalog: Dictionary = _catalog_by_name.get(item_name, {})
		if not catalog.is_empty():
			_price_by_name[item_name]["kind"] = str(catalog.get("kind", _price_by_name[item_name].get("kind", "unknown")))
			_price_by_name[item_name]["category"] = str(catalog.get("category", _price_by_name[item_name].get("category", "")))
			_price_by_name[item_name]["category_id"] = str(catalog.get("category_id", ""))
	return _build_skill_book_index()


func _skill_book_index_error(code: String, detail: String = "") -> bool:
	load_error = code if detail.is_empty() else "%s:%s" % [code, detail]
	return false


func _build_skill_book_index() -> bool:
	_skill_books_by_skill = {}
	var candidate := {}
	var canonical_skill_ids := PackedStringArray()
	for skill_alias: String in CanonicalSkills.skill_ids():
		var skill_id := CanonicalSkills.entity_skill_id(skill_alias)
		if skill_id.is_empty() or canonical_skill_ids.has(skill_id):
			return _skill_book_index_error("skill_book_index_canonical_skill_identity_invalid", skill_alias)
		canonical_skill_ids.append(skill_id)
	var validated_equipment_grants := {}
	for grant: Dictionary in EquipmentGrantedSkillRules.grant_definitions():
		var grant_id := str(grant.get("skill_id", ""))
		if grant_id.is_empty() or not canonical_skill_ids.has(grant_id):
			return _skill_book_index_error("skill_book_index_equipment_grant_invalid", grant_id)
		if not bool(grant.get("equipment_granted", false)):
			return _skill_book_index_error("skill_book_index_equipment_grant_marker_invalid", grant_id)
		validated_equipment_grants[grant_id] = true
	for item: Dictionary in item_catalog:
		if str(item.get("kind", "")) != "skill_book" or not item.get("usable", true): continue
		var target: Variant = item.get("learnSkillId", "")
		var numeric := _stable_item_id(item)
		var book := EntityRegistry.canonical(EntityRegistry.from_legacy("item", numeric) if numeric >= 0
			else EntityRegistry.from_legacy("service_item", _service_index(item)))
		if not target is String or EntityRegistry.resolve(target, "skill").is_empty() or book.is_empty():
			return _skill_book_index_error("skill_book_index_relation_invalid")
		if candidate.has(target) and candidate[target] != book:
			return _skill_book_index_error("skill_book_index_duplicate_target", target)
		candidate[target] = book
	for target: String in candidate:
		if not canonical_skill_ids.has(target):
			return _skill_book_index_error("skill_book_index_unknown_target", target)
		if validated_equipment_grants.has(target):
			return _skill_book_index_error("skill_book_index_equipment_grant_conflict", target)
	var required_book_targets := canonical_skill_ids.size() - validated_equipment_grants.size()
	if candidate.size() != required_book_targets:
		return _skill_book_index_error("skill_book_index_incomplete")
	candidate.make_read_only()
	_skill_books_by_skill = candidate
	return true


func _build_price_index() -> void:
	content_query_core()._build_price_index()


func _apply_exact_user_price_override(item_id: int) -> void:
	content_query_core()._apply_exact_user_price_override(item_id)


func _register_price_record(raw: Variant) -> void:
	content_query_core()._register_price_record(raw)


func _price_candidate_owner(row: Variant) -> Dictionary:
	return content_query_core()._price_candidate_owner(row)


func _register_catalog_item(record: Dictionary) -> void:
	if not ItemCategories.attach_source_category(record):
		_item_category_error = "unknown_catalog_category"
		return
	var item_name := str(record.get("name", ""))
	if item_name.is_empty() or _catalog_by_name.has(item_name):
		return
	# Import the exact legacy authoring identity once for every catalog source.
	# The primary gold record is a service special, not a fallback item.
	if record.get("kind") == "currency" and not record.has("currency_id"):
		var gold_identity := EntityRegistry.resolve("hc.currency.gold", "currency")
		if item_name == str(gold_identity.get("display_name", "")):
			record["currency_id"] = str(gold_identity.get("id", ""))
	# This is an index of the existing catalog, never a second currency owner.
	if record.has("currency_id"):
		var currency: Variant = record.currency_id
		if not currency is String or record.get("kind") != "currency" \
			or EntityRegistry.resolve(currency, "currency").is_empty() or _catalog_by_currency_id.has(currency):
			_item_category_error = "unknown_or_duplicate_currency_identity"
			return
		_catalog_by_currency_id[currency] = record
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
		record.merge({
			"kind": "skill_book",
			"category": "技能书",
			"stackable": false,
			"maxStack": 1,
			"useEffect": "learn_skill",
			"description": "使用技能书可以使对应技能等级+1，技能最高3级。",
		})
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
	return content_query_core().canonical_monster_id(raw_value)


func get_canonical_monster_entry(
	monster_id: int,
	use_context := "runtime"
) -> Dictionary:
	return content_query_core().get_canonical_monster_entry(monster_id, use_context)


func get_monster_by_id(monster_id: int) -> Dictionary:
	return content_query_core().get_monster_by_id(monster_id)


func canonical_monster_classification(monster_id: int) -> String:
	return content_query_core().canonical_monster_classification(monster_id)


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
	return content_query_core().is_dpv2_direct_baseline_loaded()


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
	return content_query_core().dpv2_direct_item_identity(canonical_item_id)


func dpv2_direct_resolve_slot_reward(slot: Dictionary) -> Dictionary:
	return content_query_core().dpv2_direct_resolve_slot_reward(slot)


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
			or effective_gold_amount != base_gold_amount * 5
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
	return content_query_core().dpv2_ground_slot_limit()


func dpv2_ground_slot_limit_for_monster(monster_id: int) -> int:
	return content_query_core().dpv2_ground_slot_limit_for_monster(monster_id)


func dpv2_source_slot_gate() -> Dictionary:
	return content_query_core().dpv2_source_slot_gate()


func _positive_gcd(left: int, right: int) -> int:
	var a := absi(left)
	var b := absi(right)
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return maxi(1, a)


func get_map_by_id(map_id: int) -> Dictionary:
	return content_query_core().get_map_by_id(map_id)


func service_runtime_map_id(service_map_id: int) -> int:
	return content_query_core().service_runtime_map_id(service_map_id)


func get_service_map_by_id(service_map_id: int) -> Dictionary:
	return get_map_by_id(service_runtime_map_id(service_map_id))


func get_map(map_name: String) -> Dictionary:
	return content_query_core().get_map(map_name)


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
	return content_query_core().get_item(item_name)


func player_base_appearance(profession: String, gender: String) -> Dictionary:
	var profession_id := ProfessionRules.profession_id(profession)
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
	return content_query_core().get_item_record(item_ref)


# New typed entry point delegates every attribute to the existing consumer.
# Display strings never participate in this lookup.
func get_entity_record(entity_id: String) -> Dictionary:
	return content_query_core().get_entity_record(entity_id)


func item_entity_id(item_ref: Variant) -> String:
	return content_query_core().item_entity_id(item_ref)


func item_category_id(item_ref: Variant) -> String:
	if item_ref is String:
		if EntityRegistry.resolve(item_ref).get("kind") not in ["item", "service_item"]: return ""
	elif item_ref is Dictionary:
		var typed: bool = item_ref.has("format_version")
		for key: String in ["item_id", "itemId", "service_index", "serviceIndex"]:
			if not item_ref.has(key): continue
			typed = true
			var number: Variant = item_ref[key]
			if not (number is int or number is float) or not is_finite(float(number)) \
				or float(number) != floor(float(number)) or number < 0 or number > 2147483647: return ""
		if not typed: return ""
	else:
		return ""
	var record := _item_record_for_read(item_ref)
	if record.is_empty(): return ""
	var category := ItemCategories.category_for_record(record)
	if item_ref is Dictionary and item_ref.has("category_id") and item_ref.category_id != category: return ""
	return category


func get_item_art_path(item_ref: Variant, field := "inventoryIcon") -> String:
	# UI icon refreshes need one string, not a deep copy of source provenance,
	# every animation and all equipment rules. Resolve through the same indexes.
	var record := _item_record_for_read(item_ref)
	var art: Variant = record.get("art", {})
	if not art is Dictionary:
		return ""
	var source: Variant = art.get(field, {})
	return str(source.get("path", "")) if source is Dictionary else str(source)


func get_item_art_display_size(item_ref: Variant, field := "inventoryIcon") -> Vector2:
	var record := _item_record_for_read(item_ref)
	var art: Variant = record.get("art", {})
	var source: Variant = art.get(field, {}) if art is Dictionary else {}
	if not source is Dictionary:
		return Vector2.ZERO
	var values: Variant = source.get("displaySize", [])
	if not values is Array or (values as Array).size() != 2:
		return Vector2.ZERO
	var result := Vector2(float(values[0]), float(values[1]))
	return result if result.x > 0.0 and result.y > 0.0 else Vector2.ZERO


func get_item_rules_record(item_ref: Variant) -> Dictionary:
	return content_query_core().get_item_rules_record(item_ref)


func _item_record_for_read(item_ref: Variant) -> Dictionary:
	return content_query_core()._item_record_for_read(item_ref)


func _valid_explicit_item_reference(value: Variant, runtime_membership := true) -> bool:
	return content_query_core()._valid_explicit_item_reference(value, runtime_membership)


func validate_item_drop_instance(instance: Dictionary) -> bool:
	return content_query_core().validate_item_drop_instance(instance)


func get_item_shop_price(item_ref: Variant) -> int:
	return content_query_core().get_item_shop_price(item_ref)


func get_item_price_records_by_name(item_names: Array) -> Dictionary:
	if not is_loaded() and not _database_build_in_progress:
		return {}
	# Legacy inventory records have names only. Resolve the existing exact,
	# ambiguity-rejecting name contract once per batch, never once per row.
	var requested: Dictionary = {}
	for value: Variant in item_names:
		requested[_canonical_item_name(str(value))] = -1
	var ambiguous: Dictionary = {}
	for raw: Variant in items:
		if not raw is Dictionary: continue
		var name_text := _canonical_item_name(str(raw.get("name", "")))
		if not requested.has(name_text): continue
		var item_id := _stable_item_id(raw)
		if item_id < 0: continue
		var previous := int(requested[name_text])
		if previous >= 0 and previous != item_id: ambiguous[name_text] = true
		requested[name_text] = item_id
	for name_text: String in ambiguous: requested[name_text] = -1
	var result: Dictionary = {}
	for value: Variant in item_names:
		result[str(value)] = _get_item_price_record(value, requested)
	return result


func get_item_price_record(item_ref: Variant) -> Dictionary:
	return content_query_core().get_item_price_record(item_ref)


func _get_item_price_record(item_ref: Variant, name_id_snapshot: Dictionary = {}) -> Dictionary:
	return content_query_core()._get_item_price_record(item_ref, name_id_snapshot)


func _ensure_price_index() -> void:
	content_query_core()._ensure_price_index()


func _canonical_item_name(item_name: String) -> String:
	return content_query_core()._canonical_item_name(item_name)


func _stable_identity(item_ref: Variant) -> Dictionary:
	return content_query_core()._stable_identity(item_ref)


func _stable_item_id(record: Dictionary) -> int:
	return content_query_core()._stable_item_id(record)


func _service_index(record: Dictionary) -> int:
	return content_query_core()._service_index(record)


func _parse_stable_number(value: Variant) -> int:
	return content_query_core()._parse_stable_number(value)


func _item_id_for_name(item_name: String) -> int:
	return content_query_core()._item_id_for_name(item_name)


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


func get_skill(skill_ref: String, skill_level := 0) -> Dictionary:
	return content_query_core().get_skill(skill_ref, skill_level)


func skill_book_entity_id(skill_id: String) -> String:
	return content_query_core().skill_book_entity_id(skill_id)


func skill_book_skill_id(item_ref: Variant) -> String:
	return content_query_core().skill_book_skill_id(item_ref)


func canonical_item_kind(item_id: int) -> String:
	var record: Variant = _catalog_by_item_id.get(item_id, null)
	if not record is Dictionary:
		return ""
	return str((record as Dictionary).get("kind", ""))


func get_bich_quest(quest_id: String) -> Dictionary:
	return content_query_core().get_bich_quest(quest_id)


func get_bich_quests() -> Array:
	return content_query_core().get_bich_quests()


func bich_quest_count() -> int:
	return _bich_quests_by_id.size()


func service_setup_value(key: String, fallback: Variant = null) -> Variant:
	return content_query_core().service_setup_value(key, fallback)


func service_exp_to_next_level(level_value: int) -> int:
	return content_query_core().service_exp_to_next_level(level_value)


func service_home_map_id(red_name := false) -> int:
	return content_query_core().service_home_map_id(red_name)


func service_home_runtime_map_id(red_name := false) -> int:
	return content_query_core().service_home_runtime_map_id(red_name)


func service_home_point(red_name := false) -> Vector2i:
	return content_query_core().service_home_point(red_name)


func service_profession_stats(profession_name: String, level_value: int) -> Dictionary:
	# Compatibility API, same authoritative computation as every other consumer.
	return ProfessionRules.stats_for_level(profession_name, level_value)


func get_profession_skills(profession: String) -> Array:
	return content_query_core().get_profession_skills(profession)


func summary_text() -> String:
	if not load_error.is_empty():
		return load_error
	return "地图 %d｜怪物 %d｜Boss %d｜物品 %d｜技能 %d｜掉落槽 %d" % [
		maps.size(), monsters.size(), bosses.size(), item_catalog.size(), skills.size(), drops.size()
	]

# DPV2_V505_RUNTIME_SEAL: exact generated profile/ledger cardinalities and hashes above.

# UI-L1 SUPPLEMENT BEGIN -- controlled extra members

var _ui_l1_price_fast_hits := 0
var _ui_l1_price_slow_calls := 0
var _ui_l1_price_maintenance_count := 0

func _ui_l1_get_item_price_record_slow(item_ref: Variant) -> Dictionary:
	return content_query_core()._ui_l1_get_item_price_record_slow(item_ref)


# UI-L1 SUPPLEMENT END
