extends RefCounted

## Same original pure rule functions and the same existing item-instance
## owner. These wrappers add only the required owner qualification.
const OriginalRespawn := preload("res://scripts/monster_respawn_policy.gd")
const OriginalClockDelta := preload("res://scripts/world_clock_delta.gd")

class Respawn:
	extends RefCounted
	var _owner := OS.get_thread_caller_id()
	func owner_thread_id() -> int: return _owner
	func resolve(policy: String, classification: String, legacy_seconds := -1.0, spawn_classification := "") -> Dictionary:
		assert(OS.get_thread_caller_id() == _owner)
		return OriginalRespawn.resolve(policy, classification, legacy_seconds, spawn_classification)

class ClockDelta:
	extends RefCounted
	var _owner := OS.get_thread_caller_id()
	func owner_thread_id() -> int: return _owner
	func valid_world_entry(key: String, value: Variant) -> bool:
		assert(OS.get_thread_caller_id() == _owner)
		return OriginalClockDelta.valid_world_entry(key, value)

class ItemInstances:
	extends RefCounted
	var _owner := OS.get_thread_caller_id()
	var _same_rule: RefCounted
	func _init(same_rule: RefCounted) -> void:
		assert(same_rule != null and same_rule.has_method("is_affixed_instance"))
		_same_rule = same_rule
	func owner_thread_id() -> int: return _owner
	func is_affixed_instance(instance: Dictionary, catalog_item: Dictionary) -> bool:
		assert(OS.get_thread_caller_id() == _owner)
		return _same_rule.is_affixed_instance(instance, catalog_item)

static func create_owner_services(same_item_instance_rule: RefCounted) -> Dictionary:
	assert(OS.get_thread_caller_id() != OS.get_main_thread_id())
	return {"MonsterRespawnPolicyScript":Respawn.new(), "WorldClockDeltaScript":ClockDelta.new(), "ItemDropInstanceRules":ItemInstances.new(same_item_instance_rule)}
