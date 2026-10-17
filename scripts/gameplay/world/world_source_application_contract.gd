extends RefCounted
## Fixed suboperations of the existing Feature.object_call, not an open RPC.
static func accepts(operation: String, arguments: Array) -> bool:
	match operation:
		"claim_initial_code_retention": return arguments.size() == 1 and arguments[0] is Dictionary
		"prepare_directory": return arguments.size() == 1 and arguments[0] is String and not arguments[0].is_empty()
		"view_ready": return arguments.size() == 2 and arguments[0] is Dictionary and arguments[1] is int and arguments[1] > 0
		"panel_state": return arguments.size() == 1 and arguments[0] is int and arguments[0] > 0
		"prewarm_panels", "budgeted_panels": return arguments.size() == 2 and arguments[0] is int and arguments[0] > 0 and arguments[1] is int and arguments[1] > 0
		"catalog_icons": return arguments.size() == 2 and arguments[0] is int and arguments[0] > 0 and arguments[1] is bool
		"map_scope": return arguments.size() == 4 and arguments[0] is Dictionary and arguments[1] is String and not arguments[1].is_empty() and arguments[2] is int and arguments[2] >= 0 and arguments[3] is int and arguments[3] >= 0
		"release_map_scope": return arguments.size() == 1 and arguments[0] is Dictionary
		"world_view_exit_state": return arguments.size() == 1 and arguments[0] is Dictionary and accepts_retiring_world(arguments[0])
		"actor_view_free_state": return arguments.size() == 1 and arguments[0] is Dictionary and accepts_retiring_actor(arguments[0])
		"map_warm_start", "map_warm_state": return arguments.size() == 1 and arguments[0] is Dictionary and accepts_map_warm_request(arguments[0])
	return false

static func accepts_map_warm_request(request: Dictionary) -> bool:
	if request.size() != 12 or request.get("contract_id") != "hardcore.source.map_warm_request.v1" or not request.get("world_context") is Dictionary: return false
	var world: Dictionary = request.world_context
	if world.size() != 5 or world.get("contract_id") != "hardcore.execution.world_context.v1" or not world.get("world_runtime_id") is int or world.world_runtime_id <= 0 or not world.get("profile_id") is String or world.profile_id.is_empty() or not world.get("world_epoch") is int or world.world_epoch < 0 or not world.get("runtime_map_id") is int or (world.runtime_map_id < 0 and not (world.runtime_map_id == -1 and world.world_epoch == 0)): return false
	if not request.get("source_root_id") is int or request.source_root_id == 0 or not request.get("owner_session_id") is int or request.owner_session_id <= 0 or not request.get("transition_id") is String or request.transition_id.is_empty() or not request.get("coordinator_generation") is int or request.coordinator_generation < 0 or not request.get("map_id") is int or request.map_id < 0: return false
	if request.get("operation") not in ["loot_icons","workset","render"] or not request.get("workset") is Array or request.workset.size() > 7 or not request.get("item_names") is Array or not request.get("facing") is Vector2 or not request.facing.is_finite() or not request.get("player_position_px") is Vector2 or not request.player_position_px.is_finite(): return false
	var seen: Dictionary = {}
	for skill: Variant in request.workset:
		if not skill is String or skill.is_empty() or seen.has(skill): return false
		seen[skill] = true
	for item: Variant in request.item_names:
		if not item is String or item.is_empty(): return false
	return (request.workset.is_empty() if request.operation == "loot_icons" else request.item_names.is_empty())

static func accepts_retiring_world(world: Dictionary) -> bool:
	if world.size() != 5 or world.get("contract_id") != "hardcore.execution.world_context.v1" or not world.get("world_runtime_id") is int or world.world_runtime_id <= 0 or not world.get("world_epoch") is int or world.world_epoch < 0 or not world.get("runtime_map_id") is int or not world.get("profile_id") is String or world.profile_id.is_empty(): return false
	return world.runtime_map_id >= 0 or (world.runtime_map_id == -1 and world.world_epoch == 0)

static func accepts_retiring_actor(identity: Dictionary) -> bool:
	if identity.size() != 3 or not identity.get("world") is Dictionary or not accepts_retiring_world(identity.world) or not identity.get("runtime_id") is int or identity.runtime_id <= 0 or not identity.get("life_generation") is int: return false
	return identity.life_generation >= 0 if identity.world.runtime_map_id == -1 else identity.life_generation > 0
