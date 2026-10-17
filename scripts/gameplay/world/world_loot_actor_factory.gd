extends RefCounted
const Pickup := preload("res://scripts/gameplay/world/world_loot_pickup_model.gd")
var _owner := OS.get_thread_caller_id()
var _preferences: RefCounted
var _descriptors: RefCounted
func _init(preferences: RefCounted, descriptors: RefCounted) -> void:
	assert(_owner != OS.get_main_thread_id() and preferences.owner_thread_id() == _owner and descriptors.owner_thread_id() == _owner)
	_preferences = preferences
	_descriptors = descriptors
func owner_thread_id() -> int: return _owner
func create_unconfigured(world: RefCounted) -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner and world.owner_thread_id() == _owner)
	return Pickup.new(world, _preferences, _descriptors)
