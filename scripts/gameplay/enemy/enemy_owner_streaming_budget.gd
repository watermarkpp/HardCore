extends "res://scripts/gameplay/enemy/enemy_owner_frame_budget.gd"

## One original ledger, not a companion budget. Root constructs this subclass
## IN PLACE OF the batch01 instance and injects that same instance everywhere.
## Original amounts, fairness, nested accounting and all numerical methods are
## inherited. The external segment only excludes reentrancy while S is parked.
var _resource_failure: Callable
var _resource_segment: Dictionary = {}
var _resource_configured := false
var _resource_failed := false

func configure_resource_continuations(fail_owner: Callable) -> bool:
	if _resource_configured or not fail_owner.is_valid() or OS.get_thread_caller_id() != owner_thread_id(): return false
	_resource_failure = fail_owner
	_resource_configured = true
	return true

func resource_continuations_configured() -> bool:
	return _resource_configured and not _resource_failed

func resource_external_segment_active() -> bool:
	return not _resource_segment.is_empty()

func _resource_fail(reason: String) -> bool:
	_resource_failed = true
	push_error("Single resource budget continuation failed: " + reason)
	if _resource_failure.is_valid(): _resource_failure.call(reason)
	return false

func _continuation_context_ready() -> bool:
	# Inspection must reject an active cold external segment without invoking
	# _sync_epoch() and turning a read-only refusal into a Source failure.
	return not _resource_failed and not resource_external_segment_active() and super._continuation_context_ready()

func _sync_epoch() -> bool:
	if resource_external_segment_active():
		return _resource_fail("another consumer entered an unsettled resource scope")
	if _resource_failed: return false
	return super._sync_epoch()

func end(token: int) -> void:
	if resource_external_segment_active():
		_resource_fail("scope end attempted before original resource continuation resumed")
		return
	super.end(token)

func begin_resource_external_segment(identity: Dictionary, site: Dictionary) -> Dictionary:
	if not resource_continuations_configured() or resource_external_segment_active() or OS.get_thread_caller_id() != owner_thread_id():
		_resource_fail("resource stage is not exclusive to its original owner")
		return {}
	# Do not call _sync_epoch here: a source status outside a budget scope must
	# not gain a made-up scope, admission decision, reset or fairness mutation.
	_resource_segment = {"identity": identity.duplicate(true), "site": site.duplicate(true),
		"ledger_epoch": _epoch, "logical_process_epoch": _current_epoch(),
		"scopes": _stack.duplicate(true), "started_usec": _now_usec(),
		"spent_usec": _spent_usec, "lane_spent": _lane_spent.duplicate(),
		"service_sequence": _service_sequence, "pending_sequence": _pending_sequence}
	return _resource_segment.duplicate(true)

func resume_resource_external_segment(segment: Dictionary, receipt: Dictionary) -> bool:
	if OS.get_thread_caller_id() != owner_thread_id() or segment != _resource_segment or segment.is_empty():
		return _resource_fail("wrong continuation resumed or resumed twice")
	if receipt.get("executed") != true or receipt.get("request", {}).get("identity") != segment.identity:
		return _resource_fail("unexecuted resource operation cannot settle a scope")
	if _epoch != int(segment.ledger_epoch) or _current_epoch() != int(segment.logical_process_epoch) or _stack != segment.scopes or _spent_usec != int(segment.spent_usec) or _lane_spent != segment.lane_spent or _service_sequence != int(segment.service_sequence) or _pending_sequence != int(segment.pending_sequence):
		return _resource_fail("world/epoch/ledger advanced across a suspended original source call")
	_resource_segment.clear()
	# Time was never paused. Original end(token) later accounts whole wall time
	# once, including M work and queue/return delay, with original child rules.
	return true
