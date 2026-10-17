extends RefCounted
const Loader := preload("res://scripts/gameplay/world/world_environment_boot_loader.gd")
var _owner := OS.get_thread_caller_id()
var _host: Object
var _checks: Array[Dictionary] = []
var faults: Array[Dictionary] = []
var _done := false
var _bound_world_identity: Dictionary
func current_world_identity() -> Dictionary: return _bound_world_identity
func owner_thread_id() -> int: return _owner
func fault(code: String, details: Dictionary) -> void: faults.append({"code":code,"details":details})
func current_clock_frame() -> Dictionary: return _host.current_clock_frame()
func _check(value: bool, label: String) -> void: _checks.append({"pass":value,"label":label})
func _init(host: Object, source: Dictionary) -> void:
	_host=host
	_check(_owner!=OS.get_main_thread_id(),"real Native Source owns the formal environment consumer")
	_check(host.current_clock_frame().get("source_boundary")=="bootstrap_ready_query","production Source factory runs inside the actual physics query bootstrap bracket")
	_check(host.bind_original_world_context(source.world_identity),"actual Source binds the same genuine pre-map Root identity before environment admission")
	_bound_world_identity = source.world_identity
	var loader := Loader.new()
	var ok: bool=loader.configure_owner(source.environment,self)
	_check(ok,"real Source BootLoader accepts prepared content before first map arrival")
	if ok:
		_check(loader.boot.runtime_map_id == -1 and loader.boot.world_identity.runtime_map_id == -1,"prepared target never replaces current -1 map")
		_check(not loader.publication.runtime_maps.has(-1),"no invented negative-map content entry")
		_check(loader.boot.runtime_source_documents.has(source.target_map),"actual formal target source bytes remain available")
		_check(loader.publication.background.zone_data.is_empty(),"original unbuilt environment state is unchanged")
		_check(faults.is_empty(),"accepted initial environment has no suppressed owner fault")
		var maps := preload("res://scripts/gameplay/world/world_environment_runtime_maps.gd").new()
		_check(maps.configure_owner(loader.publication,self),"actual Source configures the captured pre-map runtime table")
		_check(maps.load_map(-1).is_empty() and not maps.has_runtime_map(-1) and not maps.is_formal_playable(-1),"original unbuilt-map queries return absent data without inventing geometry")
		_check(faults.is_empty() and not maps.get("_entries").has(-1),"pre-map queries preserve strict table and produce no suppressed fault")
		_check(not maps.require_map(-1) and faults.back().code == "environment_map_not_published","geometry still refuses an unpublished negative map")
		var invalids: Array[Dictionary]=[]
		var v: Dictionary=source.environment.duplicate(true); v.erase("pre_map_context"); invalids.append(v)
		v=source.environment.duplicate(true); v.world_identity.world_epoch=1; invalids.append(v)
		v=source.environment.duplicate(true); v.pre_map_context.background_reference_map_id=-1; invalids.append(v)
		v=source.environment.duplicate(true); v.pre_map_context.source_sha256="bad"; invalids.append(v)
		v=source.environment.duplicate(true); v.runtime_source_documents.erase(source.target_map); invalids.append(v)
		for i: int in range(invalids.size()):
			var bad := Loader.new()
			_check(not bad.configure_owner(invalids[i],self),"malformed or incomplete pre-map content refuses entry %d" % i)
	_done=true
func on_inputs(_domain: String, _packets: Array) -> bool: return true
func on_phase(phase: String,_frame: Dictionary) -> bool:
	return _host.publish_snapshot({"done":_done,"checks":_checks,"faults":faults},[]) if phase=="PUBLISH" else true
func close_session() -> bool: return true
