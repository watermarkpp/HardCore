extends RefCounted

## One runtime-issued, one-shot producer capability. The runtime never reuses
## its sequence, including after clear/world change; no retired-ID list is needed.
var _owner: WeakRef
var _sequence := 0
var _closed := false
var _batch_open := false
var _branch := ""

static func create(owner: RefCounted, sequence: int) -> RefCounted:
	var result := new(); result._owner = weakref(owner); result._sequence = sequence
	return result

static func create_child(owner: RefCounted, sequence: int, release_id: String) -> RefCounted:
	var result: RefCounted=create(owner,sequence)
	result._branch=release_id
	return result

func claim(world: Dictionary, release_id: String, skill_id: String, bindings: Array) -> Dictionary:
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	if _closed or owner == null: return {"success":false}
	var result: Dictionary = owner.call("_claim_reservation",_sequence,world,release_id,skill_id,bindings,_branch,get_instance_id())
	if bool(result.get("success", false)): _batch_open = true
	return result

func matches_accepted_bindings(world: Dictionary, release_id: String, skill_id: String, bindings: Array) -> bool:
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	return not _closed and owner != null and _is_runtime_issuer(owner) and bool(owner.call("_reservation_binding_snapshot_matches",
		_sequence,world,release_id,skill_id,bindings,_branch,get_instance_id()))

static func _is_runtime_issuer(owner: RefCounted) -> bool:
	# Match the canonical Script identity, including inherited test observers.
	# Dynamic loading reuses the existing resource without a cyclic preload or
	# a persistent extra Script reference, and follows export path remapping.
	var expected: Script = load("res://scripts/features/runtime/effect_runtime.gd")
	var script: Script = owner.get_script()
	while script != null:
		if script == expected: return true
		script = script.get_base_script()
	return false

func belongs_to(owner: RefCounted) -> bool:
	return _owner != null and _owner.get_ref() == owner

func can_begin_release(release_id: String) -> bool:
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	return not _closed and owner != null and owner.call("_reservation_release_is_valid",_sequence,release_id)

func sequence() -> int: return _sequence
func branch() -> String: return _branch

func batch_owner_is_current() -> bool:
	var owner: RefCounted=_owner.get_ref() as RefCounted if _owner!=null else null
	# The batch may still own accepted work after the old action ticket closed.
	return owner!=null and bool(owner.call("_reservation_batch_owner_is_current",_sequence,_branch))

func authorizes_child_request(request: Dictionary) -> bool:
	var owner: RefCounted=_owner.get_ref() as RefCounted if _owner!=null else null
	return not _closed and not _branch.is_empty() and owner!=null \
		and bool(owner.call("_child_request_authorized",_sequence,_branch,get_instance_id(),request))

func chain_context(release_id: String) -> Dictionary:
	var owner: RefCounted=_owner.get_ref() as RefCounted if _owner!=null else null
	return owner.call("_reservation_chain_context",_sequence,release_id,_branch) if owner!=null else {}

func source_class(release_id: String) -> String:
	var owner: RefCounted=_owner.get_ref() as RefCounted if _owner!=null else null
	return str(owner.call("_reservation_source_class",_sequence,release_id,_branch)) if owner!=null else ""

func close() -> void:
	if _closed: return
	_closed = true
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	if owner != null and _branch.is_empty(): owner.call("_close_reservation_producer",_sequence)

func finish_batch() -> void:
	# The successful claim handed synchronous production to DamageBatch.
	# Closing the old action blocks new claims but cannot steal this handoff.
	close()
	if not _batch_open: return
	_batch_open = false
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	if owner != null: owner.call("_close_reservation_batch", _sequence,_branch)

func _notification(what: int) -> void:
	# A zero-refcount GDScript instance cannot dispatch another method on self.
	if what == NOTIFICATION_PREDELETE and (not _closed or _batch_open):
		_closed = true
		var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
		if owner != null:
			if _branch.is_empty(): owner.call("_close_reservation_producer",_sequence)
			if _batch_open: owner.call("_close_reservation_batch", _sequence,_branch)
