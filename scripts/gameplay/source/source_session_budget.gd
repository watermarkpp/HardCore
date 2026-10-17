extends "res://scripts/gameplay/enemy/enemy_owner_streaming_budget.gd"

## Adds accepted LIVE reservations to the SAME original ledger. Existing
## fairness, scope wall accounting and cold stack continuation remain inherited.
var _session_id := 0
var _reservation_sequence := 0
var _reservations: Dictionary = {}
var _settlements: Dictionary = {}
var _cold_gate: Callable
func configure_session(session_id: int, cold_gate: Callable) -> bool:
	if _session_id != 0 or session_id <= 0 or not cold_gate.is_valid(): return false
	_session_id = session_id
	_cold_gate = cold_gate
	return true
func begin_resource_external_segment(identity: Dictionary, site: Dictionary) -> Dictionary:
	if not _cold_gate.is_valid() or not bool(_cold_gate.call()):
		_resource_fail("LIVE original-point park is forbidden")
		return {}
	return super.begin_resource_external_segment(identity, site)
func _reserved(lane: int) -> int:
	var total := 0
	for item: Dictionary in _reservations.values():
		if item.lane == lane: total += int(item.reserved_usec)
	return total
func remaining_usec() -> int: return maxi(0, super.remaining_usec() - _reserved(LANE_BACKGROUND))
func remaining_progress_usec() -> int: return maxi(0, super.remaining_progress_usec() - _reserved(LANE_PROGRESS))
func reserve_live(category: String, lane: int, amount: int) -> Dictionary:
	if OS.get_thread_caller_id() != owner_thread_id() or _session_id <= 0 or category.is_empty() or lane not in [0,1,2] or amount < 0 or not _stack.is_empty() or not _sync_epoch(): return {}
	var available: int = remaining_progress_usec() if lane == LANE_PROGRESS else remaining_usec()
	if lane != LANE_NECESSARY and (amount > available or _fair_blocker(category, lane) != null): return {}
	_reservation_sequence += 1
	var item := {"contract_id":"hardcore.resource.budget_reservation.v1", "reservation_id":_reservation_sequence,
		"owner_session_id":_session_id, "ledger_epoch":_epoch, "category":category,
		"lane":lane, "reserved_usec":amount, "issued_usec":_now_usec()}
	_reservations[_reservation_sequence] = item.duplicate(true)
	return item
func release_unaccepted(reservation: Dictionary) -> bool:
	var id := int(reservation.get("reservation_id",0))
	if not _reservations.has(id) or _reservations[id] != reservation: return false
	_reservations.erase(id)
	return true
func settle_live(reservation: Dictionary, identity: Dictionary, reply: Dictionary, received_usec: int, commit_clock_epoch: int) -> Dictionary:
	var id := int(reservation.get("reservation_id",0))
	if not _reservations.has(id) or _reservations[id] != reservation or _settlements.has(id) or not _stack.is_empty() or not _sync_epoch(): return {}
	var request: Variant = reply.get("request")
	if not request is Dictionary or request.get("reservation") != reservation or request.get("identity") != identity or reply.get("executed") != true: return {}
	for key: String in ["started_usec","finished_usec"]:
		if not reply.get(key) is int: return {}
	if not request.get("submitted_usec") is int: return {}
	var started := int(reply.started_usec)
	var finished := int(reply.finished_usec)
	var submitted := int(request.submitted_usec)
	if submitted < int(reservation.issued_usec) or started < submitted or finished < started or received_usec < finished: return {}
	if not reply.get("native_s_poll_epoch") is int or commit_clock_epoch < int(reply.native_s_poll_epoch): return {}
	var charged := finished - started
	var receipt := {"contract_id":"hardcore.resource.budget_settlement.v1", "reservation_id":id,
		"owner_session_id":_session_id, "identity":identity.duplicate(true), "s_commit_epoch":commit_clock_epoch,
		"main_started_usec":started, "main_finished_usec":finished, "charged_usec":charged,
		"receipt_received_usec":received_usec, "queue_wait_usec":started-submitted,
		"overrun_usec":maxi(0,charged-int(reservation.reserved_usec))}
	# No active outer scope: actual Main cost enters this epoch exactly once.
	_spent_usec += charged
	_lane_spent[int(reservation.lane)] += charged
	var category: Dictionary = _category(str(reservation.category))
	category.inclusive_usec += charged
	category.self_usec += charged
	category.maximum_quantum_usec = maxi(int(category.maximum_quantum_usec), charged)
	category.scopes += 1
	if reservation.lane == LANE_NECESSARY: category.necessary_scopes += 1
	_service_sequence += 1
	if _pending.has(reservation.category):
		_pending[reservation.category].last_service_epoch = _epoch
		_pending[reservation.category].last_service_sequence = _service_sequence
	_reservations.erase(id)
	_settlements[id] = receipt.duplicate(true)
	return receipt
func retire_settlement(id: int) -> bool:
	if not _settlements.has(id): return false
	_settlements.erase(id)
	return true
func live_obligations() -> int: return _reservations.size() + _settlements.size()
