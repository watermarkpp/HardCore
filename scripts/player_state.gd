extends Node

## Legacy main adapter. Every profile field and rule has one owner in ProfileModel.
const ProfileModel := preload("res://scripts/gameplay/profile/profile_model.gd")
var _model: ProfileModel
var _source_domain_gate: RefCounted

const EquipmentRulesScript = ProfileModel.EquipmentRulesScript
const UIErrorFeedbackScript = ProfileModel.UIErrorFeedbackScript
const EquipmentTestLoadoutCatalogScript = ProfileModel.EquipmentTestLoadoutCatalogScript
const TestCharacterSkillProfilesScript = ProfileModel.TestCharacterSkillProfilesScript
const SkillLoadoutRulesScript = ProfileModel.SkillLoadoutRulesScript
const CombatResolutionRules = ProfileModel.CombatResolutionRules
const SkillDataLoaderScript = ProfileModel.SkillDataLoaderScript
const FeatureLoadout = ProfileModel.FeatureLoadout
const FeatureContributionProvider = ProfileModel.FeatureContributionProvider

var _feature_loadout: RefCounted:
	get: return _source_domain_gate.read_original_profile_view("_feature_loadout") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._feature_loadout
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_feature_loadout"): return
		_model._feature_loadout = value

var _feature_base_stats: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_feature_base_stats") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._feature_base_stats
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_feature_base_stats"): return
		_model._feature_base_stats = value

var feature_errors: Array:
	get: return _source_domain_gate.read_original_profile_view("feature_errors") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.feature_errors
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:feature_errors"): return
		_model.feature_errors = value
const SkillProgressionServiceScript = ProfileModel.SkillProgressionServiceScript
const SkillRngScript = ProfileModel.SkillRngScript
const PricingServiceScript = ProfileModel.PricingServiceScript
const ItemDropInstanceRulesScript = ProfileModel.ItemDropInstanceRulesScript
const CharacterIdentityCodec = ProfileModel.CharacterIdentityCodec
const ItemBindingCodec = ProfileModel.ItemBindingCodec
const EntityRegistry = ProfileModel.EntityRegistry
const ItemCategories = ProfileModel.ItemCategories
const EquipmentIdentity = ProfileModel.EquipmentIdentity
const ItemExtensionCodec = ProfileModel.ItemExtensionCodec
const EquipmentGrantedSkills = ProfileModel.EquipmentGrantedSkills
const RandomSpecialRules = ProfileModel.RandomSpecialRules
const ItemTransactionJournal = ProfileModel.ItemTransactionJournal
const ItemTransactionPort = ProfileModel.ItemTransactionPort
const SaveUpgradeBackup = ProfileModel.SaveUpgradeBackup
const SaveRelicRecovery = ProfileModel.SaveRelicRecovery

var _startup_save_upgrade_pending: bool:
	get: return _source_domain_gate.read_original_profile_view("_startup_save_upgrade_pending") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._startup_save_upgrade_pending
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_startup_save_upgrade_pending"): return
		_model._startup_save_upgrade_pending = value

var _startup_save_upgrade_in_progress: bool:
	get: return _source_domain_gate.read_original_profile_view("_startup_save_upgrade_in_progress") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._startup_save_upgrade_in_progress
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_startup_save_upgrade_in_progress"): return
		_model._startup_save_upgrade_in_progress = value

var startup_save_upgrade_result: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("startup_save_upgrade_result") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.startup_save_upgrade_result
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:startup_save_upgrade_result"): return
		_model.startup_save_upgrade_result = value

var _startup_save_upgrade_phase: String:
	get: return _source_domain_gate.read_original_profile_view("_startup_save_upgrade_phase") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._startup_save_upgrade_phase
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_startup_save_upgrade_phase"): return
		_model._startup_save_upgrade_phase = value

var _startup_source_backup_verified: bool:
	get: return _source_domain_gate.read_original_profile_view("_startup_source_backup_verified") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._startup_source_backup_verified
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_startup_source_backup_verified"): return
		_model._startup_source_backup_verified = value

var _item_transaction_port: RefCounted:
	get: return _source_domain_gate.read_original_profile_view("_item_transaction_port") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._item_transaction_port
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_item_transaction_port"): return
		_model._item_transaction_port = value

var _item_transaction_journal: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_item_transaction_journal") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._item_transaction_journal
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_item_transaction_journal"): return
		_model._item_transaction_journal = value
const EquipmentEnhancementRulesScript = ProfileModel.EquipmentEnhancementRulesScript
const EquipmentEnhancementServiceScript = ProfileModel.EquipmentEnhancementServiceScript
const RelicSynthesisRulesScript = ProfileModel.RelicSynthesisRulesScript
const RelicSynthesisServiceScript = ProfileModel.RelicSynthesisServiceScript
const WorldMonsterRespawnStateScript = ProfileModel.WorldMonsterRespawnStateScript
const WorldMonsterClockLedgerScript = ProfileModel.WorldMonsterClockLedgerScript
signal profile_changed
signal inventory_changed
signal equipment_changed
signal item_audio_committed(
	identity_domain: String,
	identity_id: int,
	semantic_event: String,
)
signal skills_changed
signal skill_progression_changed(snapshot: Dictionary)
signal quick_slots_changed(change: Dictionary)
signal quick_item_slots_changed(change: Dictionary)
signal warrior_runtime_state_changed(snapshot: Dictionary)
signal consumable_requested(entity_id: String)
signal scroll_requested(entity_id: String)
signal quests_changed
signal profession_changed(profession: String)
signal levels_gained(previous_level: int, new_level: int)
signal relic_proc_started(item_id: int)
const SAVE_VERSION = ProfileModel.SAVE_VERSION
const SAVE_PATH = ProfileModel.SAVE_PATH
const LEGACY_SAVE_PATH = ProfileModel.LEGACY_SAVE_PATH
const PROFILE_INDEX_PATH = ProfileModel.PROFILE_INDEX_PATH
const PROFILE_DIRECTORY = ProfileModel.PROFILE_DIRECTORY
const TEST_ROSTER_RESET_MARKER_PATH = ProfileModel.TEST_ROSTER_RESET_MARKER_PATH
const AUTOSAVE_INTERVAL = ProfileModel.AUTOSAVE_INTERVAL
const DURABILITY_SAVE_INTERVAL = ProfileModel.DURABILITY_SAVE_INTERVAL
const DURABILITY_VISUAL_INTERVAL = ProfileModel.DURABILITY_VISUAL_INTERVAL
const WARRIOR_RUNTIME_CONTRACT_ID = ProfileModel.WARRIOR_RUNTIME_CONTRACT_ID
const TAOIST_MAIN_PET_PERSISTENCE_CONTRACT_ID = ProfileModel.TAOIST_MAIN_PET_PERSISTENCE_CONTRACT_ID
const TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID = ProfileModel.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID
const TEST_CHARACTER_ROSTER_CONTRACT_ID = ProfileModel.TEST_CHARACTER_ROSTER_CONTRACT_ID
const TEST_ROSTER_RESET_CONTRACT_ID = ProfileModel.TEST_ROSTER_RESET_CONTRACT_ID
const CHIYUE_TEST_PROFILE_IDS = ProfileModel.CHIYUE_TEST_PROFILE_IDS
const CURRENT_CONTENT_SCHEMA_VERSION = ProfileModel.CURRENT_CONTENT_SCHEMA_VERSION
const CANONICAL_MATERIAL_ITEMS = ProfileModel.CANONICAL_MATERIAL_ITEMS
const SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID = ProfileModel.SKILL_BUTTON_ASSIGNMENTS_CONTRACT_ID
const WORLD_POSITION_CONTRACT_ID = ProfileModel.WORLD_POSITION_CONTRACT_ID
const SKILL_SLOT_GROUP_CENTER = ProfileModel.SKILL_SLOT_GROUP_CENTER
const SKILL_SLOT_GROUP_ATTACK = ProfileModel.SKILL_SLOT_GROUP_ATTACK
const SKILL_SLOT_GROUP_ATTACK_RING = ProfileModel.SKILL_SLOT_GROUP_ATTACK_RING
const CENTER_SKILL_SLOT_COUNT = ProfileModel.CENTER_SKILL_SLOT_COUNT
const ATTACK_SKILL_SLOT_COUNT = ProfileModel.ATTACK_SKILL_SLOT_COUNT
const ATTACK_RING_SKILL_SLOT_COUNT = ProfileModel.ATTACK_RING_SKILL_SLOT_COUNT
const QUICK_ITEM_SLOTS_CONTRACT_ID = ProfileModel.QUICK_ITEM_SLOTS_CONTRACT_ID
const QUICK_ITEM_SLOT_COUNT = ProfileModel.QUICK_ITEM_SLOT_COUNT
const SAVE_RESULT_CONTRACT_ID = ProfileModel.SAVE_RESULT_CONTRACT_ID
const DEVICE_LAB_SAVE_CONTRACT_ID = ProfileModel.DEVICE_LAB_SAVE_CONTRACT_ID
const DEATH_EXPERIENCE_PENALTY_CONTRACT_ID = ProfileModel.DEATH_EXPERIENCE_PENALTY_CONTRACT_ID
const PRICING_CONTRACT_ID = ProfileModel.PRICING_CONTRACT_ID
const DURABILITY_CONTRACT_ID = ProfileModel.DURABILITY_CONTRACT_ID
const DURABILITY_EVENT_WEAPON_PHYSICAL_HIT = ProfileModel.DURABILITY_EVENT_WEAPON_PHYSICAL_HIT
const DURABILITY_EVENT_INCOMING_PHYSICAL_STRUCK = ProfileModel.DURABILITY_EVENT_INCOMING_PHYSICAL_STRUCK
const DURABILITY_RAW_UNITS_PER_DISPLAY = ProfileModel.DURABILITY_RAW_UNITS_PER_DISPLAY
const DURABILITY_INCOMING_EXTENSION_POLICY = ProfileModel.DURABILITY_INCOMING_EXTENSION_POLICY
const SHOP_SELL_CONTRACT_ID = ProfileModel.SHOP_SELL_CONTRACT_ID
const QUEST_ABANDON_CONTRACT_ID = ProfileModel.QUEST_ABANDON_CONTRACT_ID
const WAREHOUSE_SORT_CONTRACT_ID = ProfileModel.WAREHOUSE_SORT_CONTRACT_ID
const WAREHOUSE_CAPACITY = ProfileModel.WAREHOUSE_CAPACITY
const WAREHOUSE_PAGE_SIZE = ProfileModel.WAREHOUSE_PAGE_SIZE
const INVENTORY_CAPACITY = ProfileModel.INVENTORY_CAPACITY
const INVENTORY_WEIGHT_CONTRACT_ID = ProfileModel.INVENTORY_WEIGHT_CONTRACT_ID
const INVENTORY_WEIGHT_REJECTION = ProfileModel.INVENTORY_WEIGHT_REJECTION
const INVENTORY_SLOT_REJECTION = ProfileModel.INVENTORY_SLOT_REJECTION
const WAREHOUSE_TRANSFER_CONTRACT_ID = ProfileModel.WAREHOUSE_TRANSFER_CONTRACT_ID
const SHARED_WAREHOUSE_SCHEMA_VERSION = ProfileModel.SHARED_WAREHOUSE_SCHEMA_VERSION
const SHARED_WAREHOUSE_CONTRACT_ID = ProfileModel.SHARED_WAREHOUSE_CONTRACT_ID
const SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID = ProfileModel.SHARED_WAREHOUSE_MIGRATION_CONTRACT_ID
const SHARED_WAREHOUSE_DEFAULT_PATH = ProfileModel.SHARED_WAREHOUSE_DEFAULT_PATH
const SHARED_WAREHOUSE_TRANSACTION_LOG_PATH = ProfileModel.SHARED_WAREHOUSE_TRANSACTION_LOG_PATH
const PLAYER_GOLD_CAP = ProfileModel.PLAYER_GOLD_CAP
const SHARED_GOLD_CAP = ProfileModel.SHARED_GOLD_CAP
const BANK_TRANSFER_AMOUNT = ProfileModel.BANK_TRANSFER_AMOUNT
const BANK_CONTRACT_ID = ProfileModel.BANK_CONTRACT_ID
const BANK_TRANSACTION_HISTORY_LIMIT = ProfileModel.BANK_TRANSACTION_HISTORY_LIMIT
const BANK_TRANSACTION_ID_MAX_LENGTH = ProfileModel.BANK_TRANSACTION_ID_MAX_LENGTH
const GOLD_OVERFLOW_RECORD_LIMIT = ProfileModel.GOLD_OVERFLOW_RECORD_LIMIT
const MAX_EXACT_JSON_INTEGER = ProfileModel.MAX_EXACT_JSON_INTEGER
const MAX_SAFE_WEIGHT = ProfileModel.MAX_SAFE_WEIGHT
const SHOP_SELL_HIGH_VALUE_PRICE = ProfileModel.SHOP_SELL_HIGH_VALUE_PRICE
const EQUIPMENT_SLOTS = ProfileModel.EQUIPMENT_SLOTS
const STARTER_LOADOUT_CONTRACT_ID = ProfileModel.STARTER_LOADOUT_CONTRACT_ID
const CHARACTER_DELETE_CONTRACT_ID = ProfileModel.CHARACTER_DELETE_CONTRACT_ID
const STARTER_WEAPON_ITEM_NAME = ProfileModel.STARTER_WEAPON_ITEM_NAME
const STARTER_ARMOR_BY_GENDER = ProfileModel.STARTER_ARMOR_BY_GENDER
const GAMEPLAY_EXPERIENCE_THRESHOLD_SCALE = ProfileModel.GAMEPLAY_EXPERIENCE_THRESHOLD_SCALE
const GAMEPLAY_EXPERIENCE_CURRENT_THRESHOLD_RATIO = ProfileModel.GAMEPLAY_EXPERIENCE_CURRENT_THRESHOLD_RATIO
const GAMEPLAY_EXPERIENCE_THRESHOLD_MINIMUM = ProfileModel.GAMEPLAY_EXPERIENCE_THRESHOLD_MINIMUM
const VERIFIED_EXPERIENCE_1_TO_22 = ProfileModel.VERIFIED_EXPERIENCE_1_TO_22
const TEMPORARY_ITEM_BUFF_CONTRACT_ID = ProfileModel.TEMPORARY_ITEM_BUFF_CONTRACT_ID
const BLESSING_OIL_ENTITY_ID = ProfileModel.BLESSING_OIL_ENTITY_ID
const TEMPORARY_ITEM_BUFF_ALLOWED_STATS = ProfileModel.TEMPORARY_ITEM_BUFF_ALLOWED_STATS

var level: int:
	get: return _source_domain_gate.read_original_profile_view("level") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.level
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:level"): return
		_model.level = value

var _profession_id: String:
	get: return _source_domain_gate.read_original_profile_view("_profession_id") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._profession_id
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_profession_id"): return
		_model._profession_id = value

var profession_identity_errors: Array[String]:
	get: return _source_domain_gate.read_original_profile_view("profession_identity_errors") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.profession_identity_errors
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:profession_identity_errors"): return
		_model.profession_identity_errors = value

var profession_id: String:
	get: return _source_domain_gate.read_original_profile_view("profession_id") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.profession_id

var profession: String:
	get: return _source_domain_gate.read_original_profile_view("profession") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.profession
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:profession"): return
		_model.profession = value

var gender: String:
	get: return _source_domain_gate.read_original_profile_view("gender") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.gender
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:gender"): return
		_model.gender = value

var later_content_enabled: bool:
	get: return _source_domain_gate.read_original_profile_view("later_content_enabled") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.later_content_enabled
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:later_content_enabled"): return
		_model.later_content_enabled = value

var game_mode_id: String:
	get: return _source_domain_gate.read_original_profile_view("game_mode_id") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.game_mode_id
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:game_mode_id"): return
		_model.game_mode_id = value

var experience: int:
	get: return _source_domain_gate.read_original_profile_view("experience") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.experience
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:experience"): return
		_model.experience = value

var gold: int:
	get: return _source_domain_gate.read_original_profile_view("gold") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.gold
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:gold"): return
		_model.gold = value

var gold_overflow_records: Array:
	get: return _source_domain_gate.read_original_profile_view("gold_overflow_records") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.gold_overflow_records
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:gold_overflow_records"): return
		_model.gold_overflow_records = value

var inventory: Array:
	get: return _source_domain_gate.read_original_profile_view("inventory") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.inventory
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:inventory"): return
		_model.inventory = value

var forge_tray: Array[Dictionary]:
	get: return _source_domain_gate.read_original_profile_view("forge_tray") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.forge_tray
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:forge_tray"): return
		_model.forge_tray = value

var synthesis_tray: Array[Dictionary]:
	get: return _source_domain_gate.read_original_profile_view("synthesis_tray") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.synthesis_tray
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:synthesis_tray"): return
		_model.synthesis_tray = value

var warehouse_inventory: Array:
	get: return _source_domain_gate.read_original_profile_view("warehouse_inventory") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.warehouse_inventory
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:warehouse_inventory"): return
		_model.warehouse_inventory = value

var shared_warehouse_path: String:
	get: return _source_domain_gate.read_original_profile_view("shared_warehouse_path") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.shared_warehouse_path
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:shared_warehouse_path"): return
		_model.shared_warehouse_path = value

var shared_warehouse_transaction_log_path: String:
	get: return _source_domain_gate.read_original_profile_view("shared_warehouse_transaction_log_path") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.shared_warehouse_transaction_log_path
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:shared_warehouse_transaction_log_path"): return
		_model.shared_warehouse_transaction_log_path = value

var _shared_warehouse_initialized: bool:
	get: return _source_domain_gate.read_original_profile_view("_shared_warehouse_initialized") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._shared_warehouse_initialized
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_shared_warehouse_initialized"): return
		_model._shared_warehouse_initialized = value

var _active_profile_legacy_warehouse_pending: bool:
	get: return _source_domain_gate.read_original_profile_view("_active_profile_legacy_warehouse_pending") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._active_profile_legacy_warehouse_pending
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_active_profile_legacy_warehouse_pending"): return
		_model._active_profile_legacy_warehouse_pending = value

var _warehouse_transaction_locked: bool:
	get: return _source_domain_gate.read_original_profile_view("_warehouse_transaction_locked") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._warehouse_transaction_locked
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_warehouse_transaction_locked"): return
		_model._warehouse_transaction_locked = value

var _persistence_transaction_in_progress: bool:
	get: return _source_domain_gate.read_original_profile_view("_persistence_transaction_in_progress") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._persistence_transaction_in_progress
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_persistence_transaction_in_progress"): return
		_model._persistence_transaction_in_progress = value

var _test_fail_shared_write: bool:
	get: return _source_domain_gate.read_original_profile_view("_test_fail_shared_write") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._test_fail_shared_write
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_test_fail_shared_write"): return
		_model._test_fail_shared_write = value

var _test_fail_profile_write: bool:
	get: return _source_domain_gate.read_original_profile_view("_test_fail_profile_write") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._test_fail_profile_write
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_test_fail_profile_write"): return
		_model._test_fail_profile_write = value

var _test_fail_warehouse_rollback_write: bool:
	get: return _source_domain_gate.read_original_profile_view("_test_fail_warehouse_rollback_write") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._test_fail_warehouse_rollback_write
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_test_fail_warehouse_rollback_write"): return
		_model._test_fail_warehouse_rollback_write = value

var equipment: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("equipment") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.equipment
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:equipment"): return
		_model.equipment = value

var _skill_progression: RefCounted:
	get: return _source_domain_gate.read_original_profile_view("_skill_progression") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._skill_progression
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_skill_progression"): return
		_model._skill_progression = value

var _learned_skill_ids: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_learned_skill_ids") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._learned_skill_ids
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_learned_skill_ids"): return
		_model._learned_skill_ids = value

var skill_identity_errors: Array:
	get: return _source_domain_gate.read_original_profile_view("skill_identity_errors") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.skill_identity_errors
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:skill_identity_errors"): return
		_model.skill_identity_errors = value

var learned_skills: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("learned_skills") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.learned_skills
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:learned_skills"): return
		_model.learned_skills = value

var quick_slots: Array[String]:
	get: return _source_domain_gate.read_original_profile_view("quick_slots") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.quick_slots
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:quick_slots"): return
		_model.quick_slots = value

var quick_item_slots: Array[String]:
	get: return _source_domain_gate.read_original_profile_view("quick_item_slots") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.quick_item_slots
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:quick_item_slots"): return
		_model.quick_item_slots = value

var equip_cycle_cursor: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("equip_cycle_cursor") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.equip_cycle_cursor
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:equip_cycle_cursor"): return
		_model.equip_cycle_cursor = value

var equipment_transaction_revision: int:
	get: return _source_domain_gate.read_original_profile_view("equipment_transaction_revision") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.equipment_transaction_revision
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:equipment_transaction_revision"): return
		_model.equipment_transaction_revision = value

var _last_equipment_transaction_result: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_last_equipment_transaction_result") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._last_equipment_transaction_result
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_last_equipment_transaction_result"): return
		_model._last_equipment_transaction_result = value

var _attack_skill_ids: Array[String]:
	get: return _source_domain_gate.read_original_profile_view("_attack_skill_ids") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._attack_skill_ids
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_attack_skill_ids"): return
		_model._attack_skill_ids = value

var _attack_ring_ids: Array[String]:
	get: return _source_domain_gate.read_original_profile_view("_attack_ring_ids") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._attack_ring_ids
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_attack_ring_ids"): return
		_model._attack_ring_ids = value

var attack_skill_slots: Array[String]:
	get: return _source_domain_gate.read_original_profile_view("attack_skill_slots") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.attack_skill_slots
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:attack_skill_slots"): return
		_model.attack_skill_slots = value

var attack_ring_slots: Array[String]:
	get: return _source_domain_gate.read_original_profile_view("attack_ring_slots") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.attack_ring_slots
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:attack_ring_slots"): return
		_model.attack_ring_slots = value

var warrior_runtime_state: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("warrior_runtime_state") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.warrior_runtime_state
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:warrior_runtime_state"): return
		_model.warrior_runtime_state = value

var taoist_main_pet_runtime_states: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("taoist_main_pet_runtime_states") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.taoist_main_pet_runtime_states
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:taoist_main_pet_runtime_states"): return
		_model.taoist_main_pet_runtime_states = value

var quest_states: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("quest_states") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.quest_states
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:quest_states"): return
		_model.quest_states = value

var world_monster_respawn_state: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("world_monster_respawn_state") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.world_monster_respawn_state
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:world_monster_respawn_state"): return
		_model.world_monster_respawn_state = value
const WorldClockDelta = ProfileModel.WorldClockDelta

var _world_clock_changes: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_world_clock_changes") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._world_clock_changes
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_world_clock_changes"): return
		_model._world_clock_changes = value

var _death_event_sequence: int:
	get: return _source_domain_gate.read_original_profile_view("_death_event_sequence") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._death_event_sequence
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_death_event_sequence"): return
		_model._death_event_sequence = value

var _world_clock_generation: String:
	get: return _source_domain_gate.read_original_profile_view("_world_clock_generation") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._world_clock_generation
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_world_clock_generation"): return
		_model._world_clock_generation = value

var _profile_saved_death_event_sequence: int:
	get: return _source_domain_gate.read_original_profile_view("_profile_saved_death_event_sequence") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._profile_saved_death_event_sequence
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_profile_saved_death_event_sequence"): return
		_model._profile_saved_death_event_sequence = value

var _profile_backup_death_event_sequence: int:
	get: return _source_domain_gate.read_original_profile_view("_profile_backup_death_event_sequence") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._profile_backup_death_event_sequence
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_profile_backup_death_event_sequence"): return
		_model._profile_backup_death_event_sequence = value

var _world_clock_snapshot_sequence: int:
	get: return _source_domain_gate.read_original_profile_view("_world_clock_snapshot_sequence") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._world_clock_snapshot_sequence
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_world_clock_snapshot_sequence"): return
		_model._world_clock_snapshot_sequence = value

var _world_clock_backup_sequence: int:
	get: return _source_domain_gate.read_original_profile_view("_world_clock_backup_sequence") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._world_clock_backup_sequence
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_world_clock_backup_sequence"): return
		_model._world_clock_backup_sequence = value

var _world_clock_dirty: bool:
	get: return _source_domain_gate.read_original_profile_view("_world_clock_dirty") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._world_clock_dirty
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_world_clock_dirty"): return
		_model._world_clock_dirty = value

var _clock_cleanup_worker: RefCounted:
	get: return _source_domain_gate.read_original_profile_view("_clock_cleanup_worker") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._clock_cleanup_worker
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_clock_cleanup_worker"): return
		_model._clock_cleanup_worker = value

var _clock_cleanup_pending: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_clock_cleanup_pending") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._clock_cleanup_pending
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_clock_cleanup_pending"): return
		_model._clock_cleanup_pending = value

var _clock_cleanup_active: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_clock_cleanup_active") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._clock_cleanup_active
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_clock_cleanup_active"): return
		_model._clock_cleanup_active = value

var _clock_cleanup_completed: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_clock_cleanup_completed") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._clock_cleanup_completed
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_clock_cleanup_completed"): return
		_model._clock_cleanup_completed = value
const JsonPersistenceService = ProfileModel.JsonPersistenceService

var _json_persistence: RefCounted:
	get: return _source_domain_gate.read_original_profile_view("_json_persistence") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._json_persistence
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_json_persistence"): return
		_model._json_persistence = value

var _world_json_persistence: RefCounted:
	get: return _source_domain_gate.read_original_profile_view("_world_json_persistence") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._world_json_persistence
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_world_json_persistence"): return
		_model._world_json_persistence = value
const JsonPreparedRequest = ProfileModel.JsonPreparedRequest

var saved_map_id: int:
	get: return _source_domain_gate.read_original_profile_view("saved_map_id") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.saved_map_id
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:saved_map_id"): return
		_model.saved_map_id = value

var saved_position: Vector2:
	get: return _source_domain_gate.read_original_profile_view("saved_position") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.saved_position
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:saved_position"): return
		_model.saved_position = value

var saved_ground_position_gu: Vector2:
	get: return _source_domain_gate.read_original_profile_view("saved_ground_position_gu") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.saved_ground_position_gu
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:saved_ground_position_gu"): return
		_model.saved_ground_position_gu = value

var saved_ground_position_gu_valid: bool:
	get: return _source_domain_gate.read_original_profile_view("saved_ground_position_gu_valid") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.saved_ground_position_gu_valid
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:saved_ground_position_gu_valid"): return
		_model.saved_ground_position_gu_valid = value

var base_stats: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("base_stats") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.base_stats
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:base_stats"): return
		_model.base_stats = value

var computed_stats: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("computed_stats") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.computed_stats
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:computed_stats"): return
		_model.computed_stats = value

var computed_special_effects: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("computed_special_effects") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.computed_special_effects
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:computed_special_effects"): return
		_model.computed_special_effects = value

var test_mode: bool:
	get: return _source_domain_gate.read_original_profile_view("test_mode") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.test_mode
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:test_mode"): return
		_model.test_mode = value

var durability_event_commit_count: int:
	get: return _source_domain_gate.read_original_profile_view("durability_event_commit_count") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.durability_event_commit_count
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:durability_event_commit_count"): return
		_model.durability_event_commit_count = value

var _durability_rng: RandomNumberGenerator:
	get: return _source_domain_gate.read_original_profile_view("_durability_rng") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._durability_rng
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_durability_rng"): return
		_model._durability_rng = value

var _blessing_oil_rng: RandomNumberGenerator:
	get: return _source_domain_gate.read_original_profile_view("_blessing_oil_rng") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._blessing_oil_rng
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_blessing_oil_rng"): return
		_model._blessing_oil_rng = value

var active_profile_id: String:
	get: return _source_domain_gate.read_original_profile_view("active_profile_id") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.active_profile_id
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:active_profile_id"): return
		_model.active_profile_id = value

var _profile_gameplay_owners: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_profile_gameplay_owners") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._profile_gameplay_owners

var character_name: String:
	get: return _source_domain_gate.read_original_profile_view("character_name") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.character_name
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:character_name"): return
		_model.character_name = value

var _autosave_elapsed: float:
	get: return _source_domain_gate.read_original_profile_view("_autosave_elapsed") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._autosave_elapsed
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_autosave_elapsed"): return
		_model._autosave_elapsed = value

var _durability_save_pending: bool:
	get: return _source_domain_gate.read_original_profile_view("_durability_save_pending") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._durability_save_pending
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_durability_save_pending"): return
		_model._durability_save_pending = value

var _durability_save_elapsed: float:
	get: return _source_domain_gate.read_original_profile_view("_durability_save_elapsed") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._durability_save_elapsed
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_durability_save_elapsed"): return
		_model._durability_save_elapsed = value

var _durability_mutation_revision: int:
	get: return _source_domain_gate.read_original_profile_view("_durability_mutation_revision") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._durability_mutation_revision
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_durability_mutation_revision"): return
		_model._durability_mutation_revision = value

var _world_mutation_revision: int:
	get: return _source_domain_gate.read_original_profile_view("_world_mutation_revision") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._world_mutation_revision
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_world_mutation_revision"): return
		_model._world_mutation_revision = value

var _background_save: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_background_save") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._background_save
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_background_save"): return
		_model._background_save = value

var _background_death: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_background_death") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._background_death
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_background_death"): return
		_model._background_death = value

var _item_save_revision: int:
	get: return _source_domain_gate.read_original_profile_view("_item_save_revision") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._item_save_revision
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_item_save_revision"): return
		_model._item_save_revision = value

var _item_saved_revision: int:
	get: return _source_domain_gate.read_original_profile_view("_item_saved_revision") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._item_saved_revision
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_item_saved_revision"): return
		_model._item_saved_revision = value

var _item_save_plan: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_item_save_plan") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._item_save_plan
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_item_save_plan"): return
		_model._item_save_plan = value

var _item_save_failed: bool:
	get: return _source_domain_gate.read_original_profile_view("_item_save_failed") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._item_save_failed
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_item_save_failed"): return
		_model._item_save_failed = value

var _workbench_transfer_pending: bool:
	get: return _source_domain_gate.read_original_profile_view("_workbench_transfer_pending") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._workbench_transfer_pending
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_workbench_transfer_pending"): return
		_model._workbench_transfer_pending = value
signal background_item_save_failed

var _durability_visual_pending: bool:
	get: return _source_domain_gate.read_original_profile_view("_durability_visual_pending") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._durability_visual_pending
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_durability_visual_pending"): return
		_model._durability_visual_pending = value

var _durability_visual_elapsed: float:
	get: return _source_domain_gate.read_original_profile_view("_durability_visual_elapsed") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._durability_visual_elapsed
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_durability_visual_elapsed"): return
		_model._durability_visual_elapsed = value

var profile_index_path: String:
	get: return _source_domain_gate.read_original_profile_view("profile_index_path") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.profile_index_path
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:profile_index_path"): return
		_model.profile_index_path = value

var profile_directory: String:
	get: return _source_domain_gate.read_original_profile_view("profile_directory") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.profile_directory
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:profile_directory"): return
		_model.profile_directory = value

var test_roster_reset_marker_path: String:
	get: return _source_domain_gate.read_original_profile_view("test_roster_reset_marker_path") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.test_roster_reset_marker_path
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:test_roster_reset_marker_path"): return
		_model.test_roster_reset_marker_path = value

var last_save_result: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("last_save_result") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.last_save_result
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:last_save_result"): return
		_model.last_save_result = value

var last_load_result: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("last_load_result") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.last_load_result
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:last_load_result"): return
		_model.last_load_result = value

var _save_blocked_profile_id: String:
	get: return _source_domain_gate.read_original_profile_view("_save_blocked_profile_id") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._save_blocked_profile_id
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_save_blocked_profile_id"): return
		_model._save_blocked_profile_id = value

var _save_blocked_reason: String:
	get: return _source_domain_gate.read_original_profile_view("_save_blocked_reason") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._save_blocked_reason
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_save_blocked_reason"): return
		_model._save_blocked_reason = value

var _consumed_shop_sell_quote_ids: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_consumed_shop_sell_quote_ids") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._consumed_shop_sell_quote_ids
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_consumed_shop_sell_quote_ids"): return
		_model._consumed_shop_sell_quote_ids = value

var _enhancement_service: Variant:
	get: return _source_domain_gate.read_original_profile_view("_enhancement_service") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._enhancement_service
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_enhancement_service"): return
		_model._enhancement_service = value

var _relic_synthesis_service: Variant:
	get: return _source_domain_gate.read_original_profile_view("_relic_synthesis_service") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._relic_synthesis_service
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_relic_synthesis_service"): return
		_model._relic_synthesis_service = value

var _relic_instance_rng: RandomNumberGenerator:
	get: return _source_domain_gate.read_original_profile_view("_relic_instance_rng") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._relic_instance_rng
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_relic_instance_rng"): return
		_model._relic_instance_rng = value

var _relic_proc_rng: RandomNumberGenerator:
	get: return _source_domain_gate.read_original_profile_view("_relic_proc_rng") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._relic_proc_rng
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_relic_proc_rng"): return
		_model._relic_proc_rng = value

var _relic_proc_state: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_relic_proc_state") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._relic_proc_state
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_relic_proc_state"): return
		_model._relic_proc_state = value

var _relic_proc_equipment_snapshot: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_relic_proc_equipment_snapshot") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._relic_proc_equipment_snapshot
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_relic_proc_equipment_snapshot"): return
		_model._relic_proc_equipment_snapshot = value

var _loot_batch_debug: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_loot_batch_debug") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._loot_batch_debug
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_loot_batch_debug"): return
		_model._loot_batch_debug = value

var _last_runtime_commit_profile: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_last_runtime_commit_profile") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._last_runtime_commit_profile
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_last_runtime_commit_profile"): return
		_model._last_runtime_commit_profile = value
const SpecialConsumableStacks = ProfileModel.SpecialConsumableStacks
const LootPreparedFile = ProfileModel.LootPreparedFile

var _atomic_write_generation: int:
	get: return _source_domain_gate.read_original_profile_view("_atomic_write_generation") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._atomic_write_generation
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_atomic_write_generation"): return
		_model._atomic_write_generation = value

var _validated_profile_path: String:
	get: return _source_domain_gate.read_original_profile_view("_validated_profile_path") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._validated_profile_path
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_validated_profile_path"): return
		_model._validated_profile_path = value

var _validated_profile_bytes: PackedByteArray:
	get: return _source_domain_gate.read_original_profile_view("_validated_profile_bytes") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._validated_profile_bytes
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_validated_profile_bytes"): return
		_model._validated_profile_bytes = value

var _atomic_write_phases: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_atomic_write_phases") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._atomic_write_phases
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_atomic_write_phases"): return
		_model._atomic_write_phases = value

var _last_json_promotion: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_last_json_promotion") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._last_json_promotion
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_last_json_promotion"): return
		_model._last_json_promotion = value

var _last_atomic_write_failure: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_last_atomic_write_failure") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._last_atomic_write_failure
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_last_atomic_write_failure"): return
		_model._last_atomic_write_failure = value

var _last_save_phase_profile: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_last_save_phase_profile") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._last_save_phase_profile
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_last_save_phase_profile"): return
		_model._last_save_phase_profile = value

var _last_loot_batch_profile: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_last_loot_batch_profile") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._last_loot_batch_profile
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_last_loot_batch_profile"): return
		_model._last_loot_batch_profile = value

var _last_death_settlement_profile: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_last_death_settlement_profile") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._last_death_settlement_profile
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_last_death_settlement_profile"): return
		_model._last_death_settlement_profile = value

var _loot_inventory_catalog_cache: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_loot_inventory_catalog_cache") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._loot_inventory_catalog_cache
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_loot_inventory_catalog_cache"): return
		_model._loot_inventory_catalog_cache = value

var _item_instance_serial: int:
	get: return _source_domain_gate.read_original_profile_view("_item_instance_serial") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._item_instance_serial
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_item_instance_serial"): return
		_model._item_instance_serial = value

var _test_transaction_counters: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_test_transaction_counters") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._test_transaction_counters
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_test_transaction_counters"): return
		_model._test_transaction_counters = value

var _shop_quote_debug: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_shop_quote_debug") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._shop_quote_debug
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_shop_quote_debug"): return
		_model._shop_quote_debug = value

var _consumed_shop_buy_quote_ids: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_consumed_shop_buy_quote_ids") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._consumed_shop_buy_quote_ids
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_consumed_shop_buy_quote_ids"): return
		_model._consumed_shop_buy_quote_ids = value

var _shop_buy_quote_serial: int:
	get: return _source_domain_gate.read_original_profile_view("_shop_buy_quote_serial") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._shop_buy_quote_serial
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_shop_buy_quote_serial"): return
		_model._shop_buy_quote_serial = value

var _shop_pricing_session_nonce: String:
	get: return _source_domain_gate.read_original_profile_view("_shop_pricing_session_nonce") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._shop_pricing_session_nonce
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_shop_pricing_session_nonce"): return
		_model._shop_pricing_session_nonce = value

var last_receive_result: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("last_receive_result") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.last_receive_result
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:last_receive_result"): return
		_model.last_receive_result = value

var _taoist_main_pets_persistence_provider: Callable:
	get: return _source_domain_gate.read_original_profile_view("_taoist_main_pets_persistence_provider") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._taoist_main_pets_persistence_provider
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_taoist_main_pets_persistence_provider"): return
		_model._taoist_main_pets_persistence_provider = value

var _test_force_atomic_write_failure: bool:
	get: return _source_domain_gate.read_original_profile_view("_test_force_atomic_write_failure") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._test_force_atomic_write_failure
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_test_force_atomic_write_failure"): return
		_model._test_force_atomic_write_failure = value

var temporary_item_buffs: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("temporary_item_buffs") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.temporary_item_buffs
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:temporary_item_buffs"): return
		_model.temporary_item_buffs = value
signal temporary_item_buff_expired(entity_id: String)

var temporary_item_buff_revision: int:
	get: return _source_domain_gate.read_original_profile_view("temporary_item_buff_revision") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model.temporary_item_buff_revision
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:temporary_item_buff_revision"): return
		_model.temporary_item_buff_revision = value

func _pump_persistence_receipts() -> void:
	# Prepared admission already verified old writers terminal. The original
	# ALWAYS child remains a Main callback, but all new durable receipts belong
	# to S after handoff. It must not run the retired model or fabricate a P.
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN": return
	_model.service_receipts()

func quote_item_transaction(request: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("quote_item_transaction")
	return _model.quote_item_transaction(request)

func quote_new_item_transaction(request: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("quote_new_item_transaction")
	return _model.quote_new_item_transaction(request)

func commit_item_transaction(quote: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("commit_item_transaction")
	return _model.commit_item_transaction(quote)

func _advance_durability_runtime(delta: float) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_advance_durability_runtime")
		return
	_model._advance_durability_runtime(delta)

func _clear_pending_durability_runtime() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_clear_pending_durability_runtime")
		return
	_model._clear_pending_durability_runtime()

func begin_startup_save_upgrade() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("begin_startup_save_upgrade")
		return
	_model.begin_startup_save_upgrade()

func _startup_upgrade_sources() -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_upgrade_sources")
	return _model._startup_upgrade_sources()

func _startup_upgrade_read(path: String, validator := Callable(), recover_relics := false, profile_candidates: Dictionary = {}) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_upgrade_read")
	return _model._startup_upgrade_read(path, validator, recover_relics, profile_candidates)

func _startup_standardize_noncore_profile(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_standardize_noncore_profile")
	return _model._startup_standardize_noncore_profile(document)

func _startup_standardize_shared_ledger(document: Dictionary, profiles: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_standardize_shared_ledger")
	return _model._startup_standardize_shared_ledger(document, profiles)

func _startup_upgrade_preflight() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_upgrade_preflight")
	return _model._startup_upgrade_preflight()

func _startup_relic_recovery_unchanged(recovery: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_relic_recovery_unchanged")
	return _model._startup_relic_recovery_unchanged(recovery)

func _startup_relic_recovery_guard(_identity: Dictionary, recovery: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_relic_recovery_guard")
	return _model._startup_relic_recovery_guard(_identity, recovery)

func _startup_apply_relic_recoveries(recoveries: Array, backup: RefCounted) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_apply_relic_recoveries")
	return _model._startup_apply_relic_recoveries(recoveries, backup)

func _startup_upgrade_fail(reason: String, path := "") -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_startup_upgrade_fail")
	return _model._startup_upgrade_fail(reason, path)

func finish_startup_save_upgrade() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("finish_startup_save_upgrade")
	return _model.finish_startup_save_upgrade()

func reset_progress(emit_updates := true, recompute_stats := true) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("reset_progress")
		return
	_model.reset_progress(emit_updates, recompute_stats)

func set_profession_identity(value: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("set_profession_identity")
	return _model.set_profession_identity(value)

func select_profession(value: String) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("select_profession")
	return _model.select_profession(value)

func set_later_content_enabled(enabled: bool) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("set_later_content_enabled")
	return _model.set_later_content_enabled(enabled)

func _commit_later_content_field(enabled: bool) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_commit_later_content_field")
		return
	_model._commit_later_content_field(enabled)

func add_item(item_name: String, amount := 1) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("add_item")
	return _model.add_item(item_name, amount)

func can_receive(item_name: String, amount := 1) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("can_receive")
	return _model.can_receive(item_name, amount)

func can_receive_record(record: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("can_receive_record")
	return _model.can_receive_record(record)

func receive(item_name: String, amount := 1, commit := true) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("receive")
	return _model.receive(item_name, amount, commit)

func _add_item_without_commit(item_name: String, amount: int) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_add_item_without_commit")
	return _model._add_item_without_commit(item_name, amount)

func receive_record(record: Dictionary, commit := true) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("receive_record")
	return _model.receive_record(record, commit)

func _build_receive_result(item_name: String, amount: int, base_inventory: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_build_receive_result")
	return _model._build_receive_result(item_name, amount, base_inventory)

func _build_receive_result_for_record(
	record: Dictionary,
	base_inventory: Array,
	reject_existing_drop_instance := false,
	owned_batch_weight := -1,
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_build_receive_result_for_record")
	return _model._build_receive_result_for_record(record, base_inventory, reject_existing_drop_instance, owned_batch_weight)

func _build_receive_result_for_template(
	item_name: String,
	amount: int,
	catalog_item: Dictionary,
	base_inventory: Array,
	template: Dictionary,
	owned_batch_weight := -1,
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_build_receive_result_for_template")
	return _model._build_receive_result_for_template(item_name, amount, catalog_item, base_inventory, template, owned_batch_weight)

func _receive_failure(reason: String, message: String, before := -1, after := -1, maximum := -1) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_receive_failure")
	return _model._receive_failure(reason, message, before, after, maximum)

func _apply_receive_result(result: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_apply_receive_result")
		return
	_model._apply_receive_result(result)

func _max_stack_for_item(catalog_item: Dictionary) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_max_stack_for_item")
	return _model._max_stack_for_item(catalog_item)

func can_receive_batch(rewards: Array) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("can_receive_batch")
	return _model.can_receive_batch(rewards)

func receive_batch(rewards: Array, commit := true) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("receive_batch")
	return _model.receive_batch(rewards, commit)

func _build_receive_batch_result(rewards: Array, base_inventory: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_build_receive_batch_result")
	return _model._build_receive_batch_result(rewards, base_inventory)

func can_credit_gold(amount: Variant, balance := -1) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("can_credit_gold")
	return _model.can_credit_gold(amount, balance)

func _gold_load_projection(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_gold_load_projection")
	return _model._gold_load_projection(document)

func add_gold(amount: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("add_gold")
	return _model.add_gold(amount)

func spend_gold(amount: int) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("spend_gold")
	return _model.spend_gold(amount)

func shared_gold_balance() -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("shared_gold_balance")
	return _model.shared_gold_balance()

func shared_gold_view_snapshot() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("shared_gold_view_snapshot")
	return _model.shared_gold_view_snapshot()

func next_shared_gold_transaction_sequence() -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("next_shared_gold_transaction_sequence")
	return _model.next_shared_gold_transaction_sequence()

func _bank_request_preflight(transaction_id: String, transaction_sequence: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_bank_request_preflight")
	return _model._bank_request_preflight(transaction_id, transaction_sequence)

func _shared_gold_plan(deposit: bool, transaction_id: String, transaction_sequence: int, shared: Dictionary, profile: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shared_gold_plan")
	return _model._shared_gold_plan(deposit, transaction_id, transaction_sequence, shared, profile)

func transfer_shared_gold(deposit: bool, transaction_id: String, transaction_sequence: int = -1) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("transfer_shared_gold")
	return _model.transfer_shared_gold(deposit, transaction_id, transaction_sequence)

func create_drop_item_instance(item_record: Dictionary, stable_drop_key: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("create_drop_item_instance")
	return _model.create_drop_item_instance(item_record, stable_drop_key)

func _invalid_drop_instance_record(item_record: Dictionary, reason: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_invalid_drop_instance_record")
	return _model._invalid_drop_instance_record(item_record, reason)

func has_item(item_name: String, amount := 1) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return item_count_by_entity_id(GameData.item_entity_id(item_name)) >= amount
		return _source_domain_gate.reject_legacy_call("has_item")
	return _model.has_item(item_name, amount)

func item_count(item_name: String) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("item_count")
	return _model.item_count(item_name)

func inventory_occupied_count(records: Array = inventory) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S" and records == inventory: return _source_domain_gate.read_original_profile_query(&"inventory_occupied_count")
		return _source_domain_gate.reject_legacy_call("inventory_occupied_count")
	return _model.inventory_occupied_count(records)

func warehouse_occupied_count(records: Array = warehouse_inventory) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("warehouse_occupied_count")
	return _model.warehouse_occupied_count(records)

func _inventory_slot_is_occupied(record: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_inventory_slot_is_occupied")
	return _model._inventory_slot_is_occupied(record)

func _first_free_inventory_slot(records: Array) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_first_free_inventory_slot")
	return _model._first_free_inventory_slot(records)

func _place_inventory_record_in_first_free_slot(records: Array, record: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_place_inventory_record_in_first_free_slot")
	return _model._place_inventory_record_in_first_free_slot(records, record)

func _clear_inventory_slot(records: Array, index: int) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_clear_inventory_slot")
		return
	_model._clear_inventory_slot(records, index)

func _trim_inventory_empty_tail(records: Array = inventory) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_trim_inventory_empty_tail")
		return
	_model._trim_inventory_empty_tail(records)

func remove_item(item_name: String, amount := 1) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("remove_item")
	return _model.remove_item(item_name, amount)

func _consume_inventory_index(index: int, amount := 1, save_in_background := false) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_consume_inventory_index")
	return _model._consume_inventory_index(index, amount, save_in_background)

func _consume_inventory_index_without_commit(index: int, amount := 1) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_consume_inventory_index_without_commit")
	return _model._consume_inventory_index_without_commit(index, amount)

func destroy_inventory_indices(indices: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("destroy_inventory_indices")
	return _model.destroy_inventory_indices(indices)

func sort_inventory_deterministic() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("sort_inventory_deterministic")
	return _model.sort_inventory_deterministic()

func _inventory_records_mergeable(a: Dictionary, b: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_inventory_records_mergeable")
	return _model._inventory_records_mergeable(a, b)

func shop_sell_quotes(items: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("shop_sell_quotes")
	return _model.shop_sell_quotes(items)

func shop_buy_quotes(stock: Array, context := {}) -> Array:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("shop_buy_quotes")
	return _model.shop_buy_quotes(stock, context)

func _build_shop_buy_quotes(stock: Array, context: Dictionary, quote_serial: int, only_stock_index: int = -1) -> Array:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_build_shop_buy_quotes")
	return _model._build_shop_buy_quotes(stock, context, quote_serial, only_stock_index)

func buy_shop_item(request: Dictionary, stock: Array, context := {}) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("buy_shop_item")
	return _model.buy_shop_item(request, stock, context)

func _shop_buy_result(success: bool, message: String, stock: Array, context: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_buy_result")
	return _model._shop_buy_result(success, message, stock, context)

func _forge_service():
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_forge_service")
	return _model._forge_service()

func quote_forge(target_index: int, iron_index: int, accessory_a_index: int, accessory_b_index: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("quote_forge")
	return _model.quote_forge(target_index, iron_index, accessory_a_index, accessory_b_index)

func quote_forge_tray() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("quote_forge_tray")
	return _model.quote_forge_tray()

func commit_forge(quote: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("commit_forge")
	return _model.commit_forge(quote)

func _relic_service():
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_relic_service")
	return _model._relic_service()

func quote_relic_synthesis(item_id: int, material_indices: Array[int], profession := "") -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("quote_relic_synthesis")
	return _model.quote_relic_synthesis(item_id, material_indices, profession)

func commit_relic_synthesis(quote: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("commit_relic_synthesis")
	return _model.commit_relic_synthesis(quote)

func commit_workbench_immediate(mode: String, quote: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("commit_workbench_immediate")
	return await _model.commit_workbench_immediate(mode, quote)

func _empty_workbench_tray() -> Array[Dictionary]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_empty_workbench_tray")
	return _model._empty_workbench_tray()

func _load_workbench_tray(value: Variant) -> Array[Dictionary]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_load_workbench_tray")
	return _model._load_workbench_tray(value)

func workbench_tray(mode: String) -> Array[Dictionary]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S":
			var result: Array[Dictionary] = []
			if mode in ["forge","synthesis"]:
				result.assign(_source_domain_gate.read_original_profile_view(&"forge_tray" if mode == "forge" else &"synthesis_tray").duplicate(true))
			return result
		return _source_domain_gate.reject_legacy_call("workbench_tray")
	return _model.workbench_tray(mode)

func place_workbench_item(mode: String, slot: int, inventory_index: int, save_in_background := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("place_workbench_item")
	return _model.place_workbench_item(mode, slot, inventory_index, save_in_background)

func take_workbench_item(mode: String, slot: int, save_in_background := false, destination_slot := -1) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("take_workbench_item")
	return _model.take_workbench_item(mode, slot, save_in_background, destination_slot)

func transfer_workbench_immediate(mode: String, slot: int, inventory_index := -1, destination_slot := -1) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("transfer_workbench_immediate")
	return await _model.transfer_workbench_immediate(mode, slot, inventory_index, destination_slot)

func _begin_live_workbench_transaction() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_begin_live_workbench_transaction")
	return await _model._begin_live_workbench_transaction()

func configure_relic_roll_rng(rng: RandomNumberGenerator) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("configure_relic_roll_rng")
		return
	_model.configure_relic_roll_rng(rng)

func configure_relic_proc_rng(rng: RandomNumberGenerator) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("configure_relic_proc_rng")
		return
	_model.configure_relic_proc_rng(rng)

func sell_inventory_item(request: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("sell_inventory_item")
	return _model.sell_inventory_item(request)

func sell_inventory_items(requests: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("sell_inventory_items")
	return _model.sell_inventory_items(requests)

func test_transaction_debug_reset() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("test_transaction_debug_reset")
		return
	_model.test_transaction_debug_reset()

func test_transaction_debug_snapshot() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("test_transaction_debug_snapshot")
	return _model.test_transaction_debug_snapshot()

func test_shop_quote_debug_reset() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("test_shop_quote_debug_reset")
		return
	_model.test_shop_quote_debug_reset()

func test_shop_quote_debug_snapshot() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("test_shop_quote_debug_snapshot")
	return _model.test_shop_quote_debug_snapshot()

func _new_shop_quote_lookup_cache() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_new_shop_quote_lookup_cache")
	return _model._new_shop_quote_lookup_cache()

func _shop_sell_merchant_context(
	request: Dictionary, lookup_cache: Dictionary
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_sell_merchant_context")
	return _model._shop_sell_merchant_context(request, lookup_cache)

func _shop_sell_catalog(item_name: String, lookup_cache: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_sell_catalog")
	return _model._shop_sell_catalog(item_name, lookup_cache)

func _shop_sell_price_record(item_name: String, lookup_cache: Dictionary, item_ref: Variant = null) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_sell_price_record")
	return _model._shop_sell_price_record(item_name, lookup_cache, item_ref)

func _shop_sell_base_price_cached(
	item_name: String, price_record: Dictionary, lookup_cache: Dictionary
) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_sell_base_price_cached")
	return _model._shop_sell_base_price_cached(item_name, price_record, lookup_cache)

func _shop_sell_quote(request: Dictionary, lookup_cache := {}) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_sell_quote")
	return _model._shop_sell_quote(request, lookup_cache)

func _shop_sell_base_price(item_name: String, _catalog: Dictionary) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_sell_base_price")
	return _model._shop_sell_base_price(item_name, _catalog)

func _shop_sell_risk_flags(
	record: Dictionary,
	catalog: Dictionary,
	base_price: int
) -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_sell_risk_flags")
	return _model._shop_sell_risk_flags(record, catalog, base_price)

func _shop_sell_result(success: bool, message: String, merchant_id := "") -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shop_sell_result")
	return _model._shop_sell_result(success, message, merchant_id)

func _current_shop_sell_quote_items(merchant_id := "") -> Array:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_current_shop_sell_quote_items")
	return _model._current_shop_sell_quote_items(merchant_id)

func _item_audio_identity(item_ref: Variant) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_item_audio_identity")
	return _model._item_audio_identity(item_ref)

func _item_audio_nonnegative_integer(value: Variant) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_item_audio_nonnegative_integer")
	return _model._item_audio_nonnegative_integer(value)

func _emit_item_audio_committed(item_ref: Variant, semantic_event: String) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_emit_item_audio_committed")
		return
	_model._emit_item_audio_committed(item_ref, semantic_event)

func _last_item_commit_succeeded() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_last_item_commit_succeeded")
	return _model._last_item_commit_succeeded()

func _use_item_success(message: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_use_item_success")
	return _model._use_item_success(message)

func _use_item_failure(reason: String, message: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_use_item_failure")
	return _model._use_item_failure(reason, message)

func use_inventory_index(index: int) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("use_inventory_index")
	return _model.use_inventory_index(index)

func use_inventory_index_result(index: int, save_in_background := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("use_inventory_index_result")
	return _model.use_inventory_index_result(index, save_in_background)

func _use_weapon_repair_oil_item_result(index: int, full_repair: bool, save_in_background := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_use_weapon_repair_oil_item_result")
	return _model._use_weapon_repair_oil_item_result(index, full_repair, save_in_background)

func apply_weapon_repair_oil(full_repair: bool) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_weapon_repair_oil")
	return _model.apply_weapon_repair_oil(full_repair)

func apply_weapon_repair_oil_result(full_repair: bool) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_weapon_repair_oil_result")
	return _model.apply_weapon_repair_oil_result(full_repair)

func _apply_weapon_repair_oil_without_commit(
	weapon_value: Dictionary, full_repair: bool
) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_apply_weapon_repair_oil_without_commit")
		return
	_model._apply_weapon_repair_oil_without_commit(weapon_value, full_repair)

func _make_item_instance(item_name: String, catalog_item: Dictionary, instance_serial := -1, roll_relic := true) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_make_item_instance")
	return _model._make_item_instance(item_name, catalog_item, instance_serial, roll_relic)

func _with_item_identity(record: Dictionary, catalog: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_with_item_identity")
	return _model._with_item_identity(record, catalog)

func configure_blessing_oil_rng(rng: RandomNumberGenerator) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("configure_blessing_oil_rng")
		return
	_model.configure_blessing_oil_rng(rng)

func _blessing_oil_rolls(
	weapon_value: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_blessing_oil_rolls")
	return _model._blessing_oil_rolls(weapon_value, rng)

func _apply_blessing_oil_effect_with_rolls(
	unlucky_roll: int,
	success_roll: int,
	upper_stage_roll := -1
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_apply_blessing_oil_effect_with_rolls")
	return _model._apply_blessing_oil_effect_with_rolls(unlucky_roll, success_roll, upper_stage_roll)

func apply_blessing_oil(rng: RandomNumberGenerator) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_blessing_oil")
	return _model.apply_blessing_oil(rng)

func apply_blessing_oil_with_rolls(unlucky_roll: int, success_roll: int, upper_stage_roll := -1) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_blessing_oil_with_rolls")
	return _model.apply_blessing_oil_with_rolls(unlucky_roll, success_roll, upper_stage_roll)

func use_blessing_oil_inventory_index(
	index: int,
	rng: RandomNumberGenerator,
	save_in_background := false
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("use_blessing_oil_inventory_index")
	return _model.use_blessing_oil_inventory_index(index, rng, save_in_background)

func use_blessing_oil_inventory_index_with_rolls(
	index: int,
	unlucky_roll: int,
	success_roll: int,
	upper_stage_roll := -1,
	save_in_background := false
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("use_blessing_oil_inventory_index_with_rolls")
	return _model.use_blessing_oil_inventory_index_with_rolls(index, unlucky_roll, success_roll, upper_stage_roll, save_in_background)

func lose_gold_percent(rate: float) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("lose_gold_percent")
	return _model.lose_gold_percent(rate)

func add_experience(amount: int) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("add_experience")
		return
	_model.add_experience(amount)

func record_kill_and_experience(monster_name: String, amount: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("record_kill_and_experience")
	return _model.record_kill_and_experience(monster_name, amount)

func _plan_kill_rewards(kills: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_plan_kill_rewards")
	return _model._plan_kill_rewards(kills)

func _apply_kill_reward_plan(plan: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_apply_kill_reward_plan")
		return
	_model._apply_kill_reward_plan(plan)

func prepare_death_settlement(kills: Array, world_upserts: Dictionary, origin_guard := Callable()) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("prepare_death_settlement")
	return _model.prepare_death_settlement(kills, world_upserts, origin_guard)

func _death_request_context_matches(identity: Dictionary, plan: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_death_request_context_matches")
	return _model._death_request_context_matches(identity, plan)

func finish_prepared_death_settlement(plan: Dictionary, wait := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("finish_prepared_death_settlement")
	return _model.finish_prepared_death_settlement(plan, wait)

func _complete_background_death(receipt: Dictionary, plan: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_complete_background_death")
		return
	_model._complete_background_death(receipt, plan)

func record_kills_and_experience_batch(
	kills: Array,
	force_save := false,
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("record_kills_and_experience_batch")
	return _model.record_kills_and_experience_batch(kills, force_save)

func apply_death_experience_penalty() -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_death_experience_penalty")
	return _model.apply_death_experience_penalty()

func experience_to_next_level() -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return _source_domain_gate.read_original_profile_query(&"experience_to_next_level")
		return _source_domain_gate.reject_legacy_call("experience_to_next_level")
	return _model.experience_to_next_level()

func _experience_to_next_level_for_level(target_level: int) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_experience_to_next_level_for_level")
	return _model._experience_to_next_level_for_level(target_level)

func _gameplay_experience_threshold(source_experience: int) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_gameplay_experience_threshold")
	return _model._gameplay_experience_threshold(source_experience)

func equip_inventory_index_result(index: int, preferred_slot := "", expected_instance_id := "") -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("equip_inventory_index_result")
	return _model.equip_inventory_index_result(index, preferred_slot, expected_instance_id)

func unequip_to_inventory_slot(slot: String, inventory_slot: int, expected_instance_id := "") -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("unequip_to_inventory_slot")
	return _model.unequip_to_inventory_slot(slot, inventory_slot, expected_instance_id)

func equip_inventory_index(index: int, preferred_slot := "") -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("equip_inventory_index")
	return _model.equip_inventory_index(index, preferred_slot)

func unequip_slot(slot: String, destination_slot := -1) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("unequip_slot")
	return _model.unequip_slot(slot, destination_slot)

func learn_skill(skill_name: String, inventory_index := -1) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("learn_skill")
	return _model.learn_skill(skill_name, inventory_index)

func _learn_skill_result(skill_ref: String, inventory_index := -1, save_in_background := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_learn_skill_result")
	return _model._learn_skill_result(skill_ref, inventory_index, save_in_background)

func is_skill_learned(skill_name: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return bool(_source_domain_gate.read_original_profile_query(&"skill_facts").get(preload("res://scripts/skills/skill_data_loader.gd").entity_skill_id(skill_name),{}).get("learned",false))
		return _source_domain_gate.reject_legacy_call("is_skill_learned")
	return _model.is_skill_learned(skill_name)

func accept_quest(quest_id: String) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("accept_quest")
	return _model.accept_quest(quest_id)

func abandon_quest(quest_id: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("abandon_quest")
	return _model.abandon_quest(quest_id)

func sort_warehouse(page := 0) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("sort_warehouse")
	return _model.sort_warehouse(page)

func record_kill(monster_name: String) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("record_kill")
		return
	_model.record_kill(monster_name)

func claim_quest(quest_id: String) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("claim_quest")
	return _model.claim_quest(quest_id)

func quest_progress(quest_id: String) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("quest_progress")
	return _model.quest_progress(quest_id)

func current_bich_quest_id() -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return _source_domain_gate.read_original_profile_query(&"current_bich_quest_id")
		return _source_domain_gate.reject_legacy_call("current_bich_quest_id")
	return _model.current_bich_quest_id()

func quest_objective_lines(quest_id: String) -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S":
			var result: Array[String] = []
			result.assign(_source_domain_gate.read_original_profile_query(&"quest_facts").get(quest_id,{}).get("lines",[]))
			return result
		return _source_domain_gate.reject_legacy_call("quest_objective_lines")
	return _model.quest_objective_lines(quest_id)

func quest_reward_label(quest_id: String) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return str(_source_domain_gate.read_original_profile_query(&"quest_facts").get(quest_id,{}).get("reward",""))
		return _source_domain_gate.reject_legacy_call("quest_reward_label")
	return _model.quest_reward_label(quest_id)

func _quest_monster_matches(monster_name: String, objective_name: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_quest_monster_matches")
	return _model._quest_monster_matches(monster_name, objective_name)

func _quest_objectives_complete(quest: Dictionary, state: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_quest_objectives_complete")
	return _model._quest_objectives_complete(quest, state)

func _grant_quest_item_without_commit(item_name: String, amount: int) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_grant_quest_item_without_commit")
		return
	_model._grant_quest_item_without_commit(item_name, amount)

func _migrate_quest_states() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_migrate_quest_states")
		return
	_model._migrate_quest_states()

func recalculate_stats(emit_profile_change := true, report_failure := true) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("recalculate_stats")
	return _model.recalculate_stats(emit_profile_change, report_failure)

func _on_feature_catalog_changed() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_on_feature_catalog_changed")
		return
	_model._on_feature_catalog_changed()

func _prepare_feature_configuration(configuration: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_prepare_feature_configuration")
	return _model._prepare_feature_configuration(configuration)

func _commit_feature_configuration(prepared: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_commit_feature_configuration")
		return
	_model._commit_feature_configuration(prepared)

func _feature_item_eligible(instance: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_feature_item_eligible")
	return _model._feature_item_eligible(instance)

func _synchronize_feature_loadout(base_stats: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_synchronize_feature_loadout")
	return _model._synchronize_feature_loadout(base_stats)

func feature_bundle() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("feature_bundle")
	return _model.feature_bundle()

func effective_skill_definition(skill_name_or_id: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("effective_skill_definition")
	return _model.effective_skill_definition(skill_name_or_id)

func action_configuration_versions() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("action_configuration_versions")
	return _model.action_configuration_versions()

func _sync_relic_proc_equipment() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_sync_relic_proc_equipment")
	return _model._sync_relic_proc_equipment()

func try_trigger_relic_proc() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("try_trigger_relic_proc")
	return _model.try_trigger_relic_proc()

func advance_relic_proc(delta: float) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("advance_relic_proc")
		return
	_model.advance_relic_proc(delta)

func relic_proc_status() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("relic_proc_status")
	return _model.relic_proc_status()

func _apply_relic_proc_stats(result: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_apply_relic_proc_stats")
		return
	_model._apply_relic_proc_stats(result)

func has_special_effect(effect_id: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("has_special_effect")
	return _model.has_special_effect(effect_id)

func effective_skill_level(skill_name: String) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return int(_source_domain_gate.read_original_profile_query(&"skill_facts").get(preload("res://scripts/skills/skill_data_loader.gd").entity_skill_id(skill_name),{}).get("level",0))
		return _source_domain_gate.reject_legacy_call("effective_skill_level")
	return _model.effective_skill_level(skill_name)

func equipment_granted_skill_ids() -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("equipment_granted_skill_ids")
	return _model.equipment_granted_skill_ids()

func is_skill_available(skill_name_or_id: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return bool(_source_domain_gate.read_original_profile_query(&"skill_facts").get(preload("res://scripts/skills/skill_data_loader.gd").entity_skill_id(skill_name_or_id),{}).get("available",false))
		return _source_domain_gate.reject_legacy_call("is_skill_available")
	return _model.is_skill_available(skill_name_or_id)

func available_skill_ids() -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S":
			var result: Array[String] = []
			result.assign(_source_domain_gate.read_original_profile_query(&"available_skill_ids"))
			return result
		return _source_domain_gate.reject_legacy_call("available_skill_ids")
	return _model.available_skill_ids()

func skill_assignment_roster() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("skill_assignment_roster")
	return _model.skill_assignment_roster()

func _prune_unavailable_equipment_skill_bindings() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_prune_unavailable_equipment_skill_bindings")
		return
	_model._prune_unavailable_equipment_skill_bindings()

func _equipment_skill_level_bonus(stable_skill_id: String) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_equipment_skill_level_bonus")
	return _model._equipment_skill_level_bonus(stable_skill_id)

func skill_progression_snapshot() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("skill_progression_snapshot")
	return _model.skill_progression_snapshot()

func apply_skill_proficiency_event(skill_name_or_id: String, event_id: String, seed_value: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_skill_proficiency_event")
	return _model.apply_skill_proficiency_event(skill_name_or_id, event_id, seed_value)

func canonical_skill_resource_context(stable_skill_id: String, current_mana: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("canonical_skill_resource_context")
	return _model.canonical_skill_resource_context(stable_skill_id, current_mana)

func canonical_material_item_name(material_id: String) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("canonical_material_item_name")
	return _model.canonical_material_item_name(material_id)

func _refresh_skill_identity_projection() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_refresh_skill_identity_projection")
		return
	_model._refresh_skill_identity_projection()

func available_special_actions() -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("available_special_actions")
	return _model.available_special_actions()

func damage_special_effect_item(effect_id: String, amount := 1) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("damage_special_effect_item")
		return
	_model.damage_special_effect_item(effect_id, amount)

func _add_nullable_stat(target: Dictionary, key: String, value: Variant) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_add_nullable_stat")
		return
	_model._add_nullable_stat(target, key, value)

func current_wear_weight(excluded_slot := "") -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("current_wear_weight")
	return _model.current_wear_weight(excluded_slot)

func _loot_inventory_catalog_record(item_ref: Variant) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_loot_inventory_catalog_record")
	return _model._loot_inventory_catalog_record(item_ref)

func _prewarm_loot_inventory_catalog(records: Array) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_prewarm_loot_inventory_catalog")
		return
	_model._prewarm_loot_inventory_catalog(records)

func inventory_weight(records: Array = inventory) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S" and records == inventory: return _source_domain_gate.read_original_profile_query(&"inventory_weight")
		return _source_domain_gate.reject_legacy_call("inventory_weight")
	return _model.inventory_weight(records)

func max_inventory_weight() -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return _source_domain_gate.read_original_profile_query(&"max_inventory_weight")
		return _source_domain_gate.reject_legacy_call("max_inventory_weight")
	return _model.max_inventory_weight()

func _active_double_weight_effect() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_active_double_weight_effect")
	return _model._active_double_weight_effect()

func _slots_for_category(category: String) -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_slots_for_category")
	return _model._slots_for_category(category)

func _choose_equipment_slot(category: String, preferred_slot := "") -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_choose_equipment_slot")
	return _model._choose_equipment_slot(category, preferred_slot)

func _default_equip_cycle_cursor() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_default_equip_cycle_cursor")
	return _model._default_equip_cycle_cursor()

func _normalized_equip_cycle_cursor(saved_value: Variant) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_normalized_equip_cycle_cursor")
	return _model._normalized_equip_cycle_cursor(saved_value)

func _advance_equip_cycle_cursor(category: String, equipped_slot: String) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_advance_equip_cycle_cursor")
		return
	_model._advance_equip_cycle_cursor(category, equipped_slot)

func _empty_equipment() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_empty_equipment")
	return _model._empty_equipment()

func _equipment_instance_from_saved(saved_value: Variant) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_equipment_instance_from_saved")
	return _model._equipment_instance_from_saved(saved_value)

func _ensure_raw_durability_fields(instance: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_ensure_raw_durability_fields")
	return _model._ensure_raw_durability_fields(instance)

func _adopt_legacy_durability_compatibility_override(instance: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_adopt_legacy_durability_compatibility_override")
		return
	_model._adopt_legacy_durability_compatibility_override(instance)

func _sync_durability_compatibility_fields(instance: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_sync_durability_compatibility_fields")
		return
	_model._sync_durability_compatibility_fields(instance)

func _has_positive_raw_durability(instance: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_has_positive_raw_durability")
	return _model._has_positive_raw_durability(instance)

func _migrate_item_collection_durability(records: Array) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_migrate_item_collection_durability")
	return _model._migrate_item_collection_durability(records)

func migrate_equipment_slots(saved_equipment: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("migrate_equipment_slots")
	return _model.migrate_equipment_slots(saved_equipment)

func damage_equipment_durability(slot: String, amount := 1) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("damage_equipment_durability")
		return
	_model.damage_equipment_durability(slot, amount)

func _damage_equipment_durability_raw(
	slot: String,
	amount_raw: int,
	commit_individually := false
) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_damage_equipment_durability_raw")
	return _model._damage_equipment_durability_raw(slot, amount_raw, commit_individually)

func apply_durability_event(event_id: String, context := {}) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_durability_event")
	return _model.apply_durability_event(event_id, context)

func _durability_roll(context: Dictionary, key: String, minimum: int, maximum: int) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_durability_roll")
	return _model._durability_roll(context, key, minimum, maximum)

func _weapon_strong(weapon: Dictionary, context: Dictionary) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_weapon_strong")
	return _model._weapon_strong(weapon, context)

func repair_cost(context := {}) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("repair_cost")
	return _model.repair_cost(context)

func _repair_plan(context := {}) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_repair_plan")
	return _model._repair_plan(context)

func repair_all_equipment(context := {}) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("repair_all_equipment")
	return _model.repair_all_equipment(context)

func _authoritative_merchant_context(context: Variant) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_authoritative_merchant_context")
	return _model._authoritative_merchant_context(context)

func _maximum_affordable_repair_raw_quote(
	price_record: Dictionary,
	catalog: Dictionary,
	instance: Dictionary,
	maximum_amount_raw: int,
	budget: int,
	context: Dictionary
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_maximum_affordable_repair_raw_quote")
	return _model._maximum_affordable_repair_raw_quote(price_record, catalog, instance, maximum_amount_raw, budget, context)

func _profile_path(profile_id: String) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_profile_path")
	return _model._profile_path(profile_id)

func _world_clock_directory() -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_world_clock_directory")
	return _model._world_clock_directory()

func _world_clock_path(profile_id: String, generation := "") -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_world_clock_path")
	return _model._world_clock_path(profile_id, generation)

func _death_event_root() -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_death_event_root")
	return _model._death_event_root()

func _death_event_directory(profile_id: String, generation := "") -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_death_event_directory")
	return _model._death_event_directory(profile_id, generation)

func _death_event_path(profile_id: String, sequence: int, generation := "") -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_death_event_path")
	return _model._death_event_path(profile_id, sequence, generation)

var _json_parse_snapshots: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_json_parse_snapshots") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._json_parse_snapshots
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_json_parse_snapshots"): return
		_model._json_parse_snapshots = value

func _read_json_document(path: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_read_json_document")
	return _model._read_json_document(path)

func _validation_result(valid: bool, reason := "", terminal := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validation_result")
	return _model._validation_result(valid, reason, terminal)

func _is_json_number(value: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_is_json_number")
	return _model._is_json_number(value)

func _is_integral_json_number(value: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_is_integral_json_number")
	return _model._is_integral_json_number(value)

func _valid_bank_transaction_id(transaction_id: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_valid_bank_transaction_id")
	return _model._valid_bank_transaction_id(transaction_id)

func _valid_sha256_text(value: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_valid_sha256_text")
	return _model._valid_sha256_text(value)

func _bounded_bank_transaction_history(
	current: Dictionary,
	transaction_id: String,
	record: Dictionary,
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_bounded_bank_transaction_history")
	return _model._bounded_bank_transaction_history(current, transaction_id, record)

func _validate_bank_transaction_history(document: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_bank_transaction_history")
	return _model._validate_bank_transaction_history(document)

func _validate_gold_overflow_records(document: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_gold_overflow_records")
	return _model._validate_gold_overflow_records(document)

func _valid_saved_position(value: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_valid_saved_position")
	return _model._valid_saved_position(value)

func _validate_saved_item_records(value: Variant, capacity: int) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_saved_item_records")
	return _model._validate_saved_item_records(value, capacity)

func _validate_saved_item_records_uncached(value: Variant, capacity: int) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_saved_item_records_uncached")
	return _model._validate_saved_item_records_uncached(value, capacity)

func _validate_saved_equipment(value: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_saved_equipment")
	return _model._validate_saved_equipment(value)

func _validated_drop_instance_id(record: Dictionary) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validated_drop_instance_id")
	return _model._validated_drop_instance_id(record)

func _validated_persisted_instance_id(record: Dictionary) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validated_persisted_instance_id")
	return _model._validated_persisted_instance_id(record)

func _validate_profile_drop_instance_uniqueness(document: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_profile_drop_instance_uniqueness")
	return _model._validate_profile_drop_instance_uniqueness(document)

func _profile_and_shared_drop_instances_are_disjoint(
	profile_document: Dictionary,
	shared_document: Dictionary,
) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_profile_and_shared_drop_instances_are_disjoint")
	return _model._profile_and_shared_drop_instances_are_disjoint(profile_document, shared_document)

func _validate_extended_item_ownership(document: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_extended_item_ownership")
	return _model._validate_extended_item_ownership(document)

func _validate_profile_document_status(
	document: Dictionary,
	expected_profile_id: String,
	allow_missing_identity: bool
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_profile_document_status")
	return _model._validate_profile_document_status(document, expected_profile_id, allow_missing_identity)

func _validate_profile_index_document_status(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_profile_index_document_status")
	return _model._validate_profile_index_document_status(document)

func _validate_shared_warehouse_document_status(document: Dictionary, profile_candidates: Dictionary = {}) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_shared_warehouse_document_status")
	return _model._validate_shared_warehouse_document_status(document, profile_candidates)

func _json_validator_for_path(path: String) -> Callable:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_json_validator_for_path")
	return _model._json_validator_for_path(path)

func _world_state_owner_is_unsupported(value: Variant) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_world_state_owner_is_unsupported")
	return _model._world_state_owner_is_unsupported(value)

func _validate_world_clock_document_status(document: Dictionary, profile_id: String, generation := "") -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_world_clock_document_status")
	return _model._validate_world_clock_document_status(document, profile_id, generation)

func _validate_death_event_document_status(
	document: Dictionary,
	profile_id: String,
	sequence_text: String,
	generation := "",
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_death_event_document_status")
	return _model._validate_death_event_document_status(document, profile_id, sequence_text, generation)

func _read_world_clock_replay(profile_document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_read_world_clock_replay")
	return _model._read_world_clock_replay(profile_document)

func _archive_legacy_world_clock_profile(profile_document: Dictionary) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_archive_legacy_world_clock_profile")
	return _model._archive_legacy_world_clock_profile(profile_document)

func _prepare_world_clock_profile(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_prepare_world_clock_profile")
	return _model._prepare_world_clock_profile(document)

func _complete_world_clock_import_backup(document: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_complete_world_clock_import_backup")
	return _model._complete_world_clock_import_backup(document)

func _checkpoint_world_clock() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_checkpoint_world_clock")
	return _model._checkpoint_world_clock()

func _checkpoint_world_clock_snapshot(
	profile_id: String, generation: String, state: Dictionary,
	latest_sequence: int, snapshot_sequence: int, backup_sequence: int,
	dirty: bool,
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_checkpoint_world_clock_snapshot")
	return _model._checkpoint_world_clock_snapshot(profile_id, generation, state, latest_sequence, snapshot_sequence, backup_sequence, dirty)

func _queue_world_clock_cleanup() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_queue_world_clock_cleanup")
		return
	_model._queue_world_clock_cleanup()

func _clock_cleanup_covers(existing: Dictionary, request: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_clock_cleanup_covers")
	return _model._clock_cleanup_covers(existing, request)

func _start_world_clock_cleanup(request: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_start_world_clock_cleanup")
		return
	_model._start_world_clock_cleanup(request)

func _advance_world_clock_cleanup() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_advance_world_clock_cleanup")
		return
	_model._advance_world_clock_cleanup()

func _commit_death_event() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_commit_death_event")
	return _model._commit_death_event()

func _validate_json_candidate(document: Dictionary, validator: Callable) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_json_candidate")
	return _model._validate_json_candidate(document, validator)

func _next_quarantine_path(path: String) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_next_quarantine_path")
	return _model._next_quarantine_path(path)

func _restore_json_backup(path: String, validator := Callable()) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_restore_json_backup")
	return _model._restore_json_backup(path, validator)

func _read_json_with_status(path: String, validator := Callable()) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_read_json_with_status")
	return _model._read_json_with_status(path, validator)

func _read_json(path: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_read_json")
	return _model._read_json(path)

func _write_json_atomic(path: String, data: Dictionary, preserve_known_wire := false, world_clock_identity: Dictionary = {}) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_write_json_atomic")
	return _model._write_json_atomic(path, data, preserve_known_wire, world_clock_identity)

func _promote_verified_json(path: String, temporary: String, expected_bytes: PackedByteArray, validated_previous_bytes: Variant = null) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_promote_verified_json")
	return _model._promote_verified_json(path, temporary, expected_bytes, validated_previous_bytes)

func _record_background_json_receipt(receipt: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_record_background_json_receipt")
		return
	_model._record_background_json_receipt(receipt)

func _backup_sequence_after_promotion(path: String, previous_sequence: int, current_sequence: int, field: String) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_backup_sequence_after_promotion")
	return _model._backup_sequence_after_promotion(path, previous_sequence, current_sequence, field)

func _file_matches_validated_bytes(path: String, expected: PackedByteArray) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_file_matches_validated_bytes")
	return _model._file_matches_validated_bytes(path, expected)

func _shared_warehouse_empty_document() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shared_warehouse_empty_document")
	return _model._shared_warehouse_empty_document()

var _shared_digest_cache: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_shared_digest_cache") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._shared_digest_cache
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_shared_digest_cache"): return
		_model._shared_digest_cache = value

var _shared_digest_snapshots: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_shared_digest_snapshots") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._shared_digest_snapshots
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_shared_digest_snapshots"): return
		_model._shared_digest_snapshots = value

func _shared_digest(value: Variant) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shared_digest")
	return _model._shared_digest(value)

func _shared_warehouse_read_inventory() -> Array:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shared_warehouse_read_inventory")
	return _model._shared_warehouse_read_inventory()

func _shared_warehouse_test_isolation_enabled() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shared_warehouse_test_isolation_enabled")
	return _model._shared_warehouse_test_isolation_enabled()

func _valid_profile_storage_id(profile_id: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_valid_profile_storage_id")
	return _model._valid_profile_storage_id(profile_id)

func _profile_ids_for_shared_warehouse() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_profile_ids_for_shared_warehouse")
	return _model._profile_ids_for_shared_warehouse()

func _legacy_warehouse_source(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_legacy_warehouse_source")
	return _model._legacy_warehouse_source(document)

func _validate_shared_warehouse_document(document: Dictionary, profile_candidates: Dictionary = {}) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_shared_warehouse_document")
	return _model._validate_shared_warehouse_document(document, profile_candidates)

func _occupied_records(records: Array) -> Array:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_occupied_records")
	return _model._occupied_records(records)

func _initialize_shared_warehouse() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_initialize_shared_warehouse")
	return _model._initialize_shared_warehouse()

func _ensure_shared_warehouse_ready() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_ensure_shared_warehouse_ready")
	return _model._ensure_shared_warehouse_ready()

func _revalidate_shared_warehouse_authority() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_revalidate_shared_warehouse_authority")
	return _model._revalidate_shared_warehouse_authority()

func _bank_fields_snapshot(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_bank_fields_snapshot")
	return _model._bank_fields_snapshot(document)

func _bank_transaction_transition_is_valid(
	profile_id: String,
	before_profile: Dictionary,
	after_profile: Dictionary,
	before_shared: Dictionary,
	after_shared: Dictionary,
) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_bank_transaction_transition_is_valid")
	return _model._bank_transaction_transition_is_valid(profile_id, before_profile, after_profile, before_shared, after_shared)

func _same_item_identity_upgrade(before: Dictionary, after: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_same_item_identity_upgrade")
	return _model._same_item_identity_upgrade(before, after)

func _warehouse_transaction_log_is_valid(log: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_warehouse_transaction_log_is_valid")
	return _model._warehouse_transaction_log_is_valid(log)

func _recover_shared_warehouse_transaction() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_recover_shared_warehouse_transaction")
		return
	_model._recover_shared_warehouse_transaction()

func _remove_persistence_file(path: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_remove_persistence_file")
	return _model._remove_persistence_file(path)

func _shared_document_for_records(records: Array, current_snapshot: Dictionary = {}) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_shared_document_for_records")
	return _model._shared_document_for_records(records, current_snapshot)

func _write_shared_warehouse_document_atomic(document: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_write_shared_warehouse_document_atomic")
	return _model._write_shared_warehouse_document_atomic(document)

func _write_shared_warehouse(records: Array) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_write_shared_warehouse")
	return _model._write_shared_warehouse(records)

func _prepare_character_save_payload(checkpoint_world := true) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_prepare_character_save_payload")
	return _model._prepare_character_save_payload(checkpoint_world)

func save_game(update_profile_index := true, finalize_pending_durability := true, checkpoint_world := true) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("save_game")
	return _model.save_game(update_profile_index, finalize_pending_durability, checkpoint_world)

func device_lab_active_save_document() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("device_lab_active_save_document")
	return _model.device_lab_active_save_document()

func device_lab_apply_save_document(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("device_lab_apply_save_document")
	return _model.device_lab_apply_save_document(document)

func deposit_to_warehouse(inventory_index: int, warehouse_slot: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("deposit_to_warehouse")
	return _model.deposit_to_warehouse(inventory_index, warehouse_slot)

func deposit_to_warehouse_batch(inventory_indices: Array, warehouse_slots: Array, prepare_only := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("deposit_to_warehouse_batch")
	return _model.deposit_to_warehouse_batch(inventory_indices, warehouse_slots, prepare_only)

func withdraw_from_warehouse(warehouse_slot: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("withdraw_from_warehouse")
	return _model.withdraw_from_warehouse(warehouse_slot)

func withdraw_from_warehouse_batch(warehouse_slots: Array, prepare_only := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("withdraw_from_warehouse_batch")
	return _model.withdraw_from_warehouse_batch(warehouse_slots, prepare_only)

func _trim_warehouse_empty_tail() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_trim_warehouse_empty_tail")
		return
	_model._trim_warehouse_empty_tail()

func _validate_device_lab_save_document(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_validate_device_lab_save_document")
	return _model._validate_device_lab_save_document(document)

func _emit_device_lab_state_changed() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_emit_device_lab_state_changed")
		return
	_model._emit_device_lab_state_changed()

func load_save() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("load_save")
		return
	_model.load_save()

func monster_respawn_state_for_restore() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("monster_respawn_state_for_restore")
	return _model.monster_respawn_state_for_restore()

func monster_respawn_entry(
	runtime_map_id: int,
	spawn_slot_id: String
) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("monster_respawn_entry")
	return _model.monster_respawn_entry(runtime_map_id, spawn_slot_id)

func mark_monster_respawn_dead(
	runtime_map_id: int, spawn_slot_id: String, monster_id: int,
	policy_id: String, respawn_at_unix: float,
) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("mark_monster_respawn_dead")
	return _model.mark_monster_respawn_dead(runtime_map_id, spawn_slot_id, monster_id, policy_id, respawn_at_unix)

func clear_monster_respawn_slot(runtime_map_id: int, spawn_slot_id: String) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("clear_monster_respawn_slot")
		return
	_model.clear_monster_respawn_slot(runtime_map_id, spawn_slot_id)

func world_clock_mutation_snapshot() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("world_clock_mutation_snapshot")
	return _model.world_clock_mutation_snapshot()

func restore_world_clock_mutation(snapshot: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("restore_world_clock_mutation")
		return
	_model.restore_world_clock_mutation(snapshot)

func apply_quick_slot_assignment(result: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_quick_slot_assignment")
	return _model.apply_quick_slot_assignment(result)

func apply_skill_button_assignment(result: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_skill_button_assignment")
	return _model.apply_skill_button_assignment(result)

func skill_button_assignments_snapshot() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return _source_domain_gate.read_original_profile_query(&"skill_assignments").duplicate(true)
		return _source_domain_gate.reject_legacy_call("skill_button_assignments_snapshot")
	return _model.skill_button_assignments_snapshot()

func skill_slots_for_group(slot_group: String) -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S":
			var result: Array[String] = []
			result.assign(_source_domain_gate.read_original_profile_query(&"skill_slots").get(slot_group,[]))
			return result
		return _source_domain_gate.reject_legacy_call("skill_slots_for_group")
	return _model.skill_slots_for_group(slot_group)

func skill_name_for_slot(slot_group: String, slot_index: int) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return str(_source_domain_gate.read_original_profile_query(&"slot_names").get("%s:%d" % [slot_group,slot_index],""))
		return _source_domain_gate.reject_legacy_call("skill_name_for_slot")
	return _model.skill_name_for_slot(slot_group, slot_index)

func skill_id_for_slot(slot_group: String, slot_index: int) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("skill_id_for_slot")
	return _model.skill_id_for_slot(slot_group, slot_index)

func _import_skill_slot_ids(source: Array[String]) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_import_skill_slot_ids")
	return _model._import_skill_slot_ids(source)

func _restore_skill_button_assignments(assignments_value: Variant, legacy_center: Array) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_restore_skill_button_assignments")
		return
	_model._restore_skill_button_assignments(assignments_value, legacy_center)

func _normalized_skill_button_assignments(assignments_value: Variant, legacy_center: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_normalized_skill_button_assignments")
	return _model._normalized_skill_button_assignments(assignments_value, legacy_center)

func _normalized_skill_slot_array(value: Variant, expected_size: int) -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_normalized_skill_slot_array")
	return _model._normalized_skill_slot_array(value, expected_size)

func _sync_legacy_quick_slots_from_ring() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_sync_legacy_quick_slots_from_ring")
		return
	_model._sync_legacy_quick_slots_from_ring()

func is_quick_item_candidate(item_name: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("is_quick_item_candidate")
	return _model.is_quick_item_candidate(item_name)

func quick_item_slots_snapshot() -> Array:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("quick_item_slots_snapshot")
	return _model.quick_item_slots_snapshot()

func quick_item_slot_name(slot_index: int) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("quick_item_slot_name")
	return _model.quick_item_slot_name(slot_index)

func assign_quick_item_slot(index: int, item_id: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("assign_quick_item_slot")
	return _model.assign_quick_item_slot(index, item_id)

func use_quick_item_slot(index: int, expected_item_id := "") -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("use_quick_item_slot")
	return _model.use_quick_item_slot(index, expected_item_id)

func _normalized_quick_item_slots(value: Variant) -> Array[String]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_normalized_quick_item_slots")
	return _model._normalized_quick_item_slots(value)

func _inventory_index_by_entity_id(item_id: String) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_inventory_index_by_entity_id")
	return _model._inventory_index_by_entity_id(item_id)

func item_count_by_entity_id(item_id: String) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		if _source_domain_gate.state() == "S": return int(_source_domain_gate.read_original_profile_query(&"item_counts").get(item_id,0))
		return _source_domain_gate.reject_legacy_call("item_count_by_entity_id")
	return _model.item_count_by_entity_id(item_id)

func _inventory_index_by_item_name(item_name: String) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_inventory_index_by_item_name")
	return _model._inventory_index_by_item_name(item_name)

func apply_warrior_runtime_state(snapshot: Dictionary, persist := false) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_warrior_runtime_state")
	return _model.apply_warrior_runtime_state(snapshot, persist)

func warrior_runtime_state_for_restore() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("warrior_runtime_state_for_restore")
	return _model.warrior_runtime_state_for_restore()

func configure_taoist_main_pets_persistence_provider(provider: Callable) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("configure_taoist_main_pets_persistence_provider")
		return
	_model.configure_taoist_main_pets_persistence_provider(provider)

func clear_taoist_main_pets_persistence_provider() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("clear_taoist_main_pets_persistence_provider")
		return
	_model.clear_taoist_main_pets_persistence_provider()

func apply_taoist_main_pet_runtime_states(states: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_taoist_main_pet_runtime_states")
	return _model.apply_taoist_main_pet_runtime_states(states)

func clear_taoist_main_pet_runtime_state(summon_id: String, pet_slot_index: int = -1) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("clear_taoist_main_pet_runtime_state")
		return
	_model.clear_taoist_main_pet_runtime_state(summon_id, pet_slot_index)

func taoist_main_pet_runtime_states_for_restore() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("taoist_main_pet_runtime_states_for_restore")
	return _model.taoist_main_pet_runtime_states_for_restore()

func taoist_main_pet_runtime_state_for_restore(summon_id: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("taoist_main_pet_runtime_state_for_restore")
	return _model.taoist_main_pet_runtime_state_for_restore(summon_id)

func _refresh_taoist_main_pet_runtime_states_for_save() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_refresh_taoist_main_pet_runtime_states_for_save")
		return
	_model._refresh_taoist_main_pet_runtime_states_for_save()

func _empty_taoist_main_pet_runtime_states() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_empty_taoist_main_pet_runtime_states")
	return _model._empty_taoist_main_pet_runtime_states()

func _taoist_main_pet_runtime_state_slots() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_taoist_main_pet_runtime_state_slots")
	return _model._taoist_main_pet_runtime_state_slots()

func _profile_metadata_owner_status(document: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_profile_metadata_owner_status")
	return _model._profile_metadata_owner_status(document)

func _normalized_taoist_main_pet_runtime_states(states: Variant) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_normalized_taoist_main_pet_runtime_states")
	return _model._normalized_taoist_main_pet_runtime_states(states)

func _normalized_taoist_main_pet_runtime_state(snapshot: Variant) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_normalized_taoist_main_pet_runtime_state")
	return _model._normalized_taoist_main_pet_runtime_state(snapshot)

func _normalized_warrior_runtime_state(snapshot: Variant) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_normalized_warrior_runtime_state")
	return _model._normalized_warrior_runtime_state(snapshot)

func _default_warrior_runtime_state() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_default_warrior_runtime_state")
	return _model._default_warrior_runtime_state()

func update_world_location(
	map_id: int,
	screen_position_px: Vector2,
	ground_position_gu: Variant = null
) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("update_world_location")
		return
	_model.update_world_location(map_id, screen_position_px, ground_position_gu)

func save_safe_logout(
	home_map_id: int,
	home_screen_position_px: Vector2,
	home_ground_position_gu: Variant = null
) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("save_safe_logout")
	return _model.save_safe_logout(home_map_id, home_screen_position_px, home_ground_position_gu)

func list_characters() -> Array[Dictionary]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("list_characters")
	return _model.list_characters()

func prepare_qa_test_roster_v2() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("prepare_qa_test_roster_v2")
	return _model.prepare_qa_test_roster_v2()

func _archive_current_test_profiles() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_archive_current_test_profiles")
	return _model._archive_current_test_profiles()

func ensure_equipment_skill_test_roster() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("ensure_equipment_skill_test_roster")
	return _model.ensure_equipment_skill_test_roster()

func ensure_chiyue_test_roster() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("ensure_chiyue_test_roster")
	return _model.ensure_chiyue_test_roster()

func _commit_warehouse_transaction_snapshots(
	before_profile: Dictionary,
	after_profile: Dictionary,
	before_shared: Dictionary,
	after_shared: Dictionary,
	operation_kind: String,
) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_commit_warehouse_transaction_snapshots")
	return _model._commit_warehouse_transaction_snapshots(before_profile, after_profile, before_shared, after_shared, operation_kind)

var _warehouse_preparation_pending: bool:
	get: return _source_domain_gate.read_original_profile_view("_warehouse_preparation_pending") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._warehouse_preparation_pending
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_warehouse_preparation_pending"): return
		_model._warehouse_preparation_pending = value

var _warehouse_active_preparation: RefCounted:
	get: return _source_domain_gate.read_original_profile_view("_warehouse_active_preparation") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._warehouse_active_preparation
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_warehouse_active_preparation"): return
		_model._warehouse_active_preparation = value

func transfer_shared_gold_prepared(deposit: bool, transaction_id: String, transaction_sequence: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("transfer_shared_gold_prepared")
	return await _model.transfer_shared_gold_prepared(deposit, transaction_id, transaction_sequence)

func _prepare_shared_gold_request(deposit: bool, transaction_id: String, transaction_sequence: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_prepare_shared_gold_request")
	return await _model._prepare_shared_gold_request(deposit, transaction_id, transaction_sequence)

func transfer_warehouse_prepared(operation: String, source_indices: Array, target_slots: Array = []) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("transfer_warehouse_prepared")
	return await _model.transfer_warehouse_prepared(operation, source_indices, target_slots)

func _warehouse_preparation_failure(message: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_warehouse_preparation_failure")
	return _model._warehouse_preparation_failure(message)

func _captured_json_matches_document(path: String, bytes: PackedByteArray, document: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_captured_json_matches_document")
	return _model._captured_json_matches_document(path, bytes, document)
const UI_WORK_SLICE_BUDGET_USEC = ProfileModel.UI_WORK_SLICE_BUDGET_USEC

func _continue_ui_work_slice(started_usec: int) -> int:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_continue_ui_work_slice")
	return await _model._continue_ui_work_slice(started_usec)

func _prepare_warehouse_transfer(operation: String, source_indices: Array, target_slots: Array, bank_plan: Dictionary = {}) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_prepare_warehouse_transfer")
	return await _model._prepare_warehouse_transfer(operation, source_indices, target_slots, bank_plan)

func _await_character_writes_for_ui() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_await_character_writes_for_ui")
	return await _model._await_character_writes_for_ui()

func _complete_prepared_warehouse(success: bool, can_remove_journal: bool, journal_written: bool, commit: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_complete_prepared_warehouse")
		return
	_model._complete_prepared_warehouse(success, can_remove_journal, journal_written, commit)

func _bank_transfer_commit(
	before_profile: Dictionary,
	before_shared: Dictionary,
	next_gold: int,
	bank_update: Dictionary,
) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_bank_transfer_commit")
	return _model._bank_transfer_commit(before_profile, before_shared, next_gold, bank_update)

var _warehouse_validation_scope: bool:
	get: return _source_domain_gate.read_original_profile_view("_warehouse_validation_scope") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._warehouse_validation_scope
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_warehouse_validation_scope"): return
		_model._warehouse_validation_scope = value

var _warehouse_validated_collections: Dictionary:
	get: return _source_domain_gate.read_original_profile_view("_warehouse_validated_collections") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._warehouse_validated_collections
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_warehouse_validated_collections"): return
		_model._warehouse_validated_collections = value

func _warehouse_transfer_commit(_inventory_before: Array, _warehouse_before: Array) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_warehouse_transfer_commit")
	return _model._warehouse_transfer_commit(_inventory_before, _warehouse_before)

func _warehouse_transfer_commit_validated(_inventory_before: Array, _warehouse_before: Array) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_warehouse_transfer_commit_validated")
	return _model._warehouse_transfer_commit_validated(_inventory_before, _warehouse_before)

func receive_loot_batch_partial(candidates: Array, prepare_only := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("receive_loot_batch_partial")
	return _model.receive_loot_batch_partial(candidates, prepare_only)

func prepare_loot_save(candidates: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("prepare_loot_save")
	return _model.prepare_loot_save(candidates)

func _loot_request_context_matches(identity: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_loot_request_context_matches")
	return _model._loot_request_context_matches(identity)

func finish_prepared_loot_save(plan: Dictionary, wait := false) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("finish_prepared_loot_save")
	return _model.finish_prepared_loot_save(plan, wait)

func _complete_background_loot(receipt: Dictionary, plan: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_complete_background_loot")
		return
	_model._complete_background_loot(receipt, plan)

func _loot_inventory_after_immediate_uses(before: Array, after: Array) -> Array:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_loot_inventory_after_immediate_uses")
	return _model._loot_inventory_after_immediate_uses(before, after)

func _can_accept_immediate_item_use() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_can_accept_immediate_item_use")
	return _model._can_accept_immediate_item_use()

func _commit_item_use(save_in_background: bool) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_commit_item_use")
	return _model._commit_item_use(save_in_background)

func _queue_character_snapshot_save() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_queue_character_snapshot_save")
	return _model._queue_character_snapshot_save()

func _start_item_save(retry_failed := false) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_start_item_save")
	return _model._start_item_save(retry_failed)

func _before_state_transaction(include_world := false) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_before_state_transaction")
		return
	_model._before_state_transaction(include_world)

func _loot_save_failure(outcomes: Array) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_loot_save_failure")
	return _model._loot_save_failure(outcomes)

func _drop_instance_id_already_present(instance_id: String, working_inventory: Array) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_drop_instance_id_already_present")
	return _model._drop_instance_id_already_present(instance_id, working_inventory)

func _item_record_ownership_already_present(record: Dictionary, working_inventory: Array) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_item_record_ownership_already_present")
	return _model._item_record_ownership_already_present(record, working_inventory)

func loot_batch_debug_snapshot() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("loot_batch_debug_snapshot")
	return _model.loot_batch_debug_snapshot()

func _valid_chiyue_test_profile_document(
	document: Dictionary,
	expected_profile_id: String,
	expected_profession: String,
	expected_loadout_id: String,
	expected_skill_template_id: String
) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_valid_chiyue_test_profile_document")
	return _model._valid_chiyue_test_profile_document(document, expected_profile_id, expected_profession, expected_loadout_id, expected_skill_template_id)

func _rollback_new_chiyue_test_profiles(profile_ids: Array[String]) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_rollback_new_chiyue_test_profiles")
		return
	_model._rollback_new_chiyue_test_profiles(profile_ids)

func _skill_tier_for_equipment_tier(equipment_tier: String) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_skill_tier_for_equipment_tier")
	return _model._skill_tier_for_equipment_tier(equipment_tier)

func _test_character_payload(loadout: Dictionary, skill_profile: Dictionary, profile_entry: Dictionary, now: int) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_test_character_payload")
	return _model._test_character_payload(loadout, skill_profile, profile_entry, now)

func ensure_developer_test_character()->void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("ensure_developer_test_character")
	return _model.ensure_developer_test_character()

func _developer_item(item_name:String,instance_id:String)->Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_developer_item")
	return _model._developer_item(item_name, instance_id)

func ensure_zuma_test_character() -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("ensure_zuma_test_character")
		return
	_model.ensure_zuma_test_character()

func apply_temporary_item_buff(item_id: String, effect_profile: Dictionary, emit_updates := true) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("apply_temporary_item_buff")
	return _model.apply_temporary_item_buff(item_id, effect_profile, emit_updates)

func advance_temporary_item_buffs(delta: float) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("advance_temporary_item_buffs")
		return
	_model.advance_temporary_item_buffs(delta)

func _apply_temporary_item_stat_modifiers(result: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_apply_temporary_item_stat_modifiers")
		return
	_model._apply_temporary_item_stat_modifiers(result)

func _default_world_position_fields() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_default_world_position_fields")
	return _model._default_world_position_fields()

func register_profile_gameplay_owner(owner: Node) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("register_profile_gameplay_owner")
		return
	_model.register_profile_gameplay_owner(owner)

func unregister_profile_gameplay_owner(owner: Node) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("unregister_profile_gameplay_owner")
		return
	_model.unregister_profile_gameplay_owner(owner)

func feature_publication_context() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("feature_publication_context")
	return _model.feature_publication_context()

func _profile_is_owned_by_gameplay() -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_profile_is_owned_by_gameplay")
	return _model._profile_is_owned_by_gameplay()

func create_character(new_name: String, new_profession := "战士", new_gender := "男") -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("create_character")
	return _model.create_character(new_name, new_profession, new_gender)

func _reject_character_creation_stats(previous_runtime: Dictionary) -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_reject_character_creation_stats")
	return _model._reject_character_creation_stats(previous_runtime)

func delete_character_profile(profile_id: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("delete_character_profile")
	return _model.delete_character_profile(profile_id)

func _character_name_exists(candidate: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_character_name_exists")
	return _model._character_name_exists(candidate)

func _new_profile_id() -> String:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_new_profile_id")
	return _model._new_profile_id()

func _build_starter_loadout(starter_profession: String, starter_gender: String, profile_id: String) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_build_starter_loadout")
	return _model._build_starter_loadout(starter_profession, starter_gender, profile_id)

func _remove_new_profile_files(profile_id: String) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_remove_new_profile_files")
		return
	_model._remove_new_profile_files(profile_id)

func _remove_profile_world_clock_files(
	profile_id: String, removed: Array, failures: Array
) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_remove_profile_world_clock_files")
		return
	_model._remove_profile_world_clock_files(profile_id, removed, failures)

func _remove_profile_clock_generation_files(
	profile_id: String, generation: String, removed: Array, failures: Array
) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_remove_profile_clock_generation_files")
		return
	_model._remove_profile_clock_generation_files(profile_id, generation, removed, failures)

func _creation_runtime_snapshot() -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_creation_runtime_snapshot")
	return _model._creation_runtime_snapshot()

func _restore_creation_runtime(snapshot: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_restore_creation_runtime")
		return
	_model._restore_creation_runtime(snapshot)

func select_character(profile_id: String) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("select_character")
	return _model.select_character(profile_id)

func _update_profile_index(mark_legacy_migration_consumed := false) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_update_profile_index")
	return _model._update_profile_index(mark_legacy_migration_consumed)

func _migrate_single_save_to_profile(allow_legacy_import := true) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_migrate_single_save_to_profile")
		return
	_model._migrate_single_save_to_profile(allow_legacy_import)

func _record_runtime_save_phases(prefix: String, started_usec: int) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_record_runtime_save_phases")
		return
	_model._record_runtime_save_phases(prefix, started_usec)

func _finish_pending_durability_save(started_usec: int) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_finish_pending_durability_save")
		return
	_model._finish_pending_durability_save(started_usec)

func _background_save_context_matches(identity: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_background_save_context_matches")
	return _model._background_save_context_matches(identity)

func _start_background_save(update_profile_index := true) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_start_background_save")
	return _model._start_background_save(update_profile_index)

func _capture_background_character_plan(update_profile_index: bool) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_capture_background_character_plan")
	return _model._capture_background_character_plan(update_profile_index)

func _complete_background_checkpoint(receipt: Dictionary, plan: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_complete_background_checkpoint")
		return
	_model._complete_background_checkpoint(receipt, plan)

func _submit_background_profile(plan: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_submit_background_profile")
	return _model._submit_background_profile(plan)

func _complete_background_profile(receipt: Dictionary, plan: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_complete_background_profile")
		return
	_model._complete_background_profile(receipt, plan)

func _merge_background_profile_index(document: Dictionary, identity: Dictionary) -> Dictionary:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_merge_background_profile_index")
	return _model._merge_background_profile_index(document, identity)

func _complete_background_index(receipt: Dictionary, plan: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_complete_background_index")
		return
	_model._complete_background_index(receipt, plan)

func _finish_background_save_if_ready(plan: Dictionary) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_finish_background_save_if_ready")
		return
	_model._finish_background_save_if_ready(plan)

func _finish_background_save(plan: Dictionary, success: bool, index_updated: bool) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		_source_domain_gate.reject_legacy_call("_finish_background_save")
		return
	_model._finish_background_save(plan, success, index_updated)

func _commit_save(update_profile_index := true, checkpoint_world := false) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("_commit_save")
	return _model._commit_save(update_profile_index, checkpoint_world)

var _ui_l1_buy_quote_rows: int:
	get: return _source_domain_gate.read_original_profile_view("_ui_l1_buy_quote_rows") if _source_domain_gate != null and _source_domain_gate.state() == "S" else _model._ui_l1_buy_quote_rows
	set(value):
		if _source_domain_gate != null and not _source_domain_gate.original_main_call_allowed("set:_ui_l1_buy_quote_rows"): return
		_model._ui_l1_buy_quote_rows = value

func profile_core_for_owner() -> RefCounted:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("profile_core_for_owner")
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return _model

func _init(model: ProfileModel = null) -> void:
	_model = model if model != null else ProfileModel.new()
	var runtime = preload("res://scripts/gameplay/profile/legacy_profile_runtime_port.gd").new(self)
	_model.configure_ports(
		preload("res://scripts/gameplay/profile/profile_content_port.gd").new(GameData),
		preload("res://scripts/gameplay/profile/profile_feature_port.gd").new(ContentLayers),
		preload("res://scripts/gameplay/profile/legacy_profile_mode_port.gd").new(), runtime,
		preload("res://scripts/gameplay/profile/legacy_profile_diagnostics_port.gd").new())
	_model._json_persistence.configure_process_owner(self)
	_model._world_json_persistence.configure_process_owner(self)
	_model.profile_changed.connect(func(): profile_changed.emit())
	_model.inventory_changed.connect(func(): inventory_changed.emit())
	_model.equipment_changed.connect(func(): equipment_changed.emit())
	_model.item_audio_committed.connect(func(identity_domain, identity_id, semantic_event): item_audio_committed.emit(identity_domain, identity_id, semantic_event))
	_model.skills_changed.connect(func(): skills_changed.emit())
	_model.skill_progression_changed.connect(func(snapshot): skill_progression_changed.emit(snapshot))
	_model.quick_slots_changed.connect(func(change): quick_slots_changed.emit(change))
	_model.quick_item_slots_changed.connect(func(change): quick_item_slots_changed.emit(change))
	_model.warrior_runtime_state_changed.connect(func(snapshot): warrior_runtime_state_changed.emit(snapshot))
	_model.consumable_requested.connect(func(entity_id): consumable_requested.emit(entity_id))
	_model.scroll_requested.connect(func(entity_id): scroll_requested.emit(entity_id))
	_model.quests_changed.connect(func(): quests_changed.emit())
	_model.profession_changed.connect(func(profession): profession_changed.emit(profession))
	_model.levels_gained.connect(func(previous_level, new_level): levels_gained.emit(previous_level, new_level))
	_model.relic_proc_started.connect(func(item_id): relic_proc_started.emit(item_id))
	_model.background_item_save_failed.connect(func(): background_item_save_failed.emit())
	_model.temporary_item_buff_expired.connect(func(entity_id): temporary_item_buff_expired.emit(entity_id))


func _ready() -> void:
	var receipt_pump = preload("res://scripts/layers/runtime/execution/paused_receipt_pump.gd").new()
	receipt_pump.configure(self)
	add_child(receipt_pump)
	_model.initialize_profile(DisplayServer.get_name() != "headless")
	ContentLayers.feature_catalog_changed.connect(_model._on_feature_catalog_changed)

func _process(delta: float) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN": return
	_model.service_receipts()
	_model.step_process(delta)

func _notification(what: int) -> void:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		# Only the original three suspend notifications are Source input.
		# Node PREDELETE is not a new save command; Source closes before M free.
		if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
			_source_domain_gate.source_notification(what)
		return
	if _model == null: return
	if what == NOTIFICATION_PREDELETE:
		_model.close_profile()
	elif what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		_model.suspend_profile()

func persistence_receipt_snapshot() -> Array[Dictionary]:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("persistence_receipt_snapshot")
	return _model.persistence_receipt_snapshot()

func acknowledge_persistence_receipt(path: String, identity: Dictionary) -> bool:
	if _source_domain_gate != null and _source_domain_gate.state() != "MAIN":
		return _source_domain_gate.reject_legacy_call("acknowledge_persistence_receipt")
	return _model.acknowledge_persistence_receipt(path, identity)

func install_original_profile_source_gate(gate: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _source_domain_gate!=null or gate==null: return false
	# Runtime load avoids a PlayerState <-> gate preload cycle. An arbitrary
	# RefCounted, or a gate configured for another facade, is not an owner.
	if gate.get_script()!=load("res://scripts/gameplay/source/main_profile_source_gate.gd") or gate.state()!="MAIN": return false
	var actual_facade: Variant=gate.get("_facade")
	if not actual_facade is WeakRef or actual_facade.get_ref()!=self: return false
	_source_domain_gate=gate
	return true
func submit_original_profile_command(method: StringName, arguments: Array) -> Dictionary:
	if _source_domain_gate==null: return {"success":false,"errors":["actual_source_domain_gate_required"]}
	return await _source_domain_gate.submit_original_profile_command(method,arguments)

# New owner-local Model, configured with exactly the original Main ports/signals.
# The current _model remains closed behind the S gate until terminal commit.
func create_actual_terminal_return_model(gate: RefCounted, publication: Dictionary, resource_lease: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or gate==null or not is_same(_source_domain_gate,gate) or gate.state()!="S" or gate.get("_pending_model")!=null: return {"success":false,"error":"actual_closed_Profile_return_gate_required"}
	var replacement: ProfileModel=ProfileModel.new()
	var runtime = preload("res://scripts/gameplay/profile/legacy_profile_runtime_port.gd").new(self)
	replacement.configure_ports(
		preload("res://scripts/gameplay/profile/profile_content_port.gd").new(GameData),
		preload("res://scripts/gameplay/profile/profile_feature_port.gd").new(ContentLayers),
		preload("res://scripts/gameplay/profile/legacy_profile_mode_port.gd").new(), runtime,
		preload("res://scripts/gameplay/profile/legacy_profile_diagnostics_port.gd").new())
	replacement._json_persistence.configure_process_owner(self)
	replacement._world_json_persistence.configure_process_owner(self)
	replacement.profile_changed.connect(func(): profile_changed.emit())
	replacement.inventory_changed.connect(func(): inventory_changed.emit())
	replacement.equipment_changed.connect(func(): equipment_changed.emit())
	replacement.item_audio_committed.connect(func(identity_domain, identity_id, semantic_event): item_audio_committed.emit(identity_domain, identity_id, semantic_event))
	replacement.skills_changed.connect(func(): skills_changed.emit())
	replacement.skill_progression_changed.connect(func(snapshot): skill_progression_changed.emit(snapshot))
	replacement.quick_slots_changed.connect(func(change): quick_slots_changed.emit(change))
	replacement.quick_item_slots_changed.connect(func(change): quick_item_slots_changed.emit(change))
	replacement.warrior_runtime_state_changed.connect(func(snapshot): warrior_runtime_state_changed.emit(snapshot))
	replacement.consumable_requested.connect(func(entity_id): consumable_requested.emit(entity_id))
	replacement.scroll_requested.connect(func(entity_id): scroll_requested.emit(entity_id))
	replacement.quests_changed.connect(func(): quests_changed.emit())
	replacement.profession_changed.connect(func(profession): profession_changed.emit(profession))
	replacement.levels_gained.connect(func(previous_level, new_level): levels_gained.emit(previous_level, new_level))
	replacement.relic_proc_started.connect(func(item_id): relic_proc_started.emit(item_id))
	replacement.background_item_save_failed.connect(func(): background_item_save_failed.emit())
	replacement.temporary_item_buff_expired.connect(func(entity_id): temporary_item_buff_expired.emit(entity_id))
	# Loading this Source terminal codec during autoload compilation pulls its
	# runtime graph into the initial cold code cache. Its actual return caller
	# reaches here only after Source/physics join and physical owner restoration.
	var terminal_return: Script=load("res://scripts/gameplay/profile/profile_terminal_return.gd")
	if terminal_return==null or not terminal_return.can_instantiate(): return {"success":false,"error":"actual_terminal_Profile_codec_unavailable"}
	var adopted: Dictionary=terminal_return.adopt_main(replacement,publication,resource_lease)
	if adopted.get("ok")!=true: return {"success":false,"error":"actual_latest_Source_Profile_adoption_failed","details":adopted}
	return {"success":true,"model":replacement,"adoption":adopted}

func install_actual_terminal_return_model(gate: RefCounted, replacement: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or gate==null or not is_same(_source_domain_gate,gate) or gate.state()!="RETURN_COMMITTING" or not is_same(gate.get("_pending_model"),replacement) or not replacement is ProfileModel or replacement==_model or replacement._owner_thread_id!=OS.get_main_thread_id(): return false
	_model=replacement
	if not ContentLayers.feature_catalog_changed.is_connected(_model._on_feature_catalog_changed): ContentLayers.feature_catalog_changed.connect(_model._on_feature_catalog_changed)
	return true

func finish_actual_terminal_return_gate(gate: RefCounted) -> bool:
	if not is_same(_source_domain_gate,gate) or gate.state()!="RETURNED" or not is_same(_model,gate.get("_pending_model")): return false
	_source_domain_gate=null
	return true
