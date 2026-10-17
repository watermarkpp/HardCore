extends RefCounted

## Original-position M primitive continuation. Native Host preserves the S
## stack; there is one sequence shared with streaming and feature resources.
const PROTOCOL := "hardcore.world.primitives.v1"
const GLOBAL_OPERATIONS := [&"global_randi", &"global_randi_range", &"global_randf", &"global_randf_range", &"global_seed", &"global_randomize"]
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _transport: Object
var _budget: RefCounted
var _clock: RefCounted
var _generation := 0
var _site: Dictionary = {}
var _failed := false
var deadline_failures: Array[Dictionary] = []

func owner_thread_id() -> int: return _owner

func configure_owner(world: RefCounted, transport: Object, budget: RefCounted, clock: RefCounted) -> bool:
	if _world != null or _owner == OS.get_main_thread_id(): return false
	for method: String in ["exchange_world_primitive", "capabilities", "next_original_operation_sequence", "completed_original_operation_sequence", "ordered_main_prefix", "stage_original_main_prefix", "next_original_call_ordinal"]:
		if not transport.has_method(method): return false
	for port: Object in [transport, budget, clock]:
		if not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner: return false
	var caps: Dictionary = transport.capabilities()
	for guarantee: String in ["original_point_continuation", "explicit_observation_process_epoch", "exclusive_same_epoch_budget", "ordered_main_prefix", "deadline_preserves_continuation", "abort_owner_on_failure"]:
		if caps.get(guarantee) != true: return false
	_generation = int(caps.get("bridge_generation", 0))
	if _generation <= 0 or not budget.resource_continuations_configured(): return false
	_world = weakref(world)
	_transport = transport
	_budget = budget
	_clock = clock
	return true

func _fail(reason: String, details: Dictionary = {}) -> Dictionary:
	_failed = true
	_world.get_ref().fault(reason, details)
	return {}

func begin_original_phase(site: Dictionary) -> bool:
	if _failed or _world == null or not _site.is_empty() or OS.get_thread_caller_id() != _owner: return false
	for key: String in ["clock_epoch", "domain", "entry_id", "entry_ordinal", "bootstrap", "observation_process_epoch", "world_context", "deadline_usec"]:
		if not site.has(key): return false
	if site.domain not in [&"H", &"P"] or int(site.deadline_usec) <= 0: return false
	_site = site.duplicate(true)
	_site.make_read_only()
	return true

func finish_original_phase() -> bool:
	if _failed or _site.is_empty() or _budget.resource_external_segment_active(): return false
	_site = {}
	return true

func exchange(operation: StringName, arguments: Array) -> Dictionary:
	if _failed or _world == null or _site.is_empty() or OS.get_thread_caller_id() != _owner: return _fail("world_primitive_outside_original_entry")
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if not graph.validate(arguments, false).get("success", false): return _fail("world_primitive_nonplain_arguments")
	var core: RefCounted = _world.get_ref()
	var prefix: Dictionary = core.freeze_original_main_prefix()
	if prefix.is_empty() or not _transport.stage_original_main_prefix(prefix): return _fail("world_primitive_original_prefix_not_staged")
	var sequence := int(_transport.next_original_operation_sequence())
	if sequence <= 0 or sequence != int(_transport.completed_original_operation_sequence()) + 1: return _fail("world_primitive_global_sequence_mismatch")
	var call_ordinal := int(_transport.next_original_call_ordinal(_site))
	if call_ordinal <= 0: return _fail("world_primitive_original_call_ordinal_missing")
	var site := _site.duplicate(true)
	site.call_ordinal = call_ordinal
	var identity := {"bridge_generation": _generation, "op_sequence": sequence}
	var external: Dictionary = _budget.begin_resource_external_segment(identity, site)
	if external.is_empty(): return _fail("world_primitive_original_budget_not_sealed")
	var request := {"protocol": PROTOCOL, "identity": identity, "site": site,
		"operation": operation, "arguments": arguments.duplicate(true), "budget": external,
		"world": site.world_context, "source_site": site,
		"predecessor_receipt": sequence - 1, "output_slot": 0,
		"main_prefix": _transport.ordered_main_prefix(), "submitted_usec": int(_clock.get_ticks_usec())}
	# No polls, timeout fallback, or replay. Late execution still resumes the
	# accepted original call; its deadline failure is retained separately.
	var reply: Variant = _transport.exchange_world_primitive(request)
	var received_usec := int(_clock.get_ticks_usec())
	if not reply is Dictionary or reply.get("request") != request or reply.get("executed") != true or not reply.has("result"):
		return _fail("world_primitive_unexecuted_reply", {"identity": identity})
	if reply.get("disposition") not in [&"executed", &"executed_late"] or int(reply.get("completed_prefix_ordinal", -1)) != 1:
		return _fail("world_primitive_inexact_execution_prefix", {"identity": identity})
	if int(reply.get("started_usec", -1)) < int(request.submitted_usec) or int(reply.get("finished_usec", -1)) < int(reply.started_usec) or received_usec < int(reply.finished_usec):
		return _fail("world_primitive_wall_provenance_invalid", {"identity": identity})
	if not core.ack_original_main_prefix(reply.get("native_main_prefix_receipt", {}), prefix): return _fail("world_primitive_original_prefix_ack_rejected")
	if not _budget.resume_resource_external_segment(external, reply): return _fail("world_primitive_original_budget_resume_rejected")
	if int(_transport.completed_original_operation_sequence()) != sequence: return _fail("world_primitive_global_prefix_not_consumed")
	if reply.disposition == &"executed_late" or received_usec > int(site.deadline_usec):
		deadline_failures.append({"status": "FAIL", "identity": identity, "source_site": site,
			"started_usec": reply.started_usec, "finished_usec": reply.finished_usec, "received_usec": received_usec})
	return reply

func _integer(operation: StringName, arguments: Array) -> int:
	var reply := exchange(operation, arguments)
	assert(not reply.is_empty() and reply.result is int, "global RNG must return its actual original integer")
	return int(reply.result)

func _float(operation: StringName, arguments: Array) -> float:
	var reply := exchange(operation, arguments)
	assert(not reply.is_empty() and reply.result is float, "global RNG must return its actual original float")
	return float(reply.result)

func randi() -> int: return _integer(&"global_randi", [])
func randi_range(low: int, high: int) -> int: return _integer(&"global_randi_range", [low, high])
func draw(low: int, high: int) -> int: return randi_range(low, high)
func randf() -> float: return _float(&"global_randf", [])
func randf_range(low: float, high: float) -> float: return _float(&"global_randf_range", [low, high])
func seed_original(value: int) -> bool: return not exchange(&"global_seed", [value]).is_empty()
func randomize_original() -> bool: return not exchange(&"global_randomize", []).is_empty()
