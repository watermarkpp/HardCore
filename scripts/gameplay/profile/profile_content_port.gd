extends RefCounted

## Typed dependency boundary; simulation injects an owner-local published content view.
var pricing_policy_cache: Dictionary = {}
var pricing_policy_hash := ""
var rules: RefCounted
var simulation_owner := false
var _published_growth_source_path := ""
var profession_growth_source_path: String:
	get:
		_assert_owner()
		return _published_growth_source_path if simulation_owner else str(_source.get("profession_growth_source_path"))
var _source: Object
var _owner_thread_id := OS.get_thread_caller_id()

func _init(source: Object, simulation := false) -> void:
	assert(source != null)
	assert(not simulation or not source is Node, "simulation content must not reference a main Node")
	_source = source
	simulation_owner = simulation
	if simulation:
		var growth_path: Variant = source.get("profession_growth_source_path")
		assert(growth_path is String and not growth_path.is_empty(), "content must publish the exact profession growth source")
		_published_growth_source_path = growth_path
		rules = load("res://scripts/gameplay/profile/profile_rule_set.gd").new(self)
	else:
		rules = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").for_content(self)

func _assert_owner() -> void:
	assert(OS.get_thread_caller_id() == _owner_thread_id)

var service_reference: Dictionary:
	get:
		_assert_owner()
		return _source.get("service_reference")

var dpv2_single_player_drop_boost: Dictionary:
	get:
		_assert_owner()
		return _source.get("dpv2_single_player_drop_boost")

func _stable_item_id(record: Dictionary) -> int:
	_assert_owner()
	return _source.callv("_stable_item_id", [record])

func canonical_monster_classification(monster_id: int) -> String:
	_assert_owner()
	return _source.callv("canonical_monster_classification", [monster_id])

func canonical_monster_id(raw_value: Variant) -> int:
	_assert_owner()
	return _source.callv("canonical_monster_id", [raw_value])

func dpv2_direct_item_identity(canonical_item_id: Variant) -> Dictionary:
	_assert_owner()
	return _source.callv("dpv2_direct_item_identity", [canonical_item_id])

func dpv2_direct_resolve_slot_reward(slot: Dictionary) -> Dictionary:
	_assert_owner()
	return _source.callv("dpv2_direct_resolve_slot_reward", [slot])

func dpv2_ground_slot_limit_for_monster(monster_id: int) -> int:
	_assert_owner()
	return _source.callv("dpv2_ground_slot_limit_for_monster", [monster_id])

func dpv2_source_slot_gate() -> Dictionary:
	_assert_owner()
	return _source.callv("dpv2_source_slot_gate", [])

func get_bich_quest(quest_id: String) -> Dictionary:
	_assert_owner()
	return _source.callv("get_bich_quest", [quest_id])

func get_bich_quests() -> Array:
	_assert_owner()
	return _source.callv("get_bich_quests", [])

func get_entity_record(entity_id: String) -> Dictionary:
	_assert_owner()
	return _source.callv("get_entity_record", [entity_id])

func get_item(item_name: String) -> Dictionary:
	_assert_owner()
	return _source.callv("get_item", [item_name])

func get_item_price_record(item_ref: Variant) -> Dictionary:
	_assert_owner()
	return _source.callv("get_item_price_record", [item_ref])

func get_item_record(item_ref: Variant) -> Dictionary:
	_assert_owner()
	return _source.callv("get_item_record", [item_ref])

func get_item_rules_record(item_ref: Variant) -> Dictionary:
	_assert_owner()
	return _source.callv("get_item_rules_record", [item_ref])

func get_item_shop_price(item_ref: Variant) -> int:
	_assert_owner()
	return _source.callv("get_item_shop_price", [item_ref])

func get_profession_skills(profession: String) -> Array:
	_assert_owner()
	return _source.callv("get_profession_skills", [profession])

func get_skill(skill_ref: String, skill_level := 0) -> Dictionary:
	_assert_owner()
	return _source.callv("get_skill", [skill_ref, skill_level])

func is_dpv2_direct_baseline_loaded() -> bool:
	_assert_owner()
	return _source.callv("is_dpv2_direct_baseline_loaded", [])

func is_loaded() -> bool:
	_assert_owner()
	return _source.callv("is_loaded", [])

func item_entity_id(item_ref: Variant) -> String:
	_assert_owner()
	return _source.callv("item_entity_id", [item_ref])

func merchant_context(stock_key: String) -> Dictionary:
	_assert_owner()
	return _source.callv("merchant_context", [stock_key])

func merchant_context_by_id(merchant_id: String) -> Dictionary:
	_assert_owner()
	return _source.callv("merchant_context_by_id", [merchant_id])

func service_exp_to_next_level(level_value: int) -> int:
	_assert_owner()
	return _source.callv("service_exp_to_next_level", [level_value])

func skill_book_entity_id(skill_id: String) -> String:
	_assert_owner()
	return _source.callv("skill_book_entity_id", [skill_id])

func skill_book_skill_id(item_ref: Variant) -> String:
	_assert_owner()
	return _source.callv("skill_book_skill_id", [item_ref])

func validate_item_drop_instance(instance: Dictionary) -> bool:
	_assert_owner()
	return _source.callv("validate_item_drop_instance", [instance])



func potion_recovery_profile(player_level: int, restore_health: int, restore_mana: int, use_effect: String) -> Dictionary:
	_assert_owner()
	return _source.callv("potion_recovery_profile", [player_level, restore_health, restore_mana, use_effect])
