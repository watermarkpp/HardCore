extends RefCounted

## One runtime-issued, one-shot producer capability. The runtime never reuses
## its sequence, including after clear/world change; no retired-ID list is needed.
var _owner: WeakRef
var _sequence := 0
var _closed := false
var _batch_open := false

static func create(owner: RefCounted, sequence: int) -> RefCounted:
	var result := new(); result._owner = weakref(owner); result._sequence = sequence
	return result

func claim(world: Dictionary, release_id: String, skill_id: String, bindings: Array) -> Dictionary:
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	if _closed or owner == null: return {"success":false}
	var result: Dictionary = owner.call("_claim_reservation",_sequence,world,release_id,skill_id,bindings)
	if bool(result.get("success", false)): _batch_open = true
	return result

func belongs_to(owner: RefCounted) -> bool:
	return _owner != null and _owner.get_ref() == owner

func can_begin_release(release_id: String) -> bool:
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	return not _closed and owner != null and owner.call("_reservation_release_is_valid",_sequence,release_id)

func sequence() -> int: return _sequence

func close() -> void:
	if _closed: return
	_closed = true
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	if owner != null: owner.call("_close_reservation_producer",_sequence)

func finish_batch() -> void:
	# The successful claim handed synchronous production to DamageBatch.
	# Closing the old action blocks new claims but cannot steal this handoff.
	close()
	if not _batch_open: return
	_batch_open = false
	var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
	if owner != null: owner.call("_close_reservation_batch", _sequence)

func _notification(what: int) -> void:
	# A zero-refcount GDScript instance cannot dispatch another method on self.
	if what == NOTIFICATION_PREDELETE and (not _closed or _batch_open):
		_closed = true
		var owner: RefCounted = _owner.get_ref() as RefCounted if _owner != null else null
		if owner != null:
			owner.call("_close_reservation_producer",_sequence)
			if _batch_open: owner.call("_close_reservation_batch", _sequence)
