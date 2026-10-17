extends RefCounted

## The production GameData query bodies live here once. Legacy fields are
## read live through the main adapter; simulation owns a captured field store.
const Fields := preload("res://scripts/gameplay/content/content_field_store.gd")
const Graph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const Gate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const ContentPort := preload("res://scripts/gameplay/profile/profile_content_port.gd")
const EntityRegistry := preload("res://scripts/identity/entity_registry.gd")
const ItemCategories := preload("res://scripts/identity/item_category_identity.gd")
const ItemExtensionCodec := preload("res://scripts/items/item_extension_codec.gd")
const SocketGemRules := preload("res://scripts/items/socket_gem_rules.gd")
const RuneItemRules := preload("res://scripts/items/rune_item_rules.gd")
const CanonicalSkills := preload("res://scripts/skills/skill_data_loader.gd")
const PricingServiceScript := preload("res://scripts/pricing_service.gd")
const rank_rules := preload("res://scripts/skills/skill_rank_resolver.gd")
const summon_rules := preload("res://scripts/taoist_combat_math.gd")
const SERVICE_RUNTIME_MAP_ALIASES := {0: 910001}
static var _preloaded_script: WeakRef

static func prepare_factory(script: Script) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
	if script == null or script.resource_path != "res://scripts/gameplay/content/content_query_core.gd": return false
	if _preloaded_script == null: _preloaded_script = weakref(script)
	return true

var _owner_thread_id := OS.get_thread_caller_id()
var _state: RefCounted
var _content_ref: WeakRef
var simulation_owner := false
var source_revision := 0
var published_source_hash := ""
var catalog_lease: Dictionary = {}

func _owned() -> bool:
	return OS.get_thread_caller_id() == _owner_thread_id and (not simulation_owner or Gate.owns_reader(catalog_lease))

func _init(state: RefCounted, simulation := false) -> void:
	_state = state
	simulation_owner = simulation

func bind_content_port(port: ContentPort) -> void:
	if not _owned(): return
	_content_ref = weakref(port)

func _content() -> ContentPort:
	var port: ContentPort = _content_ref.get_ref() if _content_ref != null else null
	assert(port != null, "content port lifetime must cover its query core")
	return port

func _item_instance_rules() -> Variant:
	return _content().rules.get("item_instances")

func _profession_rules() -> Variant:
	return _content().rules.get("professions")

func _pricing_content() -> ContentPort:
	return _content() if simulation_owner else null

static func from_snapshot(snapshot: Dictionary) -> RefCounted:
	if snapshot.get("contract_id") != "content.query.snapshot.v1" or not snapshot.get("fields") is Dictionary or not snapshot.get("catalog_lease") is Dictionary:
		return null
	var token: Dictionary = snapshot.get("catalog_lease", {})
	if not Gate.owns_reader(token): return null
	# Validate before hashing: malformed objects or cycles never reach the
	# serializer, and incomplete graphs never reach typed field getters.
	if not Graph.validate(snapshot).success: return null
	for field: String in STATE_FIELDS:
		if not snapshot.fields.has(field): return null
	if not snapshot.get("database_revision") is int or snapshot.database_revision < 0: return null
	var growth_path: Variant = snapshot.fields.profession_growth_source_path
	if not growth_path is String or growth_path.is_empty(): return null
	if Graph.fingerprint(snapshot.fields) != snapshot.get("fields_sha256"): return null
	if _preloaded_script == null: return null
	var script: Script = _preloaded_script.get_ref()
	if script == null: return null
	var core: RefCounted = script.new(Fields.new(snapshot.fields, token), true)
	core.source_revision = int(snapshot.get("database_revision", -1))
	core.published_source_hash = str(snapshot.fields_sha256)
	core.catalog_lease = token
	return core

static func create_content_port(snapshot: Dictionary) -> ContentPort:
	var core := from_snapshot(snapshot)
	if core == null: return null
	var port := ContentPort.new(core, true)
	core.bind_content_port(port)
	return port

func diagnostics() -> Dictionary:
	if not _owned(): return {}
	return {"fast_hits": _ui_l1_price_fast_hits, "slow_calls": _ui_l1_price_slow_calls,
		"maintenance": _ui_l1_price_maintenance_count}

const STATE_FIELDS := ["service_reference", "bich_quest_chain", "service_item_catalog", "equipment_price_candidates", "merchant_catalog", "item_runtime_authority", "dpv2_direct_baseline_manifest", "dpv2_direct_baseline", "dpv2_monster_drop_semantic_authority", "monster_ground_slot_group_policy", "dpv2_direct_baseline_loaded", "items", "skills", "_item_category_error", "_initial_load_complete", "_monsters_by_id", "_items_by_name", "_maps_by_id", "_maps_by_name", "_catalog_by_name", "_catalog_by_item_id", "_catalog_by_service_index", "_catalog_by_currency_id", "_skill_books_by_skill", "_price_by_name", "_price_by_item_id", "_price_by_service_index", "_bich_quests_by_id", "_dpv2_direct_item_by_id", "_database_build_in_progress", "_ui_l1_price_fast_hits", "_ui_l1_price_slow_calls", "_ui_l1_price_maintenance_count", "dpv2_single_player_drop_boost", "profession_growth_source_path"]

const SERVICE_ITEM_CATALOG_PATH := "res://assets/data/service_item_catalog.json"

const EQUIPMENT_PRICE_CANDIDATES_PATH := "res://assets/data/equipment_price_candidates_v1.json"

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
	# 服务目录(cjlaaa)把该手镯记录为"思贝尔手镯"，运行时目录/掉落与 1.76 资料站
	# 均为"思贝儿手镯"；价格记录必须挂回运行时物品身份，否则无法估值。
	"思贝尔手镯": "思贝儿手镯",

}

var service_reference: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("service_reference")
	set(value):
		if not _owned(): return
		_state.write_field("service_reference", value)

var bich_quest_chain: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("bich_quest_chain")
	set(value):
		if not _owned(): return
		_state.write_field("bich_quest_chain", value)

var service_item_catalog: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("service_item_catalog")
	set(value):
		if not _owned(): return
		_state.write_field("service_item_catalog", value)

var equipment_price_candidates: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("equipment_price_candidates")
	set(value):
		if not _owned(): return
		_state.write_field("equipment_price_candidates", value)

var merchant_catalog: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("merchant_catalog")
	set(value):
		if not _owned(): return
		_state.write_field("merchant_catalog", value)

var item_runtime_authority: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("item_runtime_authority")
	set(value):
		if not _owned(): return
		_state.write_field("item_runtime_authority", value)

var dpv2_direct_baseline_manifest: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("dpv2_direct_baseline_manifest")
	set(value):
		if not _owned(): return
		_state.write_field("dpv2_direct_baseline_manifest", value)

var dpv2_direct_baseline: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("dpv2_direct_baseline")
	set(value):
		if not _owned(): return
		_state.write_field("dpv2_direct_baseline", value)

var dpv2_monster_drop_semantic_authority: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("dpv2_monster_drop_semantic_authority")
	set(value):
		if not _owned(): return
		_state.write_field("dpv2_monster_drop_semantic_authority", value)

var monster_ground_slot_group_policy: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("monster_ground_slot_group_policy")
	set(value):
		if not _owned(): return
		_state.write_field("monster_ground_slot_group_policy", value)

var dpv2_direct_baseline_loaded: bool:
	get:
		if not _owned(): return false
		return _state.read_field("dpv2_direct_baseline_loaded")
	set(value):
		if not _owned(): return
		_state.write_field("dpv2_direct_baseline_loaded", value)

var items: Array:
	get:
		if not _owned(): return []
		return _state.read_field("items")
	set(value):
		if not _owned(): return
		_state.write_field("items", value)

var skills: Array:
	get:
		if not _owned(): return []
		return _state.read_field("skills")
	set(value):
		if not _owned(): return
		_state.write_field("skills", value)

var _item_category_error: String:
	get:
		if not _owned(): return ""
		return _state.read_field("_item_category_error")
	set(value):
		if not _owned(): return
		_state.write_field("_item_category_error", value)

var _initial_load_complete: bool:
	get:
		if not _owned(): return false
		return _state.read_field("_initial_load_complete")
	set(value):
		if not _owned(): return
		_state.write_field("_initial_load_complete", value)

var _monsters_by_id: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_monsters_by_id")
	set(value):
		if not _owned(): return
		_state.write_field("_monsters_by_id", value)

var _items_by_name: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_items_by_name")
	set(value):
		if not _owned(): return
		_state.write_field("_items_by_name", value)

var _maps_by_id: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_maps_by_id")
	set(value):
		if not _owned(): return
		_state.write_field("_maps_by_id", value)

var _maps_by_name: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_maps_by_name")
	set(value):
		if not _owned(): return
		_state.write_field("_maps_by_name", value)

var _catalog_by_name: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_catalog_by_name")
	set(value):
		if not _owned(): return
		_state.write_field("_catalog_by_name", value)

var _catalog_by_item_id: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_catalog_by_item_id")
	set(value):
		if not _owned(): return
		_state.write_field("_catalog_by_item_id", value)

var _catalog_by_service_index: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_catalog_by_service_index")
	set(value):
		if not _owned(): return
		_state.write_field("_catalog_by_service_index", value)

var _catalog_by_currency_id: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_catalog_by_currency_id")
	set(value):
		if not _owned(): return
		_state.write_field("_catalog_by_currency_id", value)

var _skill_books_by_skill: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_skill_books_by_skill")
	set(value):
		if not _owned(): return
		_state.write_field("_skill_books_by_skill", value)

var _price_by_name: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_price_by_name")
	set(value):
		if not _owned(): return
		_state.write_field("_price_by_name", value)

var _price_by_item_id: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_price_by_item_id")
	set(value):
		if not _owned(): return
		_state.write_field("_price_by_item_id", value)

var _price_by_service_index: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_price_by_service_index")
	set(value):
		if not _owned(): return
		_state.write_field("_price_by_service_index", value)

var _bich_quests_by_id: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_bich_quests_by_id")
	set(value):
		if not _owned(): return
		_state.write_field("_bich_quests_by_id", value)

var _dpv2_direct_item_by_id: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("_dpv2_direct_item_by_id")
	set(value):
		if not _owned(): return
		_state.write_field("_dpv2_direct_item_by_id", value)

var _database_build_in_progress: bool:
	get:
		if not _owned(): return false
		return _state.read_field("_database_build_in_progress")
	set(value):
		if not _owned(): return
		_state.write_field("_database_build_in_progress", value)

var _ui_l1_price_fast_hits: int:
	get:
		if not _owned(): return 0
		return _state.read_field("_ui_l1_price_fast_hits")
	set(value):
		if not _owned(): return
		_state.write_field("_ui_l1_price_fast_hits", value)

var _ui_l1_price_slow_calls: int:
	get:
		if not _owned(): return 0
		return _state.read_field("_ui_l1_price_slow_calls")
	set(value):
		if not _owned(): return
		_state.write_field("_ui_l1_price_slow_calls", value)

var _ui_l1_price_maintenance_count: int:
	get:
		if not _owned(): return 0
		return _state.read_field("_ui_l1_price_maintenance_count")
	set(value):
		if not _owned(): return
		_state.write_field("_ui_l1_price_maintenance_count", value)

var dpv2_single_player_drop_boost: Dictionary:
	get:
		if not _owned(): return {}
		return _state.read_field("dpv2_single_player_drop_boost")
	set(value):
		if not _owned(): return
		_state.write_field("dpv2_single_player_drop_boost", value)

var profession_growth_source_path: String:
	get:
		if not _owned(): return ""
		return _state.read_field("profession_growth_source_path")
	set(value):
		if not _owned(): return
		_state.write_field("profession_growth_source_path", value)

func is_loaded() -> bool:
	if not _owned(): return false
	return _initial_load_complete


func _load_service_item_catalog() -> void:
	if not _owned(): return
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


func _dpv2_json_integer(value: Variant) -> int:
	if not _owned(): return -1
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


func _load_equipment_price_candidates() -> void:
	if not _owned(): return
	equipment_price_candidates = {}
	if not FileAccess.file_exists(EQUIPMENT_PRICE_CANDIDATES_PATH):
		return
	var file := FileAccess.open(EQUIPMENT_PRICE_CANDIDATES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		var owners := {}
		for row: Variant in parsed.get("records", []):
			var owner := _price_candidate_owner(row)
			if owner.is_empty() or owners.has(owner.id):
				push_error("Price candidate identity is unknown, conflicting or repeated")
				return
			owners[owner.id] = true
		equipment_price_candidates = parsed
	else:
		push_warning("装备价格候选文件不是有效JSON：%s" % EQUIPMENT_PRICE_CANDIDATES_PATH)


func merchant_stock(stock_key: String) -> Array:
	if not _owned(): return []
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
	if not _owned(): return {}
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


func merchant_context_by_id(merchant_id: String) -> Dictionary:
	if not _owned(): return {}
	if merchant_id.is_empty():
		return {}
	for stock_key: String in (merchant_catalog.get("merchants", {}) as Dictionary).keys():
		var context := merchant_context(stock_key)
		if str(context.get("merchant_id", "")) == merchant_id:
			context["stock_key"] = stock_key
			return context
	return {}


func _build_price_index() -> void:
	if not _owned(): return
	_price_by_name.clear()
	_price_by_item_id.clear()
	_price_by_service_index.clear()
	for raw: Variant in service_item_catalog.get("serviceEquipmentReference", []):
		_register_price_record(raw)
	for raw: Variant in service_item_catalog.get("runtimeItems", []):
		if raw is Dictionary and int(raw.get("serviceIndex", -1)) == 828 and str(raw.get("name", "")) == "黑铁矿":
			continue
		_register_price_record(raw)
	for raw: Variant in service_item_catalog.get("runtimeSpecials", {}).values():
		_register_price_record(raw)
	# 项目权威 newItems（910xxx 神水系等）由 item_runtime_authority 直接定义；
	# 携带 price 的记录在此入索引，避免"目录有身份、估值无主库价格"的裂缝。
	for raw: Variant in item_runtime_authority.get("newItems", []):
		_register_price_record(raw)
	# Primary database records always register first. These candidates are used
	# only for exact official items proven missing from every configured
	# server_data source; _register_price_record never overwrites an existing
	# primary record.
	for raw: Variant in equipment_price_candidates.get("records", []):
		_register_price_record(raw)
	# User-authorized price rulings may supersede one already-present legacy
	# quote, but only through an exact stable item identity. Keep the general
	# primary-first rule unchanged for every other catalog entry.
	_apply_exact_user_price_override(920032)


func _apply_exact_user_price_override(item_id: int) -> void:
	if not _owned(): return
	var service_index := EntityRegistry.service_for_item(EntityRegistry.canonical(EntityRegistry.from_legacy("item", item_id)))
	var record: Dictionary = {}
	# Quote lookup prefers the registered service alias, even when a candidate
	# also populated the item index. Update that real owner and all its aliases.
	if service_index >= 0 and _price_by_service_index.has(service_index):
		record = _price_by_service_index[service_index]
	elif _price_by_item_id.has(item_id):
		record = _price_by_item_id[item_id]
	if record.is_empty():
		return
	for raw: Variant in equipment_price_candidates.get("records", []):
		if not raw is Dictionary or str(raw.get("entity_id", "")) != "hc.item.%06d" % item_id:
			continue
		var source: Variant = raw.get("source", {})
		if not source is Dictionary or str(source.get("distribution", "")) != "user.pricing_ruling":
			return
		var override_price := maxi(0, int(raw.get("price", 0)))
		if override_price <= 0:
			return
		record["base_price"] = override_price
		record["source"] = source.duplicate(true)
		_price_by_item_id[item_id] = record
		if service_index >= 0:
			_price_by_service_index[service_index] = record
		var record_service_index := int(record.get("service_index", service_index))
		if record_service_index >= 0:
			_price_by_service_index[record_service_index] = record
		if str(record.get("item_name", "")) != "":
			_price_by_name[str(record.item_name)] = record
		return


func _register_price_record(raw: Variant) -> void:
	if not _owned(): return
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
	if source_record.has("entity_id"):
		var owner := _price_candidate_owner(source_record)
		if owner.is_empty(): return
		item_id = int(owner.legacy_id) if owner.kind == "item" else -1
		service_index = int(owner.legacy_id) if owner.kind == "service_item" else -1
	elif item_id < 0 and service_index >= 0:
		# Explicit old server-catalog import boundary. Candidate authoring carries
		# a registered identity and never enters this historical name translation.
		item_id = _item_id_for_name(canonical_name)
	if service_index < 0 and item_id < 0:
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
		),
		"entity_id": EntityRegistry.canonical(EntityRegistry.from_legacy("item", item_id)) if item_id >= 0
			else EntityRegistry.canonical(EntityRegistry.from_legacy("service_item", service_index)),
		"item_name": canonical_name,
		"item_id": item_id,
		"service_index": service_index,
		"service_type": int(source_record.get("serviceType", -1)),
		"base_price": base_price,
		"kind": str(source_record.get("kind", "unknown")),
		"category": str(source_record.get("category", "")),
		"category_id": ItemCategories.category_for_record(source_record),
		"source": (source_record.get("source", {}) as Dictionary).duplicate(true),
	}
	if not ItemCategories.attach_source_category(price_record):
		_item_category_error = "unknown_price_category"
		return
	if not _price_by_name.has(canonical_name):
		_price_by_name[canonical_name] = price_record
	if service_index >= 0:
		_price_by_service_index[service_index] = price_record
	if item_id >= 0:
		_price_by_item_id[item_id] = price_record


func _price_candidate_owner(row: Variant) -> Dictionary:
	if not _owned(): return {}
	if not row is Dictionary or not row.get("entity_id") is String: return {}
	var owner := EntityRegistry.resolve(EntityRegistry.canonical(row.entity_id))
	if owner.get("kind") not in ["item", "service_item"]: return {}
	for key: String in ["item_id", "itemId", "stableItemId", "id", "service_index", "serviceIndex"]:
		if not row.has(key): continue
		var value: Variant = row[key]
		var kind := "service_item" if key in ["service_index", "serviceIndex"] else "item"
		var declared := EntityRegistry.from_legacy(kind, value)
		if declared.is_empty() or EntityRegistry.canonical(declared) != owner.id: return {}
	return owner


func canonical_monster_id(raw_value: Variant) -> int:
	if not _owned(): return -1
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
	if not _owned(): return {}
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
	elif context == "editor":
		if not bool(entry.get("editor_placement", {}).get("allowed", false)):
			return {}
	return entry.duplicate(true)


func get_monster_by_id(monster_id: int) -> Dictionary:
	if not _owned(): return {}
	return get_canonical_monster_entry(monster_id, "runtime")


func canonical_monster_classification(monster_id: int) -> String:
	if not _owned(): return ""
	var resolved_id := canonical_monster_id(monster_id)
	var entry: Variant = _monsters_by_id.get(resolved_id, null)
	if not entry is Dictionary:
		return ""
	return str((entry as Dictionary).get("classification", ""))


func is_dpv2_direct_baseline_loaded() -> bool:
	if not _owned(): return false
	return dpv2_direct_baseline_loaded


func dpv2_direct_item_identity(canonical_item_id: Variant) -> Dictionary:
	if not _owned(): return {}
	var item_id := _dpv2_json_integer(canonical_item_id)
	if not dpv2_direct_baseline_loaded or item_id <= 0:
		return {}
	var value: Variant = _dpv2_direct_item_by_id.get(item_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func dpv2_direct_resolve_slot_reward(slot: Dictionary) -> Dictionary:
	if not _owned(): return {}
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


func dpv2_ground_slot_limit() -> int:
	if not _owned(): return -1
	if not dpv2_direct_baseline_loaded:
		return 0
	var policy: Variant = dpv2_direct_baseline.get("probability_policy", {})
	if not policy is Dictionary:
		return 0
	return maxi(0, _dpv2_json_integer(
		(policy as Dictionary).get("post_rng_ground_slot_limit", 0)
	))


func dpv2_ground_slot_limit_for_monster(monster_id: int) -> int:
	if not _owned(): return -1
	var resolved_id := canonical_monster_id(monster_id)
	if not _monsters_by_id.has(resolved_id):
		return 0
	var classification := canonical_monster_classification(resolved_id)
	var overrides: Dictionary = monster_ground_slot_group_policy.get("exact_id_group_overrides", {})
	var group_name := str(overrides.get(str(resolved_id), classification))
	var groups: Variant = monster_ground_slot_group_policy.get("groups", {})
	if not groups is Dictionary:
		return 0
	var group: Variant = groups.get(group_name, null)
	if not group is Dictionary:
		return 0
	return maxi(0, int(group.get("ground_slot_limit", 0)))


func dpv2_source_slot_gate() -> Dictionary:
	if not _owned(): return {}
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


func get_map_by_id(map_id: int) -> Dictionary:
	if not _owned(): return {}
	return _maps_by_id.get(map_id, {})

func get_map(map_name: String) -> Dictionary:
	if not _owned(): return {}
	return _maps_by_name.get(map_name, {})

func service_runtime_map_id(service_map_id: int) -> int:
	assert(_owned())
	return int(SERVICE_RUNTIME_MAP_ALIASES.get(service_map_id, service_map_id))

func service_setup_value(key: String, fallback: Variant = null) -> Variant:
	assert(_owned())
	return service_reference.get("serviceSetup", {}).get(key, fallback)

func service_home_map_id(red_name := false) -> int:
	return int(service_setup_value("RedHomeMap" if red_name else "HomeMap", 0))

func service_home_runtime_map_id(red_name := false) -> int:
	return service_runtime_map_id(service_home_map_id(red_name))

func service_home_point(red_name := false) -> Vector2i:
	var prefix := "RedHome" if red_name else "Home"
	return Vector2i(int(service_setup_value("%sX" % prefix, 0)),int(service_setup_value("%sY" % prefix, 0)))


func get_item(item_name: String) -> Dictionary:
	if not _owned(): return {}
	return _items_by_name.get(_canonical_item_name(item_name), {})


func get_item_record(item_ref: Variant) -> Dictionary:
	if not _owned(): return {}
	return _item_record_for_read(item_ref).duplicate(true)


func get_entity_record(entity_id: String) -> Dictionary:
	if not _owned(): return {}
	var identity := EntityRegistry.resolve(entity_id)
	if identity.is_empty():
		return {}
	match identity.kind:
		"item":
			return get_item_record({"item_id":int(identity.legacy_id)})
		"service_item":
			return get_item_record({"service_index":int(identity.legacy_id)})
		"monster":
			return get_monster_by_id(int(identity.legacy_id))
		"map":
			return get_map_by_id(int(identity.legacy_id))
		"currency":
			return get_item_record(entity_id)
	return {}


func item_entity_id(item_ref: Variant) -> String:
	if not _owned(): return ""
	var record := _item_record_for_read(item_ref)
	if record.is_empty():
		return ""
	if record.get("kind") == "currency" and record.get("currency_id") is String:
		return str(record.currency_id) if not EntityRegistry.resolve(record.currency_id, "currency").is_empty() else ""
	var item_id := _stable_item_id(record)
	if item_id >= 0:
		return EntityRegistry.canonical(EntityRegistry.from_legacy("item", item_id))
	return EntityRegistry.canonical(EntityRegistry.from_legacy("service_item", _service_index(record)))


func get_item_rules_record(item_ref: Variant) -> Dictionary:
	if not _owned(): return {}
	# Independent rule snapshot; art frame/provenance arrays are irrelevant to
	# pricing and save validation. All gameplay/identity fields stay identical.
	var record := _item_record_for_read(item_ref).duplicate()
	record.erase("art")
	return record.duplicate(true)


func _item_record_for_read(item_ref: Variant) -> Dictionary:
	if not _owned(): return {}
	if not is_loaded() and not _database_build_in_progress:
		return {}
	if not _valid_explicit_item_reference(item_ref):
		return {}
	if item_ref is Dictionary and (item_ref.has("format_version") or item_ref.has("base") or item_ref.has("extensions")):
		var base := ItemExtensionCodec.base_record(item_ref, _content())
		return _item_record_for_read(base) if not base.is_empty() else {}
	if item_ref is String and item_ref.begins_with("hc."):
		var registered := EntityRegistry.resolve(item_ref)
		if registered.get("kind") == "item":
			return _item_record_for_read({"item_id":int(registered.legacy_id)})
		if registered.get("kind") == "service_item":
			return _item_record_for_read({"service_index":int(registered.legacy_id)})
		if registered.get("kind") == "currency":
			return _catalog_by_currency_id.get(item_ref, {}) as Dictionary
		return {}
	if item_ref is Dictionary and item_ref.has("currency_id"):
		return _catalog_by_currency_id.get(item_ref.currency_id, {}) as Dictionary
	var identity := _stable_identity(item_ref)
	var item_id := int(identity.get("item_id", -1))
	if item_id == SocketGemRules.ITEM_ID:
		return SocketGemRules.record_for_id(item_id)
	var rune_record:=RuneItemRules.record_for_id(item_id)
	if not rune_record.is_empty(): return rune_record
	if item_id >= 0 and _catalog_by_item_id.has(item_id):
		return _catalog_by_item_id.get(item_id, {}) as Dictionary
	# The registry declares the exact service source for these reserved direct
	# item IDs. No display string participates in this runtime bridge.
	if item_id >= 0:
		var service_id := EntityRegistry.service_for_item(EntityRegistry.from_legacy("item", item_id))
		if service_id >= 0 and _catalog_by_service_index.has(service_id):
			var direct_record: Dictionary = (_catalog_by_service_index[service_id] as Dictionary).duplicate(true)
			var existing_id := int(direct_record.get("itemId", -1))
			if existing_id >= 0 and existing_id != item_id:
				return {}
			direct_record["itemId"] = item_id
			direct_record["identityBridge"] = "dpv2.direct_item_identity.v2"
			return direct_record
		return {}
	var service_index := int(identity.get("service_index", -1))
	if service_index >= 0 and _catalog_by_service_index.has(service_index):
		return _catalog_by_service_index.get(service_index, {}) as Dictionary
	var canonical_name := _canonical_item_name(str(identity.get("name", "")))
	return _catalog_by_name.get(canonical_name, {}) as Dictionary


func _valid_explicit_item_reference(value: Variant, runtime_membership := true) -> bool:
	if not _owned(): return false
	if value is int or value is float:
		return is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= 0 and float(value) <= 2147483647
	if not value is Dictionary:
		return true
	if value.has("currency_id"):
		if not value.currency_id is String or EntityRegistry.resolve(value.currency_id, "currency").is_empty():
			return false
		for item_key: String in ["item_id", "itemId", "service_index", "serviceIndex"]:
			if value.has(item_key): return false
		return not runtime_membership or _catalog_by_currency_id.has(value.currency_id)
	# A malformed explicit runtime identity never falls through to presentation
	# text. Authoring aliases are resolved by their existing primary indexes.
	for key: String in ["item_id", "service_index"]:
		if value.has(key):
			var number: Variant = value[key]
			if not (number is int or number is float) or not is_finite(float(number)) \
				or float(number) != floor(float(number)) or float(number) < 0 or float(number) > 2147483647:
				return false
	if value.has("item_id") and value.has("service_index"):
		# Both are permitted only when the existing item authority declares that
		# precise service link. Neither display name can establish the relation.
		var item := _item_record_for_read({"item_id": value.item_id})
		return not item.is_empty() and _service_index(item) == int(value.service_index)
	if value.has("service_index"):
		return not runtime_membership or _catalog_by_service_index.has(int(value.service_index))
	if value.has("item_id"):
		return not runtime_membership or not EntityRegistry.from_legacy("item", value.item_id).is_empty()
	return true


func validate_item_drop_instance(instance: Dictionary) -> bool:
	if not _owned(): return false
	# The validator reads this authoritative record without exposing a mutable
	# catalog reference to callers or copying unrelated artwork/rule metadata.
	var base := ItemExtensionCodec.base_record(instance, _content())
	return not base.is_empty() and _item_instance_rules().validate_instance(base,
		_item_record_for_read({"item_id": base.get("item_id", -1)}))


func get_item_shop_price(item_ref: Variant) -> int:
	if not _owned(): return -1
	return PricingServiceScript.adjusted_database_price(get_item_price_record(item_ref), {}, _pricing_content())


func get_item_price_record(item_ref: Variant) -> Dictionary:
	if not _owned(): return {}
	return _get_item_price_record(item_ref)


func _get_item_price_record(item_ref: Variant, name_id_snapshot: Dictionary = {}) -> Dictionary:
	if not _owned(): return {}
	if not is_loaded() and not _database_build_in_progress:
		return {}
	if item_ref is Dictionary:
		item_ref = item_ref.duplicate()
		for source_key: String in ["itemId", "serviceIndex"]:
			if not item_ref.has(source_key): continue
			var runtime_key := "item_id" if source_key == "itemId" else "service_index"
			if item_ref.has(runtime_key) and item_ref[runtime_key] != item_ref[source_key]: return {}
			item_ref[runtime_key] = item_ref[source_key]
	# Price-only service SKUs also include the existing equipment source lane;
	# their numeric source identity need not be an inventory-ownable service item.
	if not _valid_explicit_item_reference(item_ref, false):
		return {}
	if item_ref is String and item_ref.begins_with("hc."):
		var registered := EntityRegistry.resolve(item_ref)
		if registered.get("kind") not in ["item", "service_item"]:
			return {}
		item_ref = {"item_id" if registered.kind == "item" else "service_index": int(registered.legacy_id)}
	if item_ref is Dictionary and item_ref.has("item_id") and not item_ref.has("service_index"):
		var service_id := EntityRegistry.service_for_item(EntityRegistry.from_legacy("item", item_ref.item_id))
		if service_id >= 0:
			item_ref = item_ref.duplicate()
			item_ref["service_index"] = service_id
	if item_ref is Dictionary and (item_ref.has("item_id") or item_ref.has("service_index")):
		item_ref = item_ref.duplicate()
		item_ref.erase("name")
		item_ref.erase("item_name")
		item_ref.erase("itemName")
	# No independent price cache. Read the existing primary-first indexes only.
	# A missing higher-priority identity MUST run the original maintenance path.
	# Its newly added candidate can be stronger than a currently available fallback.
	if not _price_by_name.is_empty():
		var identity := _stable_identity(item_ref)
		var service_index := int(identity.get("service_index", -1))
		var item_id := int(identity.get("item_id", -1))
		if service_index >= 0:
			if _price_by_service_index.has(service_index):
				_ui_l1_price_fast_hits += 1
				return (_price_by_service_index[service_index] as Dictionary).duplicate(true)
		elif item_id >= 0:
			if _price_by_item_id.has(item_id):
				_ui_l1_price_fast_hits += 1
				return (_price_by_item_id[item_id] as Dictionary).duplicate(true)
		else:
			var canonical_name := _canonical_item_name(str(identity.get("name", "")))
			var name_item_id := int(name_id_snapshot[canonical_name]) if name_id_snapshot.has(canonical_name) else _item_id_for_name(canonical_name)
			if name_item_id >= 0:
				if _price_by_item_id.has(name_item_id):
					_ui_l1_price_fast_hits += 1
					return (_price_by_item_id[name_item_id] as Dictionary).duplicate(true)
			elif _price_by_name.has(canonical_name):
				_ui_l1_price_fast_hits += 1
				return (_price_by_name[canonical_name] as Dictionary).duplicate(true)
	_ui_l1_price_slow_calls += 1
	return _ui_l1_get_item_price_record_slow(item_ref)


func _ensure_price_index() -> void:
	if not _owned(): return
	_ui_l1_price_maintenance_count += 1
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
	if not _owned(): return ""
	var authority_aliases: Variant = item_runtime_authority.get("aliases", {})
	if authority_aliases is Dictionary and authority_aliases.has(item_name):
		return str(authority_aliases.get(item_name))
	return str(ITEM_ALIASES.get(item_name, item_name))


func _stable_identity(item_ref: Variant) -> Dictionary:
	if not _owned(): return {}
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
	if not _owned(): return -1
	for key: String in ["item_id", "itemId", "stableItemId", "id"]:
		if not record.has(key):
			continue
		var value := _parse_stable_number(record.get(key, -1))
		if value >= 0:
			return value
	return -1


func _service_index(record: Dictionary) -> int:
	if not _owned(): return -1
	for key: String in ["service_index", "serviceIndex"]:
		if not record.has(key):
			continue
		var value := _parse_stable_number(record.get(key, -1))
		if value >= 0:
			return value
	return -1


func _parse_stable_number(value: Variant) -> int:
	if not _owned(): return -1
	if value is String:
		var text := value as String
		if not text.is_valid_int():
			return -1
	return maxi(-1, int(value))


func _item_id_for_name(item_name: String) -> int:
	if not _owned(): return -1
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


func get_skill(skill_ref: String, skill_level := 0) -> Dictionary:
	if not _owned(): return {}
	# Exact legacy/UI ingress translates once; rank ownership is the existing
	# primary skill_id, independent of any display projection in these rows.
	var stable_id := CanonicalSkills.stable_skill_id(skill_ref)
	if stable_id.is_empty(): return {}
	for entry: Variant in skills:
		if entry is Dictionary and entry.get("skill_id", "") == stable_id and int(entry.get("skillLevel", -1)) == skill_level:
			return entry
	return {}


func skill_book_entity_id(skill_id: String) -> String:
	if not _owned(): return ""
	if EntityRegistry.resolve(skill_id, "skill").is_empty(): return ""
	return str(_skill_books_by_skill.get(skill_id, ""))


func skill_book_skill_id(item_ref: Variant) -> String:
	if not _owned(): return ""
	# New business queries require a typed owner. Old name-only saves are
	# imported by the item codec before reaching this runtime entrance.
	if item_ref is String and not item_ref.begins_with("hc."): return ""
	if item_ref is Dictionary and not item_ref.has("item_id") and not item_ref.has("service_index"): return ""
	var item := _item_record_for_read(item_ref)
	if str(item.get("kind", "")) != "skill_book" or not item.get("usable", true): return ""
	var target: Variant = item.get("learnSkillId", "")
	if not target is String or EntityRegistry.resolve(target, "skill").is_empty(): return ""
	return target if _skill_books_by_skill.get(target, "") == item_entity_id(item_ref) else ""


func get_bich_quest(quest_id: String) -> Dictionary:
	if not _owned(): return {}
	return _bich_quests_by_id.get(quest_id, {})


func get_bich_quests() -> Array:
	if not _owned(): return []
	return bich_quest_chain.get("quests", [])


func service_exp_to_next_level(level_value: int) -> int:
	if not _owned(): return -1
	var table: Dictionary = service_reference.get("serviceRuntimeExpTableLevel1To60", {})
	var key := str(maxi(1, level_value))
	if table.has(key):
		return int(table[key])
	return 300000 + maxi(0, level_value - 22) * 100000


func get_profession_skills(profession: String) -> Array:
	if not _owned(): return []
	var result: Array = []
	var identity: String = _profession_rules().profession_id(profession)
	if identity.is_empty(): return result
	for entry: Variant in skills:
		if entry is Dictionary and entry.get("profession_id", "") == identity and int(entry.get("skillLevel", -1)) == 0:
			result.append(entry)
	return result


func _ui_l1_get_item_price_record_slow(item_ref: Variant) -> Dictionary:
	if not _owned(): return {}
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




func potion_recovery_profile(player_level: int, restore_health: int, restore_mana: int, use_effect: String) -> Dictionary:
	if not _owned(): return {}
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

## Exact GameData.DATABASE_STATE_FIELDS intersection with the published query
## fields. Runtime cache/counters, fixed growth source and rule instances retain
## their owners, just as GameData.adopt_database_candidate does.
const PROFILE_DATABASE_FIELDS := ["service_reference", "bich_quest_chain", "service_item_catalog", "equipment_price_candidates", "merchant_catalog", "item_runtime_authority", "dpv2_direct_baseline_manifest", "dpv2_direct_baseline", "dpv2_monster_drop_semantic_authority", "monster_ground_slot_group_policy", "dpv2_direct_baseline_loaded", "items", "skills", "_item_category_error", "_monsters_by_id", "_items_by_name", "_maps_by_id", "_maps_by_name", "_catalog_by_name", "_catalog_by_item_id", "_catalog_by_service_index", "_catalog_by_currency_id", "_skill_books_by_skill", "_price_by_name", "_price_by_item_id", "_price_by_service_index", "_bich_quests_by_id", "_dpv2_direct_item_by_id", "dpv2_single_player_drop_boost"]

func adopt_profile_database_candidate(candidate: Dictionary, expected_revision: int) -> bool:
	if not _owned() or not simulation_owner or source_revision != expected_revision: return false
	if candidate.get("contract_id") != "profile.database.candidate.v1" or not candidate.get("validated_canonical",false): return false
	if not candidate.get("fields") is Dictionary or not Graph.validate(candidate).success: return false
	if candidate.fields.size() != PROFILE_DATABASE_FIELDS.size() or Graph.fingerprint(candidate.fields) != candidate.get("fields_sha256"): return false
	for field: String in PROFILE_DATABASE_FIELDS:
		if not candidate.fields.has(field): return false
	# All validation happens before the first write. There are no yields,
	# callbacks, shared static mutation or observer notifications here.
	var copied := Graph.capture(candidate.fields,false)
	if not copied.success: return false
	for field: String in PROFILE_DATABASE_FIELDS: _state.write_field(field,copied.value[field])
	_state.write_field("_initial_load_complete",true)
	source_revision += 1
	published_source_hash = str(candidate.fields_sha256)
	return true
