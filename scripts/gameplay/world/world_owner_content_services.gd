extends RefCounted
## Borrowed view of the SAME original rule/model authority. No state copy.
const Source := preload("res://scripts/gameplay/content/content_query_core.gd")
const ContentPort := preload("res://scripts/gameplay/profile/profile_content_port.gd")
var _owner := OS.get_thread_caller_id()
var _target: WeakRef
func _init(target: RefCounted) -> void:
	assert(_owner != OS.get_main_thread_id())
	_target = weakref(target)
func owner_thread_id() -> int: return _owner
func service_runtime_map_id(service_map_id: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().service_runtime_map_id(service_map_id)
func service_setup_value(key: String, fallback: Variant = null) -> Variant:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().service_setup_value(key,fallback)
func service_home_map_id(red_name := false) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().service_home_map_id(red_name)
func service_home_runtime_map_id(red_name := false) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().service_home_runtime_map_id(red_name)
func service_home_point(red_name := false) -> Vector2i:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().service_home_point(red_name)
func _get(field: StringName) -> Variant:
	var source_script: Script=Source
	var constants: Dictionary=source_script.get_script_constant_map()
	return constants[String(field)] if constants.has(String(field)) else _target.get_ref().get(field)
func _set(field: StringName, value: Variant) -> bool:
	_target.get_ref().set(field, value)
	return true

func prepare_factory(script: Script) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("prepare_factory", [script])

func bind_content_port(port: ContentPort) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_target.get_ref().callv("bind_content_port", [port])

func from_snapshot(snapshot: Dictionary) -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("from_snapshot", [snapshot])

func create_content_port(snapshot: Dictionary) -> ContentPort:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("create_content_port", [snapshot])

func diagnostics() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("diagnostics", [])

func is_loaded() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("is_loaded", [])

func merchant_context(stock_key: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("merchant_context", [stock_key])

func merchant_context_by_id(merchant_id: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("merchant_context_by_id", [merchant_id])

func canonical_monster_id(raw_value: Variant) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("canonical_monster_id", [raw_value])

func get_canonical_monster_entry(monster_id: int, use_context := "runtime") -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_canonical_monster_entry", [monster_id, use_context])

func get_monster_by_id(monster_id: int) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_monster_by_id", [monster_id])

func canonical_monster_classification(monster_id: int) -> String:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("canonical_monster_classification", [monster_id])

func is_dpv2_direct_baseline_loaded() -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("is_dpv2_direct_baseline_loaded", [])

func dpv2_direct_item_identity(canonical_item_id: Variant) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("dpv2_direct_item_identity", [canonical_item_id])

func dpv2_direct_resolve_slot_reward(slot: Dictionary) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("dpv2_direct_resolve_slot_reward", [slot])

func dpv2_ground_slot_limit() -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("dpv2_ground_slot_limit", [])

func dpv2_ground_slot_limit_for_monster(monster_id: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("dpv2_ground_slot_limit_for_monster", [monster_id])

func dpv2_source_slot_gate() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("dpv2_source_slot_gate", [])

func get_map_by_id(map_id: int) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_map_by_id", [map_id])

func get_item(item_name: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_item", [item_name])

func get_item_record(item_ref: Variant) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_item_record", [item_ref])

func get_entity_record(entity_id: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_entity_record", [entity_id])

func item_entity_id(item_ref: Variant) -> String:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("item_entity_id", [item_ref])

func get_item_rules_record(item_ref: Variant) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_item_rules_record", [item_ref])

func validate_item_drop_instance(instance: Dictionary) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("validate_item_drop_instance", [instance])

func get_item_shop_price(item_ref: Variant) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_item_shop_price", [item_ref])

func get_item_price_record(item_ref: Variant) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_item_price_record", [item_ref])

func get_skill(skill_ref: String, skill_level := 0) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_skill", [skill_ref, skill_level])

func skill_book_entity_id(skill_id: String) -> String:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("skill_book_entity_id", [skill_id])

func skill_book_skill_id(item_ref: Variant) -> String:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("skill_book_skill_id", [item_ref])

func get_bich_quest(quest_id: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_bich_quest", [quest_id])

func get_bich_quests() -> Array:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_bich_quests", [])

func service_exp_to_next_level(level_value: int) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("service_exp_to_next_level", [level_value])

func get_profession_skills(profession: String) -> Array:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("get_profession_skills", [profession])

func potion_recovery_profile(player_level: int, restore_health: int, restore_mana: int, use_effect: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("potion_recovery_profile", [player_level, restore_health, restore_mana, use_effect])

func adopt_profile_database_candidate(candidate: Dictionary, expected_revision: int) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().callv("adopt_profile_database_candidate", [candidate, expected_revision])

func get_item_art_display_size(item_ref: Variant, field := "inventoryIcon") -> Vector2:
	assert(OS.get_thread_caller_id() == _owner)
	var record: Dictionary = _target.get_ref()._item_record_for_read(item_ref)
	var art: Variant = record.get("art", {})
	var source: Variant = art.get(field, {}) if art is Dictionary else {}
	if not source is Dictionary:
		return Vector2.ZERO
	var values: Variant = source.get("displaySize", [])
	if not values is Array or (values as Array).size() != 2:
		return Vector2.ZERO
	var result := Vector2(float(values[0]), float(values[1]))
	return result if result.x > 0.0 and result.y > 0.0 else Vector2.ZERO

func get_map(map_name: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().get_map(map_name)

func merchant_stock(stock_key: String) -> Array:
	assert(OS.get_thread_caller_id() == _owner)
	return _target.get_ref().merchant_stock(stock_key)
