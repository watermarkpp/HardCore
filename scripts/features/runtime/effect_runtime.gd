extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Handler := preload("res://scripts/features/handlers/ignite_handler.gd")
const Heap := preload("res://scripts/features/runtime/indexed_due_heap.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Presentation := preload("res://scripts/features/presentation/presentation_port.gd")
const Reservation := preload("res://scripts/features/contracts/effect_reservation.gd")
const MAX_PENDING_FACTS := 8192
const MAX_ACTIVE_STATES := 4096
const MAX_RECEIPTS := 65536
const MAX_STATES_PER_TARGET := preload("res://scripts/features/adapters/feature_authority.gd").MAX_STATES_PER_TARGET
var _world: RefCounted
var _clock: RefCounted
var _combat := WeakRef.new()
var _world_identity: Dictionary = {}
var _category := ""
var _batches: Dictionary = {}
var _batch_head := 0
var _batch_tail := 0
var _pending := 0
var _states: Dictionary = {}
var _states_per_target: Dictionary = {}
var _receipts: Dictionary = {}
var _heap := Heap.new()
var _presentation: RefCounted
var _prefer_due := true
var _reservations: Dictionary = {}
var _next_reservation := 0
var _reserved_facts := 0
var _reserved_states := 0
var _reserved_receipts := 0
var require_reservations := false
var last_admission_reason := ""
var _stats := {"ticks":0,"actual_loss":0,"started":0,"refreshed":0,"expired":0,"invalidated":0,"failed":0,"admitted_facts":0,"peak_states":0,"peak_pending":0,"optional_cue_missing":0,
	"peak_receipts":0,"retired_receipts":0,"peak_reservations":0,
	"tick_delivery_count":0,"maximum_tick_delivery_lateness_usec":0}
var errors: Array[String] = []

func configure(world: RefCounted, clock: RefCounted, combat: Node, presentation: RefCounted = null) -> bool:
	# An accepted state owns its clock, mutation port and cue lifecycle until
	# terminal drain. Replacing that owner mid-flight would orphan the old cue.
	if has_work() or world == null or clock == null or not is_instance_valid(combat) \
		or world.current_world_owner() == null:
		return false
	_world = world; _clock = clock; _combat = weakref(combat)
	var owner: Node = world.current_world_owner()
	_category = "feature_effects:" + str(owner.get_instance_id())
	_presentation = presentation
	if _presentation == null:
		_presentation = Presentation.new()
		_presentation.configure(world,DisplayServer.get_name() != "headless")
	return true

func active_count() -> int: return _states.size()
func heap_count() -> int: return _heap.size()
func pending_count() -> int: return _pending
func has_work() -> bool: return _pending > 0 or not _states.is_empty() or not _reservations.is_empty()
func has_due() -> bool: return _clock != null and _heap.due_usec() <= _clock.simulation_usec()
func metrics() -> Dictionary: return Graph.capture(_stats).value
func presentation() -> RefCounted: return _presentation

func reservation_snapshot() -> Dictionary:
	return {"actions":_reservations.size(),"facts":_reserved_facts,"states":_reserved_states,
		"promised_receipts":_reserved_receipts,"receipts":_receipts.size()}

func reserve_action(skill_id: String, bindings: Array, maximum_receivers: int, expected_release_id := "") -> RefCounted:
	last_admission_reason = ""
	if not _sync_world() or maximum_receivers < 0 or maximum_receivers > preload("res://scripts/features/runtime/damage_batch.gd").MAX_FACTS \
		or bindings.is_empty() or not preload("res://scripts/features/runtime/damage_batch.gd").validate_bindings(skill_id,bindings):
		last_admission_reason = "feature_action_bound_invalid"; return null
	var cost := maximum_receivers*bindings.size()
	var queued_cost := _unreserved_queued_cost()
	# Empty legal casts still own a producer record. Bound those records by the
	# existing queue capacity even when their proven fact/state bound is zero.
	if _reservations.size() >= MAX_PENDING_FACTS:
		last_admission_reason = "feature_action_producer_capacity"; return null
	if _pending+_reserved_facts+maximum_receivers > MAX_PENDING_FACTS:
		last_admission_reason = "feature_action_pending_capacity"; return null
	if _states.size()+_reserved_states+queued_cost+cost > MAX_ACTIVE_STATES:
		last_admission_reason = "feature_action_state_capacity"; return null
	if _receipts.size()+_reserved_receipts+queued_cost+cost > MAX_RECEIPTS:
		last_admission_reason = "feature_action_receipt_capacity"; return null
	var sources := _binding_sources(bindings) if maximum_receivers > 0 else {}
	if not _target_sources_fit(sources):
		last_admission_reason = "feature_action_target_capacity"; return null
	if _next_reservation == 9223372036854775807:
		last_admission_reason = "feature_action_identity_exhausted"; return null
	_next_reservation += 1
	_reservations[_next_reservation] = {"stage":"reserved","world":_world_identity,"skill_id":skill_id,
		"expected_release_id":expected_release_id,
		"bindings":Graph.capture(bindings).value,"sources":sources,"facts":maximum_receivers,
		"states":cost,"receipt_space":cost,"receipts":[]}
	_reserved_facts += maximum_receivers; _reserved_states += cost; _reserved_receipts += cost
	_stats.peak_reservations = maxi(int(_stats.peak_reservations),_reservations.size())
	return Reservation.create(self,_next_reservation)

func _reservation_release_is_valid(sequence: int, release_id: String) -> bool:
	if _world == null or not _reservations.has(sequence): return false
	var value: Dictionary = _reservations[sequence]
	return value.stage == "reserved" and _world.matches_world(value.world) and not release_id.is_empty() \
		and (str(value.expected_release_id).is_empty() or value.expected_release_id == release_id)

func _claim_reservation(sequence: int, identity: Dictionary, release_id: String, skill_id: String, bindings: Array) -> Dictionary:
	if not _sync_world() or not _reservations.has(sequence): return {"success":false}
	var value: Dictionary = _reservations[sequence]
	if value.stage != "reserved" or value.world != identity or value.skill_id != skill_id or value.bindings != bindings:
		return {"success":false}
	if not str(value.expected_release_id).is_empty() and value.expected_release_id != release_id: return {"success":false}
	value.stage = "producing"
	return {"success":true,"maximum_facts":int(value.facts)}

func _close_reservation_producer(sequence: int) -> void:
	if not _reservations.has(sequence): return
	# A successful claim transfers production to the batch; queue admission
	# then transfers it to the consumer. Old action cancellation owns neither.
	if _reservations[sequence].stage == "reserved": _retire_reservation(sequence)

func _close_reservation_batch(sequence: int) -> void:
	if not _reservations.has(sequence): return
	# Empty, rejected or abandoned synchronous work has reached its terminal
	# boundary. A queued batch remains exclusively owned by its consumer.
	if _reservations[sequence].stage == "producing": _retire_reservation(sequence)

func _retire_reservation(sequence: int) -> void:
	if not _reservations.has(sequence): return
	var value: Dictionary = _reservations[sequence]
	_reserved_facts -= int(value.facts); _reserved_states -= int(value.states)
	_reserved_receipts -= int(value.receipt_space)
	# Only a claimed, sealed, completely consumed one-shot producer retires
	# these receipts. Unticketed historical receipts retain their old lifetime.
	for receipt: String in value.receipts:
		_receipts.erase(receipt); _stats.retired_receipts += 1
	_reservations.erase(sequence)

func _unreserved_queued_cost() -> int:
	var result := 0
	for work: Dictionary in _batches.values():
		if int(work.get("admission_id",0)) != 0: continue
		for index in range(int(work.cursor),work.entries.size()): result += work.entries[index].bindings.size()
	return result

static func _binding_sources(bindings: Array) -> Dictionary:
	var result := {}
	for binding: Dictionary in bindings:
		result[JSON.stringify([binding.handle,binding.definition.mechanic_id,Handler.EFFECT_ID])] = true
	return result

func _target_sources_fit(additional: Dictionary) -> bool:
	var promised := additional.duplicate()
	for reservation: Dictionary in _reservations.values(): promised.merge(reservation.sources)
	if promised.size() > MAX_STATES_PER_TARGET: return false
	var targets := {}
	for state: Dictionary in _states.values():
		var command: Dictionary = state.command
		var values: Dictionary = targets.get(state.target_key,{})
		values[JSON.stringify([command.source_handle,command.mechanic_id,command.effect_id])] = true
		targets[state.target_key] = values
	for work: Dictionary in _batches.values():
		for index in range(int(work.cursor),work.entries.size()):
			var entry: Dictionary = work.entries[index]
			var key := JSON.stringify(entry.fact.target)
			var values: Dictionary = targets.get(key,{})
			values.merge(_binding_sources(entry.bindings)); targets[key] = values
	for values: Dictionary in targets.values():
		values.merge(promised)
		if values.size() > MAX_STATES_PER_TARGET: return false
	return true

func _sync_world() -> bool:
	if _world == null or _world.current_world_owner() == null:
		clear(); return false
	var current: Dictionary = _world.capture_world()
	if current != _world_identity:
		clear()
		_world_identity = current
	return not current.is_empty()

func submit_batch(batch: RefCounted) -> bool:
	if batch == null or batch.get_script() != preload("res://scripts/features/runtime/damage_batch.gd") or not _sync_world():
		return false
	var count: int = batch.pending_fact_count()
	if count == 0: return false
	var ticket: RefCounted = batch.reservation()
	var admission_id := 0
	if ticket != null:
		if not ticket.belongs_to(self): return false
		admission_id = ticket.sequence()
		if not _reservations.has(admission_id) or _reservations[admission_id].stage != "producing" \
			or count > int(_reservations[admission_id].facts): return false
	elif require_reservations:
		_error("feature_unreserved_producer"); return false
	var own_facts := int(_reservations[admission_id].facts) if admission_id > 0 else 0
	if _pending+_reserved_facts-own_facts+count > MAX_PENDING_FACTS:
		_error("feature_pending_capacity"); return false
	if admission_id == 0 and not _reservations.is_empty():
		var cost: int = count*batch.binding_count()+_unreserved_queued_cost()
		if _states.size()+_reserved_states+cost > MAX_ACTIVE_STATES \
			or _receipts.size()+_reserved_receipts+cost > MAX_RECEIPTS:
			_error("feature_reserved_capacity_protected"); return false
		if not _target_sources_fit(_binding_sources(batch.event_bindings())):
			_error("feature_reserved_target_capacity_protected"); return false
	# Main-thread admission and the one-shot transfer are synchronous. Nothing
	# consumes the batch before its entire fact buffer has a queue destination.
	var entries: Array = batch.consume()
	if admission_id > 0:
		_reserved_facts -= own_facts
		_reservations[admission_id].facts = 0; _reservations[admission_id].stage = "queued"
	_batches[_batch_tail] = {"entries":entries,"cursor":0,"admission_id":admission_id}
	_batch_tail += 1
	_pending += entries.size()
	_stats.peak_pending = maxi(int(_stats.peak_pending),_pending)
	return true

func pump() -> int:
	if not _sync_world(): return 0
	var owner: Node = _world.current_world_owner()
	if owner.get_tree().paused: return 0
	var served := 0
	var runnable := _pending > 0 or has_due()
	Budget.mark_pending(_category,runnable,true,false,owner,true)
	while runnable:
		var token := Budget.begin(_category)
		if token <= 0: break
		# One admitted fact or one tick is a bounded quantum. Facts and bindings
		# were frozen and capacity checked before this queue accepted them.
		if has_due() and (_pending == 0 or _prefer_due): _tick_one(); _prefer_due = false
		else: _dispatch_one_fact(); _prefer_due = true
		Budget.end(token)
		served += 1
		runnable = _pending > 0 or has_due()
		Budget.mark_pending(_category,runnable,true,false,owner,true)
	return served

func _dispatch_one_fact() -> void:
	var work: Dictionary = _batches[_batch_head]
	var entry: Dictionary = work.entries[work.cursor]
	var admission_id := int(work.admission_id)
	work.cursor += 1; _pending -= 1
	var complete: bool = work.cursor == work.entries.size()
	if complete:
		# A continuous producer need not let the queue become empty. Retire the
		# completed buffer immediately without shifting or copying live work.
		_batches.erase(_batch_head)
		_batch_head += 1
	if _pending == 0:
		_batch_head = 0; _batch_tail = 0
	_deliver_fact(entry,admission_id)
	if complete and admission_id > 0: _retire_reservation(admission_id)

func _deliver_fact(entry: Dictionary, admission_id: int) -> void:
	var fact: Dictionary = entry.fact
	if not bool(fact.target_survived_commit) or int(fact.actual_loss) <= 0 or entry.target.resolve() == null:
		return
	_stats.admitted_facts += 1
	for binding: Dictionary in entry.bindings:
		var producer: Variant = ["reservation",admission_id] if admission_id > 0 else fact.release_id
		var receipt := JSON.stringify([producer,fact.target,binding.handle])
		if _receipts.has(receipt): continue
		if _receipts.size() >= MAX_RECEIPTS:
			_error("feature_receipt_capacity"); return
		_receipts[receipt] = true
		_stats.peak_receipts = maxi(int(_stats.peak_receipts),_receipts.size())
		if admission_id > 0:
			_reservations[admission_id].receipts.append(receipt)
			_reservations[admission_id].receipt_space -= 1; _reserved_receipts -= 1
		for command: Dictionary in Handler.commands(fact,binding):
			_apply_command(command,entry)

func _apply_command(command: Dictionary, entry: Dictionary) -> void:
	if command.op != "ApplyStatus" or command.handler_id != Handler.ID or command.effect_id != Handler.EFFECT_ID:
		_error("unknown_feature_command"); return
	var target: Node = entry.target.resolve()
	if target == null or not target.has_method("has_actor_capability"): return
	if target.has_actor_capability("hc.immune.periodic"): return
	var target_key := JSON.stringify(command.target)
	var handle := JSON.stringify([command.target,command.source_handle,command.mechanic_id,command.effect_id])
	var accepted_at := int(entry.fact.accepted_simulation_usec)
	if _states.has(handle):
		var state: Dictionary = _states[handle]
		state.raw_per_tick = maxi(int(state.raw_per_tick),int(command.raw_per_tick))
		state.expires = maxi(int(state.expires),accepted_at+int(command.duration_usec))
		state.period = int(command.period_usec)
		# next_due remains unchanged: refresh never creates an immediate tick or
		# a second heap node, including refresh after that tick became overdue.
		_stats.refreshed += 1
		_presentation.refresh(handle,int(state.raw_per_tick))
		return
	if _states.size() >= MAX_ACTIVE_STATES or int(_states_per_target.get(target_key,0)) >= MAX_STATES_PER_TARGET:
		_error("feature_state_capacity"); return
	var admission_id := int(entry.get("admission_id",0))
	if admission_id > 0:
		if not _reservations.has(admission_id) or int(_reservations[admission_id].states) <= 0:
			_error("feature_state_reservation_missing"); return
		_reservations[admission_id].states -= 1; _reserved_states -= 1
	var state := {"target":entry.target,"source":entry.source,"command":command,"target_key":target_key,
		"resource_lease":entry.get("resource_lease"),
		"raw_per_tick":int(command.raw_per_tick),"period":int(command.period_usec),
		"next_due":accepted_at+int(command.period_usec),"expires":accepted_at+int(command.duration_usec),"ticks":0}
	_states[handle] = state
	_states_per_target[target_key] = int(_states_per_target.get(target_key,0))+1
	_heap.put(handle,int(state.next_due))
	_stats.started += 1; _stats.peak_states = maxi(int(_stats.peak_states),_states.size())
	if not _presentation.start(handle,entry.target,command,entry.get("resource_lease")):
		if command.cue_policy == "required_procedural": _error("feature_required_cue_failed")
		else: _stats.optional_cue_missing += 1

func _tick_one() -> void:
	var handle := _heap.pop()
	if handle.is_empty() or not _states.has(handle):
		_error("feature_heap_state_mismatch"); return
	var state: Dictionary = _states[handle]
	var target: Node = state.target.resolve()
	var combat: Node = _combat.get_ref() as Node
	if target == null or not is_instance_valid(combat):
		_stats.invalidated += 1; _stop(handle); return
	if int(state.next_due) > int(state.expires):
		_stats.expired += 1; _stop(handle); return
	var source: Node2D = state.source.resolve(false) as Node2D if state.source != null else null
	var rng := RandomNumberGenerator.new()
	rng.seed = JSON.stringify(["hc.rng.periodic.v1",handle,int(state.next_due)]).sha256_text().substr(0,15).hex_to_int()
	# Count valid damage-port delivery attempts, including a rejected port call.
	# `ticks` counts successful returns, `failed` rejected returns; invalidated
	# and expired states never reach this boundary. Heap sampling after service
	# misses late work that has already been consumed in this frame.
	_stats.tick_delivery_count += 1
	_stats.maximum_tick_delivery_lateness_usec = maxi(int(_stats.maximum_tick_delivery_lateness_usec),
		maxi(0,_clock.simulation_usec()-int(state.next_due)))
	var result: Dictionary = combat.apply_feature_periodic_damage(target,int(state.raw_per_tick),source,rng,state.command.historical_credit)
	if not bool(result.success):
		_error(str(result.reason)); _stats.failed += 1; _stop(handle); return
	_stats.ticks += 1; _stats.actual_loss += int(result.actual_loss)
	state.ticks += 1; state.next_due += int(state.period)
	if state.target.resolve() == null:
		_stats.invalidated += 1; _stop(handle)
	elif int(state.next_due) > int(state.expires):
		_stats.expired += 1; _stop(handle)
	else: _heap.put(handle,int(state.next_due))

func _stop(handle: String) -> void:
	if not _states.has(handle): return
	var key: String = _states[handle].target_key
	_states_per_target[key] = int(_states_per_target[key])-1
	if int(_states_per_target[key]) == 0: _states_per_target.erase(key)
	_states.erase(handle); _heap.remove(handle)
	_presentation.stop(handle)

func clear() -> void:
	# Stop all logic handles, including cues with declared missing visuals.
	# Count cancellation before draining so every started state has a terminal
	# outcome; no target or presentation mutation survives an owner change.
	_stats.invalidated += _states.size()
	for handle: String in _states.keys(): _stop(handle)
	if _presentation != null: _presentation.clear()
	_states.clear(); _states_per_target.clear(); _receipts.clear(); _batches.clear()
	_reservations.clear(); _reserved_facts = 0; _reserved_states = 0; _reserved_receipts = 0
	_heap.clear(); _batch_head = 0; _batch_tail = 0; _pending = 0
	if not _category.is_empty(): Budget.mark_pending(_category,false)

func _error(reason: String) -> void:
	if reason not in errors: errors.append(reason)
