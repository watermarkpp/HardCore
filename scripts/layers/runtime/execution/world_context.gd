extends RefCounted

## Identity views delegate to existing owners. This object never increments
## a world/character generation or owns a second map/profile state.
const CONTRACT_ID := "hardcore.execution.world_context.v1"
var _world_owner := WeakRef.new()
var _profile_owner := WeakRef.new()

func configure(world_owner: Node, profile_owner: Node) -> void:
	_world_owner = weakref(world_owner)
	_profile_owner = weakref(profile_owner)

func capture_world() -> Dictionary:
	var owner: Node = _world_owner.get_ref() as Node
	var profile: Node = _profile_owner.get_ref() as Node
	if not is_instance_valid(owner) or owner.is_queued_for_deletion() or not is_instance_valid(profile):
		return {}
	var result := {"contract_id": CONTRACT_ID, "world_runtime_id": owner.get_instance_id(),
		"world_epoch": int(owner.get("_zone_generation")), "runtime_map_id": int(owner.get("current_map_id")),
		"profile_id": str(profile.get("active_profile_id"))}
	result.make_read_only()
	return result

func capture_profile() -> Dictionary:
	var owner: Node = _profile_owner.get_ref() as Node
	if not is_instance_valid(owner) or owner.is_queued_for_deletion():
		return {}
	var generation: Variant = owner.get("_world_clock_generation")
	if not preload("res://scripts/world_monster_clock_ledger.gd").valid_generation(generation):
		return {}
	var result := {"profile_id": str(owner.get("active_profile_id")),
		"world_clock_generation": generation}
	result.make_read_only()
	return result

func matches_world(identity: Dictionary) -> bool:
	var current := capture_world()
	return not identity.is_empty() and not current.is_empty() and identity == current

func matches_profile(identity: Dictionary) -> bool:
	var current := capture_profile()
	return not identity.is_empty() and not current.is_empty() and identity == current

func current_world_owner() -> Node:
	var owner: Node = _world_owner.get_ref() as Node
	return owner if is_instance_valid(owner) and not owner.is_queued_for_deletion() else null
