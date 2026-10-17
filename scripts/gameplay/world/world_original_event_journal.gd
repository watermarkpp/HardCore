extends RefCounted

## One journal producer. Native primitive prefixes and normal PUBLISH share
## the same immutable events. Only a verified Main acknowledgement retires it.
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _bridge_generation := 0
var _journal_generation := 0
var _last_ordinal := 0
var _applied_ordinal := 0
var _events: Array[Dictionary] = []

func _init(world: RefCounted, bridge_generation: int, journal_generation: int) -> void:
	assert(_owner != OS.get_main_thread_id() and bridge_generation > 0 and journal_generation > 0)
	_world = weakref(world)
	_bridge_generation = bridge_generation
	_journal_generation = journal_generation

func owner_thread_id() -> int: return _owner

func append(event: Dictionary) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if not graph.validate(event, false).get("success", false):
		_world.get_ref().fault("main_journal_nonplain_event", {})
		return false
	_last_ordinal += 1
	var captured := event.duplicate(true)
	captured.ordinal = _last_ordinal
	captured.make_read_only()
	_events.append(captured)
	return true

func freeze_prefix() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	var captured: Array[Dictionary] = []
	for event: Dictionary in _events:
		if int(event.ordinal) > _applied_ordinal: captured.append(event)
	captured.make_read_only()
	var prefix := {"bridge_generation": _bridge_generation, "journal_generation": _journal_generation,
		"through_ordinal": _last_ordinal, "events": captured}
	prefix.make_read_only()
	return prefix

func acknowledge(receipt: Dictionary, submitted: Dictionary) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	if submitted.get("bridge_generation") != _bridge_generation or submitted.get("journal_generation") != _journal_generation:
		return false
	if submitted.size() != 4 or not submitted.get("events") is Array or int(submitted.get("through_ordinal", -1)) > _last_ordinal: return false
	var prior := _applied_ordinal
	for event: Dictionary in submitted.events:
		if int(event.get("ordinal", -1)) != prior + 1: return false
		var offset: int = prior - _applied_ordinal
		if offset >= _events.size() or event != _events[offset]: return false
		prior += 1
	if prior != int(submitted.through_ordinal): return false
	for field: String in ["bridge_generation", "journal_generation", "through_ordinal"]:
		if receipt.get(field) != submitted.get(field): return false
	if receipt.size() != 4 or receipt.get("applied") != true: return false
	_applied_ordinal = int(submitted.through_ordinal)
	while not _events.is_empty() and int(_events[0].ordinal) <= _applied_ordinal: _events.pop_front()
	return true

func has_pending() -> bool: return not _events.is_empty()
func applied_ordinal() -> int: return _applied_ordinal

var _published_prefixes: Dictionary = {}
func register_normal_publication(prefix: Dictionary) -> bool:
	if prefix != freeze_prefix(): return false
	_published_prefixes[int(prefix.through_ordinal)] = prefix
	return true
func original_registered_prefix_containing(event: Dictionary) -> Dictionary:
	# Read the same producer's real admitted publications. A later ordinary or
	# LIVE packet may already carry this reserved event. Reuse that exact packet
	# instead of needing a new FIFO slot while Main is waiting for its seal.
	if OS.get_thread_caller_id()!=_owner or not _events.has(event): return {}
	var found: Dictionary = {}
	for prefix: Dictionary in _published_prefixes.values():
		if prefix.events.has(event) and (found.is_empty() or prefix.through_ordinal<found.through_ordinal): found=prefix
	return found
func is_current_original_prefix(prefix: Dictionary) -> bool:
	return OS.get_thread_caller_id()==_owner and prefix==freeze_prefix()
func is_original_normal_publication(prefix: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=_owner or not prefix.get("through_ordinal") is int: return false
	return _published_prefixes.get(prefix.through_ordinal,{}) == prefix and prefix == freeze_prefix()
func consume_normal_receipt(receipt: Dictionary) -> bool:
	if receipt.is_empty(): return true
	if receipt.get("bridge_generation") != _bridge_generation or receipt.get("journal_generation") != _journal_generation or receipt.get("applied") != true or not receipt.get("through_ordinal") is int: return false
	var through: int = receipt.through_ordinal
	if through <= _applied_ordinal:
		for ordinal: int in _published_prefixes.keys():
			if ordinal <= through: _published_prefixes.erase(ordinal)
		return true
	if not _published_prefixes.has(through): return false
	# Several real immutable publications can overlap before Main ACKs the
	# first. Its receipt has already pruned those events from the active queue;
	# the later registered publication still contains that historical prefix.
	# Only this exact producer-registered value permits removing that overlap.
	# acknowledge() continues checking every remaining event, its consecutive
	# ordinal, exact bytes/value and the complete receipt identity.
	var published: Dictionary = _published_prefixes[through]
	var remaining: Array[Dictionary] = []
	for event: Dictionary in published.events:
		if int(event.ordinal) > _applied_ordinal: remaining.append(event)
	remaining.make_read_only()
	var suffix := {"bridge_generation":published.bridge_generation,"journal_generation":published.journal_generation,
		"through_ordinal":through,"events":remaining}
	suffix.make_read_only()
	if not acknowledge(receipt, suffix): return false
	for ordinal: int in _published_prefixes.keys():
		if ordinal <= through: _published_prefixes.erase(ordinal)
	return true

func next_original_event_identity() -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return {"bridge_generation":_bridge_generation, "journal_generation":_journal_generation, "event_ordinal":_last_ordinal + 1}
