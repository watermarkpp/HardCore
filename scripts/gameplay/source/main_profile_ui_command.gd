extends RefCounted
## UI transport adapter only. Original algorithms and all mutable state remain
## in the actual current Profile owner. Every Source result is verified/ACKed
## by the existing same-session command transport before returning here.
static func call_owner(method: StringName, arguments: Array) -> Variant:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	assert(preload("res://scripts/gameplay/source/profile_original_command_catalog.gd").accepts(str(method),arguments.size()))
	var positions := {"equip_inventory_index_result":3,"unequip_to_inventory_slot":3,"use_inventory_index_result":2,"destroy_inventory_indices":1,"transfer_warehouse_prepared":3}
	if positions.has(str(method)):
		var supplied: Variant=arguments[positions[str(method)]]
		var selections: Array=supplied if supplied is Array else [supplied]
		for selected: Variant in selections:
			if not preload("res://scripts/gameplay/profile/profile_item_selection.gd").valid(selected): return {"success":false,"complete":false,"destroyed":0,"transferred":0,"reason":"selection_changed","message":"所选物品已变化，请重新选择。"}
	var gate: RefCounted = PlayerState.get("_source_domain_gate")
	if gate != null and gate.state() == "S":
		var actual: Dictionary = await PlayerState.submit_original_profile_command(method,arguments)
		if actual.get("success") != true or not actual.has("result"):
			push_error("actual original Source UI command failed: "+str(method))
			return null
		return actual.result
	var legacy := arguments.duplicate(true)
	if str(method) in ["equip_inventory_index_result","unequip_to_inventory_slot","use_inventory_index_result","destroy_inventory_indices","transfer_warehouse_prepared"]: legacy.pop_back()
	return await PlayerState.callv(method,legacy)

static func capture_selection(container: String, slot: Variant, record: Dictionary) -> Dictionary:
	var gate: RefCounted = PlayerState.get("_source_domain_gate")
	var session_id := 0
	if gate!=null and gate.state()=="S": session_id=gate._router._transport._session_id
	return preload("res://scripts/gameplay/profile/profile_item_selection.gd").capture(str(PlayerState.active_profile_id),session_id,container,slot,record)

