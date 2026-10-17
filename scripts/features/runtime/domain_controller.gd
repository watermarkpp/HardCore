extends RefCounted

## Original GameRoot feature batch/child entries with explicit S dependencies.
## The one canonical SkillRuntimeRouter and the same synchronous HP port stay
## authoritative; this class neither plans twice nor queues damage for later.
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const Skills := preload("res://scripts/skills/skill_data_loader.gd")
const Child := preload("res://scripts/features/contracts/child_action_lease.gd")
const Ticket := preload("res://scripts/features/contracts/effect_reservation.gd")
var _thread := OS.get_thread_caller_id()
var _owner: WeakRef
var _profile: RefCounted
var _world: RefCounted
var _clock: RefCounted
var runtime: RefCounted
var combat: RefCounted
var presentation: RefCounted
func _init(owner: RefCounted, profile: RefCounted, world: RefCounted, clock: RefCounted, effect_runtime: RefCounted, combat_port: RefCounted, cues: RefCounted) -> void:
	_owner = weakref(owner)
	_profile = profile
	_world = world
	_clock = clock
	runtime = effect_runtime
	combat = combat_port
	presentation = cues
func _owned() -> void: assert(OS.get_thread_caller_id() == _thread)
func _fault(code: String) -> void: _owner.get_ref().call("fault",code,{})

func begin_batch(skill_id: String, release_id: String, configuration: RefCounted = null) -> RefCounted:
	_owned()
	var bindings: Array = configuration.event_bindings_for(skill_id) if configuration != null else _profile.feature_bundle().get("event_index",{}).get("damage_committed:"+Skills.entity_skill_id(skill_id),[])
	if bindings.is_empty(): return null # Original explicit not-applicable path.
	var entity_id := Skills.entity_skill_id(skill_id)
	var reservation: RefCounted = configuration.effect_reservation() if configuration != null else null
	if configuration != null and reservation == null:
		_fault("feature_producer_reservation_missing")
		return null
	if configuration == null and runtime.require_reservations:
		_fault("feature_unreserved_producer")
		return null
	var resources: RefCounted = configuration.resource_lease() if configuration != null else _owner.get_ref().call("feature_action_resource_lease")
	var created := Batch.create(_world,release_id,entity_id,bindings,{"profile_id":_profile.active_profile_id},_clock.simulation_usec(),reservation,resources,
		reservation.chain_context(release_id) if reservation != null else {})
	if not bool(created.success):
		_fault("feature_damage_batch_rejected:"+str(created.reason))
		return null
	var batch: RefCounted = created.batch
	if not batch.begin_base_scope():
		_fault("feature_scope_rejected")
		return null
	return batch

func finish_batch(batch: RefCounted) -> Dictionary:
	_owned()
	if batch == null: return {"success":true,"outcome":"not_applicable","reason":""}
	if not batch.finish_base_scope() or not batch.errors.is_empty():
		batch.finish_production()
		_fault("feature_batch_rejected")
		return {"success":false,"outcome":"rejected","reason":"feature_batch_rejected"}
	var ticket: RefCounted = batch.reservation()
	if runtime == null or (ticket != null and not ticket.batch_owner_is_current()):
		batch.finish_production()
		return {"success":false,"outcome":"owner_retired","reason":"feature_batch_owner_retired"}
	if batch.pending_fact_count() == 0:
		batch.finish_production()
		return {"success":true,"outcome":"empty","reason":""}
	var transferred: bool = runtime.submit_batch(batch)
	batch.finish_production()
	if not transferred: _fault("feature_batch_submission_rejected")
	return {"success":transferred,"outcome":"transferred" if transferred else "rejected","reason":"" if transferred else "feature_batch_submission_rejected"}

func execute_child_action(request: Dictionary, ticket: RefCounted, bindings: Array, source: Object, resources: RefCounted) -> Dictionary:
	_owned()
	var child: RefCounted = Child.from_request(request)
	if child == null or ticket == null or ticket.get_script() != Ticket or runtime == null or not ticket.belongs_to(runtime) or not ticket.authorizes_child_request(request):
		return {"success":false,"reason":"child_owner_rejected"}
	var release_id: String = ticket.branch()
	var lineage: Dictionary = ticket.chain_context(release_id)
	if lineage.is_empty() or lineage != child.chain_context(): return {"success":false,"reason":"child_lineage_rejected"}
	var context: Variant = _owner.get_ref().call("feature_child_plan_context",release_id)
	if not context is Dictionary: return {"success":false,"reason":"child_context_rejected"}
	# Same source Router, lease-owned center/radius, projections and lineage.
	var plan: Dictionary = Router.build_canonical_plan(request,context)
	if not bool(plan.rejection.accepted): return {"success":false,"reason":plan.rejection.reason}
	var query: Variant = _owner.get_ref().call("feature_child_query_actor_ids",plan)
	if not query is Dictionary or query.get("success") != true or not query.get("actor_ids") is Array:
		return {"success":false,"reason":"child_query_rejected"}
	var targets: Array[Object] = []
	var previous := 0
	for id: Variant in query.actor_ids:
		# Exactly the old insertion-by-instance-id ordering. A missing service or
		# corrupted result cannot turn into a successful empty child release.
		if not id is int or id <= previous: return {"success":false,"reason":"child_query_order_rejected"}
		previous = id
		var record: Object = _world.actor_registry().resolve_runtime_actor(id)
		if record == null or record.kind() != &"enemy": return {"success":false,"reason":"child_query_actor_rejected"}
		if record.is_inside_world() and not record.is_queued_for_retirement() and record.model().current_hp > 0:
			targets.append(record)
	var made := Batch.create(_world,release_id,plan.skill_id,bindings,plan.historical_credit,_clock.simulation_usec(),ticket,resources,plan.chain_context,"child",str(plan.chain_context.root_skill_id))
	if not made.success: return {"success":false,"reason":made.reason}
	var batch: RefCounted = made.batch
	if not batch.begin_base_scope():
		batch.finish_production()
		return {"success":false,"reason":"child_scope_rejected"}
	var rng := RandomNumberGenerator.new()
	rng.seed = int(request.seed)
	var succeeded := true
	for enemy: Object in targets:
		if not is_instance_valid(enemy) or enemy.model().current_hp <= 0 or enemy.is_queued_for_retirement(): continue
		var hit: Dictionary = combat.apply_feature_child_damage(enemy,int(plan.gameplay_actions[0].raw_power),source,rng,plan.historical_credit,batch)
		if not hit.success: succeeded = false
	var transfer := finish_batch(batch)
	var delivered: bool = succeeded and batch.errors.is_empty() and bool(transfer.success)
	return {"success":delivered,"reason":"" if delivered else (str(transfer.reason) if not transfer.success else "child_commit_rejected"),"batch_outcome":transfer.outcome}

func close() -> bool:
	_owned()
	runtime.clear()
	return presentation.flush() and presentation.pending_count() == 0
