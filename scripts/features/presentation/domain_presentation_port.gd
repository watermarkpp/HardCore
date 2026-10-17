extends RefCounted

## S logical cue-head ownership and reliable VALUE facts. Actual cues/audio/
## Resource leases stay on M, where the original PresentationPort runs.
const Definitions := preload("res://scripts/features/presentation/cue_definitions.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
var _thread := OS.get_thread_caller_id()
var _world: RefCounted
var _owner: WeakRef
var _heads: Dictionary = {}
var _facts: Array[Dictionary] = []
var _serial := 0
var events: Array[Dictionary] = []
func _init(world: RefCounted) -> void:
	assert(world != null and world.is_domain() and world.current_effect_owner() != null)
	_world = world
	_owner = weakref(world.current_effect_owner())
func _owned() -> void: assert(OS.get_thread_caller_id() == _thread)

func _prepare(target: RefCounted, command: Dictionary, resources: RefCounted) -> Dictionary:
	_owned()
	var definition := Definitions.definition(str(command.get("cue_id","")))
	if definition.is_empty() or command.get("cue_policy") != definition.policy: return {}
	var requirements := Definitions.requirements(command.cue_id)
	if not requirements.success or _world.resolve_feature_actor(target) == null: return {}
	if not requirements.paths.is_empty():
		if resources == null or resources.get_script() != Lease or not resources.is_domain(): return {}
		for path: String in requirements.paths:
			if not resources.supports_path(path): return {}
	var descriptor := {"target":target.identity(),"command":command,"resource_publication":resources.domain_publication() if resources != null else {},
		"resource_retention_id":resources.domain_retention_id() if resources != null else 0}
	var captured := Graph.capture(descriptor)
	return captured.value if captured.success else {}

func _record(kind: String, handle: String) -> void:
	if events.size() >= 256: events.pop_front()
	var row := {"kind":kind,"effect_handle":handle}
	row.make_read_only()
	events.append(row)

func _emit(kind: String, handle: String, descriptor: Dictionary, resources: RefCounted = null) -> void:
	_serial += 1
	# Retain the S numeric entitlement until Root accepts the event. Root then
	# pins the matching M lease for its reliable event/ack lifetime.
	_facts.append({"ordinal":_serial,"kind":kind,"handle":handle,"value":descriptor,"resources":resources})
	flush()

func flush() -> bool:
	_owned()
	while not _facts.is_empty():
		var work: Dictionary = _facts.front()
		if not bool(_owner.get_ref().call("enqueue_feature_presentation", str(get_instance_id()), work.ordinal, work.kind, work.handle, work.value)): return false
		_facts.pop_front()
	return true

func pending_count() -> int:
	_owned()
	return _facts.size()

func start(handle: String, target: RefCounted, command: Dictionary, resources: RefCounted = null) -> bool:
	_owned()
	if _heads.has(handle): return false
	var prepared := _prepare(target,command,resources)
	if prepared.is_empty(): return false
	_record("start",handle)
	# Required procedural readiness is a real M admission publication. It is
	# checked synchronously before S accepts status/cue ownership.
	if not bool(_owner.get_ref().call("feature_cue_is_supported", command.cue_id, command.cue_policy)): return false
	_heads[handle] = {"cue_id":command.cue_id,"descriptor":prepared,"resources":resources}
	_emit("start",handle,prepared,resources)
	return true

func replace(handle: String, target: RefCounted, command: Dictionary, resources: RefCounted = null) -> bool:
	_owned()
	var prepared := _prepare(target,command,resources)
	if prepared.is_empty(): return false
	if not bool(_owner.get_ref().call("feature_cue_is_supported",command.cue_id,command.cue_policy)):
		stop(handle)
		return false
	if not _heads.has(handle): return start(handle,target,command,resources)
	var same_cue: bool = _heads[handle].cue_id == command.cue_id
	_heads[handle] = {"cue_id":command.cue_id,"descriptor":prepared,"resources":resources}
	_record("refresh" if same_cue else "replace",handle)
	# M uses original replace(), including unchanged-cue no-repeat audio and
	# synchronous onset guards. Replacement never changes the S effect head.
	_emit("replace",handle,prepared,resources)
	return true

func refresh(handle: String, strength: int) -> void:
	_owned()
	_record("refresh",handle)
	if not _heads.has(handle): return
	_emit("refresh",handle,{"strength":strength})

func stop(handle: String) -> void:
	_owned()
	_record("stop",handle)
	_heads.erase(handle)
	_emit("stop",handle,{})

func clear() -> void:
	_owned()
	for handle: String in _heads.keys(): stop(handle)

func node_count() -> int:
	_owned()
	# Logical accepted heads; actual M physical counts arrive in M receipts.
	return _heads.size()
