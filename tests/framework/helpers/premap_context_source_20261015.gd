extends RefCounted
## Protocol component on an actual Native Source thread. No full World/Save claim.
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
var _host: Object
var _world: Dictionary
var _checks: Array[Dictionary] = []
var _after_boot := false
func _check(value: bool, label: String) -> void: _checks.append({"pass":value,"label":label})
func _init(host: Object, boot: Dictionary) -> void:
	_host = host
	_world = boot.world_identity
	_check(OS.get_thread_caller_id() != OS.get_main_thread_id(),"actual independent Native Source thread")
	_check(host.current_clock_frame().get("epoch") == 0,"real bootstrap epoch observed rather than supplied")
	_check(host.bind_original_world_context(_world),"Native accepts the exact initial not-yet-mapped Root context")
	var registry := Registry.new()
	_check(registry.configure_world(_world,""),"canonical registry can exist before original first map arrival")
	_check(registry.capture_world() == _world,"pre-map registry preserves -1 and does not claim the prepared target is active")
	_check(registry.remaining_actor_count() == 0 and registry.remaining_lease_count() == 0,"pre-map context creates neither actors nor leases")
	var invalids: Array[Dictionary] = []
	var value: Dictionary = _world.duplicate(true); value.runtime_map_id = -2; invalids.append(value)
	value = _world.duplicate(true); value.runtime_map_id = -1.0; invalids.append(value)
	value = _world.duplicate(true); value.world_epoch = 1; invalids.append(value)
	value = _world.duplicate(true); value.world_epoch = 0.0; invalids.append(value)
	value = _world.duplicate(true); value.world_runtime_id = 0; invalids.append(value)
	value = _world.duplicate(true); value.profile_id = ""; invalids.append(value)
	value = _world.duplicate(true); value.extra = true; invalids.append(value)
	for index: int in range(invalids.size()):
		_check(not host.bind_original_world_context(invalids[index]),"Native rejects malformed pre-map context %d" % index)
		var rejected := Registry.new()
		_check(not rejected.configure_world(invalids[index],""),"registry rejects malformed pre-map context %d" % index)
	value = _world.duplicate(true); value.world_runtime_id += 1
	_check(not host.bind_original_world_context(value),"a different Root cannot replace the captured pre-map bootstrap identity")
	_check(registry.capture_world() == _world,"invalid attempts do not mutate accepted registry context")
	_check(registry.retire_world(),"empty structural pre-map registry retires without artificial gameplay")
func on_inputs(_domain: String, _packets: Array) -> bool: return true
func on_phase(phase: String, _frame: Dictionary) -> bool:
	if phase == "P_GROUP" and not _after_boot:
		_after_boot = true
		_check(not _host.bind_original_world_context(_world),"pre-map birth cannot be re-admitted at a later live epoch")
	if phase != "PUBLISH": return true
	return _host.publish_snapshot({"done":_after_boot,"checks":_checks,"world":_world},[])
func close_session() -> bool: return true
