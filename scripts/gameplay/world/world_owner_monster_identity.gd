extends RefCounted
const Identity := preload("res://scripts/monster_identity.gd")
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _inputs: Dictionary
func _init(world: RefCounted, publication: Dictionary) -> void:
	assert(_owner != OS.get_main_thread_id() and publication.contract_id == "world.monster_inputs.publication.v1")
	_world = weakref(world)
	_inputs = publication.inputs
func owner_thread_id() -> int: return _owner
func monster_id(data: Variant) -> int: return Identity.monster_id(data)
func _entry(id: int, key: String) -> Dictionary:
	if not _inputs.has(id) or not _inputs[id].get(key) is Dictionary:
		_world.get_ref().fault("canonical_monster_publication_missing", {"monster_id": id, "field": key})
		return {}
	return _inputs[id][key].duplicate(true)
func require_catalog_entry(id: int, purpose := "runtime") -> Dictionary:
	assert(purpose == "runtime")
	return _entry(id, "entry")
func appearance_profile(id: int) -> Dictionary: return _entry(id, "appearance")
func body_profile(id: int) -> Dictionary: return _entry(id, "body")
func behavior_profile(data: Dictionary) -> Dictionary: return _entry(monster_id(data), "behavior")
func runtime_boss_rule(data: Dictionary, _rules: Dictionary) -> Dictionary: return _entry(monster_id(data), "boss_rule")
