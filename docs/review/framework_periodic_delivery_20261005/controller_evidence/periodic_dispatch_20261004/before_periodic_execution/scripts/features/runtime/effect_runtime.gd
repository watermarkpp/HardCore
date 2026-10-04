extends RefCounted

const Graph := preload("res://scripts/features/contracts/plain_graph.gd")
const Handler := preload("res://scripts/features/handlers/ignite_handler.gd")
const Handlers := preload("res://scripts/features/handlers/handler_registry.gd")
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
var _delivery_generation := 0
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
var _reserved_children := 0
var _children: Dictionary = {}
var _child_serial := 0
var _child_executor := Callable()
var _pumping := false
var require_reservations := false
var last_admission_reason := ""
var _stats := {"ticks":0,"actual_loss":0,"started":0,"refreshed":0,"expired":0,"invalidated":0,"failed":0,"admitted_facts":0,"healing_commands":0,"actual_healing":0,"peak_states":0,"peak_pending":0,"optional_cue_missing":0,
	"peak_receipts":0,"retired_receipts":0,"peak_reservations":0,
	"tick_delivery_count":0,"maximum_tick_delivery_lateness_usec":0,"child_actions":0,"peak_children":0}
var errors: Array[String] = []

func configure(world: RefCounted, clock: RefCounted, combat: Node, presentation: RefCounted = null) -> bool:
	# An accepted state owns its clock, mutation port and cue lifecycle until
	# terminal drain. Replacing that owner mid-flight would orphan the old cue.
	if _pumping or has_work() or world == null or clock == null or not is_instance_valid(combat) \
		or world.current_world_owner() == null:
		return false
	_world = world; _clock = clock; _combat = weakref(combat)
	_delivery_generation += 1
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

func configure_child_executor(executor: Callable) -> bool:
	if _pumping or _world==null or has_work() or not executor.is_valid() or executor.get_object()!=_world.current_world_owner(): return false
	_child_executor=executor
	return true

func child_count() -> int: return _children.size()

func reservation_snapshot() -> Dictionary:
	return {"actions":_reservations.size(),"facts":_reserved_facts,"states":_reserved_states,
		"promised_receipts":_reserved_receipts,"receipts":_receipts.size(),"children":_children.size(),"promised_children":_reserved_children}

func reserve_action(skill_id: String, bindings: Array, maximum_receivers: int, expected_release_id := "", maximum_child_receivers := -1) -> RefCounted:
	last_admission_reason = ""
	if not _sync_world() or maximum_receivers < 0 or maximum_receivers > preload("res://scripts/features/runtime/damage_batch.gd").MAX_FACTS \
		or bindings.is_empty() or not preload("res://scripts/features/runtime/damage_batch.gd").validate_bindings(skill_id,bindings):
		last_admission_reason = "feature_action_bound_invalid"; return null
	var cost := maximum_receivers*bindings.size()
	var state_cost := maximum_receivers*Handlers.persistent_binding_count(bindings)
	var fact_cost := maximum_receivers
	var chain := _chain_cost(bindings,maximum_receivers if maximum_child_receivers<0 else maximum_child_receivers)
	if not chain.success:
		last_admission_reason=chain.reason; return null
	if not chain.value.is_empty():
		if expected_release_id.is_empty() or not _child_executor.is_valid():
			last_admission_reason="feature_child_executor_missing"; return null
		fact_cost=int(chain.value.cost.facts); cost=int(chain.value.cost.receipts); state_cost=int(chain.value.cost.states)
		if _children.size()+_reserved_children+int(chain.value.cost.child_actions)>MAX_PENDING_FACTS:
			last_admission_reason="feature_child_pending_capacity"; return null
	var queued_cost := _unreserved_queued_cost()
	# Empty legal casts still own a producer record. Bound those records by the
	# existing queue capacity even when their proven fact/state bound is zero.
	if _reservations.size() >= MAX_PENDING_FACTS:
		last_admission_reason = "feature_action_producer_capacity"; return null
	if _pending+_reserved_facts+fact_cost > MAX_PENDING_FACTS:
		last_admission_reason = "feature_action_pending_capacity"; return null
	if _states.size()+_reserved_states+queued_cost.states+state_cost > MAX_ACTIVE_STATES:
		last_admission_reason = "feature_action_state_capacity"; return null
	if _receipts.size()+_reserved_receipts+queued_cost.receipts+cost > MAX_RECEIPTS:
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
		"states":state_cost,"receipt_space":cost,"receipts":[],"chain":chain.value}
	var value: Dictionary=_reservations[_next_reservation]
	value.facts=fact_cost
	if not chain.value.is_empty():
		value.branches={expected_release_id:{"stage":"reserved","ticket_id":0,"source_class":"direct","context":Graph.capture({
			"contract_id":"hardcore.combat.chain_context.v1","root_release_id":expected_release_id,
			"release_id":expected_release_id,"parent_release_id":"","root_skill_id":skill_id,
			"generation":0,"maximum_generation":chain.value.maximum_generation},16,2).value}}
		value.state_owners=0; value.child_space=int(chain.value.cost.child_actions)
		value.state_loan_handles={}
		value.total_fact_space=int(chain.value.cost.total_facts)
		_reserved_children+=value.child_space
	_reserved_facts += fact_cost; _reserved_states += state_cost; _reserved_receipts += cost
	_stats.peak_reservations = maxi(int(_stats.peak_reservations),_reservations.size())
	var ticket: RefCounted=Reservation.create(self,_next_reservation)
	if not chain.value.is_empty(): value.branches[expected_release_id].ticket_id=ticket.get_instance_id()
	return ticket

func _chain_cost(bindings: Array, maximum: int) -> Dictionary:
	var count:=0; var generations:=0
	for binding: Dictionary in bindings:
		if binding.definition.handler_id!="hc.death_burst.v1": continue
		var g:=int(binding.definition.config.maximum_generation)
		if count>0 and g!=generations: return {"success":false,"reason":"feature_child_generation_conflict"}
		generations=g; count+=1
	if count==0: return {"success":true,"value":{}}
	if maximum<0 or maximum>preload("res://scripts/features/runtime/damage_batch.gd").MAX_FACTS:
		return {"success":false,"reason":"feature_child_receiver_bound_invalid"}
	var proof:=preload("res://scripts/features/compilation/child_capacity_proof.gd").compile_state_loan_residency({
		"maximum_receivers":maximum,"child_bindings":count,"maximum_generation":generations,
		"binding_count":bindings.size(),"persistent_bindings":Handlers.persistent_binding_count(bindings)},
		{"pending_facts":MAX_PENDING_FACTS,"active_states":MAX_ACTIVE_STATES,"receipts":MAX_RECEIPTS})
	if not proof.success: return proof
	return {"success":true,"value":{"maximum_generation":generations,"maximum_receivers":maximum,"cost":proof.cost}}

func _reservation_chain_context(sequence: int, release_id: String, branch: String) -> Dictionary:
	if not _reservations.has(sequence) or _reservations[sequence].chain.is_empty(): return {}
	var value: Dictionary=_reservations[sequence]
	var key: String=release_id if branch.is_empty() else branch
	return value.branches[key].context if value.branches.has(key) and key==release_id else {}

func _reservation_source_class(sequence: int, release_id: String, branch: String) -> String:
	if not _reservations.has(sequence): return ""
	var value: Dictionary=_reservations[sequence]
	if value.chain.is_empty():
		return "direct" if branch.is_empty() and (str(value.expected_release_id).is_empty() or value.expected_release_id==release_id) else ""
	var key: String=release_id if branch.is_empty() else branch
	return str(value.branches[key].source_class) if key==release_id and value.branches.has(key) else ""

func _child_request_authorized(sequence: int, branch: String, ticket_id: int, request: Dictionary) -> bool:
	if not _reservations.has(sequence) or _reservations[sequence].chain.is_empty() \
		or not _world.matches_world(_reservations[sequence].world): return false
	var producer: Dictionary=_reservations[sequence].branches.get(branch,{})
	var lease: Variant=request.get("child_action_lease")
	return not producer.is_empty() and producer.stage=="available" and producer.ticket_id==ticket_id \
		and lease is RefCounted and lease.get_instance_id()==int(producer.get("request_owner_id",0))

func _reservation_release_is_valid(sequence: int, release_id: String) -> bool:
	if _world == null or not _reservations.has(sequence): return false
	var value: Dictionary = _reservations[sequence]
	return value.stage == "reserved" and _world.matches_world(value.world) and not release_id.is_empty() \
		and (str(value.expected_release_id).is_empty() or value.expected_release_id == release_id)

func _reservation_batch_owner_is_current(sequence: int, branch: String) -> bool:
	if _world==null or not _reservations.has(sequence): return false
	var value: Dictionary=_reservations[sequence]
	if not _world.matches_world(value.world): return false
	if value.chain.is_empty(): return value.stage in ["producing","queued"]
	var key: String=value.expected_release_id if branch.is_empty() else branch
	return value.branches.has(key) and value.branches[key].stage in ["producing","queued"]

func _claim_reservation(sequence: int, identity: Dictionary, release_id: String, skill_id: String, bindings: Array, branch := "", ticket_id := 0) -> Dictionary:
	if not _sync_world() or not _reservations.has(sequence): return {"success":false}
	var value: Dictionary = _reservations[sequence]
	if not value.chain.is_empty():
		var key: String=release_id if branch.is_empty() else branch
		var expected_skill: String=value.skill_id if branch.is_empty() else "hc.child.death_burst.v1"
		if value.world!=identity or skill_id!=expected_skill or value.bindings!=bindings or not value.branches.has(key): return {"success":false}
		var producer: Dictionary=value.branches[key]
		if key!=release_id or producer.ticket_id!=ticket_id or producer.stage not in ["reserved","available"]: return {"success":false}
		if int(value.total_fact_space)<int(value.chain.maximum_receivers): return {"success":false}
		producer.stage="producing"
		if branch.is_empty(): value.stage="producing"
		return {"success":true,"maximum_facts":int(value.chain.maximum_receivers)}
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

func _close_reservation_batch(sequence: int, branch := "") -> void:
	if not _reservations.has(sequence): return
	var value: Dictionary=_reservations[sequence]
	if not value.chain.is_empty():
		var key: String=value.expected_release_id if branch.is_empty() else branch
		if value.branches.has(key) and value.branches[key].stage in ["producing","available"]:
			value.branches.erase(key); _retire_chain_if_terminal(sequence)
		return
	# Empty, rejected or abandoned synchronous work has reached its terminal
	# boundary. A queued batch remains exclusively owned by its consumer.
	if _reservations[sequence].stage == "producing": _retire_reservation(sequence)

func _retire_reservation(sequence: int) -> void:
	if not _reservations.has(sequence): return
	var value: Dictionary = _reservations[sequence]
	_reserved_facts -= int(value.facts); _reserved_states -= int(value.states)
	_reserved_receipts -= int(value.receipt_space)
	if not value.chain.is_empty(): _reserved_children-=int(value.child_space)
	# Only a claimed, sealed, completely consumed one-shot producer retires
	# these receipts. Unticketed historical receipts retain their old lifetime.
	for receipt: String in value.receipts:
		_receipts.erase(receipt); _stats.retired_receipts += 1
	_reservations.erase(sequence)

func _retire_chain_if_terminal(sequence: int) -> void:
	if not _reservations.has(sequence): return
	var value: Dictionary=_reservations[sequence]
	if value.branches.is_empty() and int(value.state_owners)==0: _retire_reservation(sequence)

func _unreserved_queued_cost() -> Dictionary:
	var result := {"states":0,"receipts":0}
	for work: Dictionary in _batches.values():
		if int(work.get("admission_id",0)) != 0: continue
		for index in range(int(work.cursor),work.entries.size()):
			var bindings: Array = work.entries[index].bindings
			result.receipts += bindings.size()
			result.states += Handlers.persistent_binding_count(bindings)
	return result

static func _binding_sources(bindings: Array) -> Dictionary:
	var result := {}
	for binding: Dictionary in bindings:
		var contract := Handlers.contract(binding.definition.handler_id)
		if int(contract.states) > 0:
			result[JSON.stringify([binding.handle,binding.definition.mechanic_id,contract.effect_id])] = true
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
		if not _reservations.has(admission_id) or count > int(_reservations[admission_id].facts): return false
		var reserved: Dictionary=_reservations[admission_id]
		if reserved.chain.is_empty():
			if reserved.stage!="producing": return false
		else:
			var key: String=reserved.expected_release_id if ticket.branch().is_empty() else ticket.branch()
			if not reserved.branches.has(key) or reserved.branches[key].stage!="producing": return false
	elif require_reservations:
		_error("feature_unreserved_producer"); return false
	var chain_batch: bool=admission_id>0 and not _reservations[admission_id].chain.is_empty()
	var own_facts := (count if chain_batch else int(_reservations[admission_id].facts)) if admission_id>0 else 0
	if _pending+_reserved_facts-own_facts+count > MAX_PENDING_FACTS:
		_error("feature_pending_capacity"); return false
	if admission_id == 0 and not _reservations.is_empty():
		var queued := _unreserved_queued_cost()
		var cost: int = count*batch.binding_count()+int(queued.receipts)
		var state_cost: int = count*Handlers.persistent_binding_count(batch.event_bindings())+int(queued.states)
		if _states.size()+_reserved_states+state_cost > MAX_ACTIVE_STATES \
			or _receipts.size()+_reserved_receipts+cost > MAX_RECEIPTS:
			_error("feature_reserved_capacity_protected"); return false
		if not _target_sources_fit(_binding_sources(batch.event_bindings())):
			_error("feature_reserved_target_capacity_protected"); return false
	# Main-thread admission and the one-shot transfer are synchronous. Nothing
	# consumes the batch before its entire fact buffer has a queue destination.
	var entries: Array = batch.consume()
	if admission_id > 0:
		_reserved_facts -= own_facts
		_reservations[admission_id].facts -= own_facts; _reservations[admission_id].stage = "queued"
		if chain_batch:
			var key: String=_reservations[admission_id].expected_release_id if ticket.branch().is_empty() else ticket.branch()
			_reservations[admission_id].branches[key].stage="queued"
			_reservations[admission_id].branches[key].receipts=[]
			_reservations[admission_id].total_fact_space-=count
	_batches[_batch_tail] = {"entries":entries,"cursor":0,"admission_id":admission_id,
		"branch":(str(_reservations[admission_id].expected_release_id) if ticket.branch().is_empty() else ticket.branch()) if chain_batch else ""}
	_batch_tail += 1
	_pending += entries.size()
	_stats.peak_pending = maxi(int(_stats.peak_pending),_pending)
	return true

func pump() -> int:
	# A synchronous HP/heal observer may call this public entry again. The
	# outer consumer still owns its unreturned fact/producer and budget scope.
	# Serial residency and branch retirement require one consumer at a time.
	if _pumping: return 0
	if not _sync_world(): return 0
	var owner: Node = _world.current_world_owner()
	if owner.get_tree().paused: return 0
	_pumping=true
	var generation:=_delivery_generation
	var served := 0
	var runnable := _pending > 0 or has_due() or not _children.is_empty()
	Budget.mark_pending(_category,runnable,true,false,owner,true)
	while runnable:
		var token := Budget.begin(_category)
		if token <= 0: break
		# One admitted fact or one tick is a bounded quantum. Facts and bindings
		# were frozen and capacity checked before this queue accepted them.
		if has_due() and (_pending == 0 or _prefer_due): _tick_one(); _prefer_due = false
		elif _pending>0: _dispatch_one_fact(); _prefer_due = true
		else: _dispatch_one_child(); _prefer_due=true
		Budget.end(token)
		served += 1
		if generation!=_delivery_generation: break
		runnable = _pending > 0 or has_due() or not _children.is_empty()
		Budget.mark_pending(_category,runnable,true,false,owner,true)
	_pumping=false
	return served

func _dispatch_one_fact() -> void:
	var work: Dictionary = _batches[_batch_head]
	var entry: Dictionary = work.entries[work.cursor]
	var admission_id := int(work.admission_id)
	work.cursor += 1; _pending -= 1
	if admission_id>0 and _reservations.has(admission_id) and not _reservations[admission_id].chain.is_empty():
		# Consumed storage remains a live root promise, including inside any
		# synchronous observer. Transfer one pending slot back immediately;
		# waiting for the whole batch would temporarily lend it to other roots.
		_reservations[admission_id].facts+=1; _reserved_facts+=1
	var complete: bool = work.cursor == work.entries.size()
	if complete:
		# A continuous producer need not let the queue become empty. Retire the
		# completed buffer immediately without shifting or copying live work.
		_batches.erase(_batch_head)
		_batch_head += 1
	if _pending == 0:
		_batch_head = 0; _batch_tail = 0
	_deliver_fact(entry,admission_id)
	if complete and admission_id>0 and _reservations.has(admission_id):
		if _reservations[admission_id].chain.is_empty(): _retire_reservation(admission_id)
		else:
			# The batch is sealed and consumed, its minted ticket is closed, and
			# the branch can never be minted again. All of its consumers finished.
			# Pending children/state owners retain the root, not this producer ID.
			var value: Dictionary=_reservations[admission_id]
			for receipt: String in value.branches[work.branch].receipts:
				_receipts.erase(receipt); _stats.retired_receipts+=1
				value.receipt_space+=1; _reserved_receipts+=1
			_reservations[admission_id].branches.erase(work.branch)
			_retire_chain_if_terminal(admission_id)

func _deliver_fact(entry: Dictionary, admission_id: int) -> void:
	var fact: Dictionary = entry.fact
	var generation := _delivery_generation
	if int(fact.actual_loss) <= 0:
		return
	_stats.admitted_facts += 1
	for binding: Dictionary in entry.bindings:
		# Any prior command may synchronously retire the world/runtime. Remaining
		# old work loses its owner; it cannot mutate a replacement world or ticket.
		if generation != _delivery_generation or not _world.matches_world(fact.target.world): return
		if admission_id > 0 and (not _reservations.has(admission_id) or _reservations[admission_id].stage != "queued"):
			_error("feature_dispatch_reservation_missing"); return
		var producer: Variant = ["reservation",admission_id] if admission_id > 0 else fact.release_id
		var chained: bool=admission_id>0 and not _reservations[admission_id].chain.is_empty()
		var receipt := JSON.stringify([producer,[fact.release_id,fact.target] if chained else fact.target,binding.handle])
		if _receipts.has(receipt): continue
		if _receipts.size() >= MAX_RECEIPTS:
			_error("feature_receipt_capacity"); return
		_receipts[receipt] = true
		_stats.peak_receipts = maxi(int(_stats.peak_receipts),_receipts.size())
		if admission_id > 0:
			if chained: _reservations[admission_id].branches[fact.release_id].receipts.append(receipt)
			else: _reservations[admission_id].receipts.append(receipt)
			_reservations[admission_id].receipt_space -= 1; _reserved_receipts -= 1
		for command: Dictionary in Handlers.commands(fact,binding):
			_apply_command(command,entry)

func _apply_command(command: Dictionary, entry: Dictionary) -> void:
	if command.op=="RequestChildAction" and command.handler_id=="hc.death_burst.v1":
		_queue_child(command,entry)
		return
	if command.op == "ModifyResource" and command.handler_id == "hc.lifesteal.v1" \
		and command.resource == "hp" and command.mode == "restore":
		var combat: Node = _combat.get_ref() as Node
		if not is_instance_valid(combat): return
		var result: Dictionary = combat.apply_feature_source_restore(entry.source,command.recipient,int(command.amount))
		if not result.success: _error(str(result.reason)); return
		_stats.healing_commands += 1; _stats.actual_healing += int(result.actual_gain)
		return
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
		_hold_chain_state(state,int(entry.get("admission_id",0)))
		state.raw_per_tick = maxi(int(state.raw_per_tick),int(command.raw_per_tick))
		state.expires = maxi(int(state.expires),accepted_at+int(command.duration_usec))
		state.period = int(command.period_usec)
		# next_due remains unchanged: refresh never creates an immediate tick or
		# a second heap node, including refresh after that tick became overdue.
		_stats.refreshed += 1
		_presentation.refresh(handle,int(state.raw_per_tick))
		return
	var admission_id := int(entry.get("admission_id",0))
	if admission_id>0 and _reservations.has(admission_id) and not _reservations[admission_id].chain.is_empty() \
		and int(_reservations[admission_id].states)<=0:
		var generation:=_delivery_generation
		_reclaim_invalid_state_loan(admission_id)
		# Stopping an old cue can synchronously retire its owner. Reclamation
		# cannot grant an old command authority over that replacement runtime.
		if generation!=_delivery_generation or not _reservations.has(admission_id) or entry.target.resolve()==null: return
	if _states.size() >= MAX_ACTIVE_STATES or int(_states_per_target.get(target_key,0)) >= MAX_STATES_PER_TARGET:
		_error("feature_state_capacity"); return
	if admission_id > 0:
		if not _reservations.has(admission_id) or int(_reservations[admission_id].states) <= 0:
			_error("feature_state_reservation_missing"); return
		_reservations[admission_id].states -= 1; _reserved_states -= 1
	var state := {"target":entry.target,"source":entry.source,"command":command,"target_key":target_key,
		"resource_lease":entry.get("resource_lease"),
		"state_loan_origin":admission_id if admission_id>0 and not _reservations[admission_id].chain.is_empty() else 0,
		"raw_per_tick":int(command.raw_per_tick),"period":int(command.period_usec),
		"next_due":accepted_at+int(command.period_usec),"expires":accepted_at+int(command.duration_usec),"ticks":0,"chain_owners":{}}
	if int(state.state_loan_origin)>0: _reservations[admission_id].state_loan_handles[handle]=true
	_hold_chain_state(state,admission_id)
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
	var generation := _delivery_generation
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
	# The real HP port can synchronously retire this runtime or state. Its
	# committed result still counts, but the old tick no longer owns scheduling.
	var current_owner := generation == _delivery_generation and _states.has(handle) and is_same(_states[handle],state)
	if not bool(result.success):
		_error(str(result.reason)); _stats.failed += 1
		if current_owner: _stop(handle)
		return
	_stats.ticks += 1; _stats.actual_loss += int(result.actual_loss)
	if not current_owner: return
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
	var owners: Dictionary=_states[handle].get("chain_owners",{})
	var origin:=int(_states[handle].get("state_loan_origin",0))
	_states.erase(handle); _heap.remove(handle)
	if origin>0 and _reservations.has(origin):
		_reservations[origin].state_loan_handles.erase(handle)
		_reservations[origin].states+=1; _reserved_states+=1
	_presentation.stop(handle)
	for sequence: int in owners:
		if _reservations.has(sequence):
			_reservations[sequence].state_owners-=1; _retire_chain_if_terminal(sequence)

func _reclaim_invalid_state_loan(sequence: int) -> void:
	# Reclaim one origin loan only when its next accepted command needs it.
	# Existing committed facts/child branches are separate owners and remain
	# queued; no receipt or still-valid state is evicted to make room.
	for handle: String in _reservations[sequence].state_loan_handles.keys():
		if _states[handle].target.resolve()!=null: continue
		_stats.invalidated+=1; _stop(handle)
		return

func _hold_chain_state(state: Dictionary, sequence: int) -> void:
	if sequence==0 or not _reservations.has(sequence) or _reservations[sequence].chain.is_empty(): return
	if not state.chain_owners.has(sequence):
		state.chain_owners[sequence]=true; _reservations[sequence].state_owners+=1

func _queue_child(command: Dictionary, entry: Dictionary) -> void:
	var sequence:=int(entry.get("admission_id",0))
	if sequence==0 or not _reservations.has(sequence) or _reservations[sequence].chain.is_empty():
		_error("feature_child_admission_missing"); return
	var value: Dictionary=_reservations[sequence]
	if int(value.child_space)<=0 or int(command.maximum_generation)!=int(value.chain.maximum_generation) \
		or command.root_release_id!=value.expected_release_id or command.root_skill_id!=value.skill_id:
		_error("feature_child_promise_exhausted"); return
	if _child_serial==9223372036854775807:
		_error("feature_child_identity_exhausted"); return
	_child_serial+=1
	var release_id: String=value.expected_release_id+":child:"+str(_child_serial)
	var made:=preload("res://scripts/skills/skill_runtime_router.gd").create_child_request(command,_world,release_id)
	if not made.success: _error("feature_child_request_rejected"); return
	var ticket: RefCounted=Reservation.create_child(self,sequence,release_id)
	var lease: RefCounted=made.request.child_action_lease
	value.branches[release_id]={"stage":"child_queued","ticket_id":ticket.get_instance_id(),"source_class":"child",
		"request_owner_id":lease.get_instance_id(),"context":lease.chain_context()}
	value.child_space-=1; _reserved_children-=1
	_children[_child_serial]={"generation":int(command.generation),"sequence":sequence,"release_id":release_id,
		"request":made.request,"ticket":ticket,"source":entry.source,"resource_lease":entry.get("resource_lease")}
	_stats.peak_children=maxi(int(_stats.peak_children),_children.size())

func _dispatch_one_child() -> void:
	var selected:=0; var generation:=9223372036854775807
	# Ordered root-owned work: lower generation first, stable creation identity
	# within a layer. No handler recursively calls Root during fact dispatch.
	for key: int in _children:
		if int(_children[key].generation)<generation:
			selected=key; generation=int(_children[key].generation)
	var work: Dictionary=_children[selected]; _children.erase(selected)
	var sequence:=int(work.sequence)
	if not _reservations.has(sequence): return
	var value: Dictionary=_reservations[sequence]
	value.branches[work.release_id].stage="available"
	var epoch:=_delivery_generation
	var source: Node2D=work.source.resolve(false) as Node2D if work.source!=null else null
	var result: Dictionary=_child_executor.call(work.request,work.ticket,value.bindings,source,work.resource_lease)
	if epoch!=_delivery_generation or not _reservations.has(sequence): return
	if not result.success: _error("feature_child_delivery:"+str(result.get("reason","unknown")))
	else: _stats.child_actions+=1
	if value.branches.has(work.release_id) and value.branches[work.release_id].stage=="available":
		value.branches.erase(work.release_id); _retire_chain_if_terminal(sequence)

func clear() -> void:
	_delivery_generation += 1
	# The in-flight pump alone closes its consumer/budget scope. Clearing work
	# cannot reopen this instance to a nested pump before that outer return.
	# Stop all logic handles, including cues with declared missing visuals.
	# Count cancellation before draining so every started state has a terminal
	# outcome; no target or presentation mutation survives an owner change.
	_stats.invalidated += _states.size()
	for handle: String in _states.keys(): _stop(handle)
	if _presentation != null: _presentation.clear()
	_states.clear(); _states_per_target.clear(); _receipts.clear(); _batches.clear()
	_reservations.clear(); _reserved_facts = 0; _reserved_states = 0; _reserved_receipts = 0
	_children.clear(); _reserved_children=0
	_heap.clear(); _batch_head = 0; _batch_tail = 0; _pending = 0
	if not _category.is_empty(): Budget.mark_pending(_category,false)

func _error(reason: String) -> void:
	if reason not in errors: errors.append(reason)
