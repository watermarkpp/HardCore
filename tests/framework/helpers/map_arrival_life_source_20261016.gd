extends "res://tests/framework/helpers/player_birth_life_source_20261015.gd"

## Real original Player transitions, Registry/Handle, temporal scope and Native
## body. The value-schema checks below grant no Core/Native map CAS authority.
const Arrival := preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd")
const TemporalScope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")
const Projectile := preload("res://scripts/gameplay/world/world_skill_projectile_model.gd")
var _arrival_scope: RefCounted

func _init(host: Object, boot: Dictionary) -> void:
	super(host,boot)

func _schema_checks(identity: Dictionary, before: Dictionary, after: Dictionary) -> void:
	# Only the exact plain-value schema is under test here. Empty receipt
	# dictionaries deliberately cannot pass actual Core/Native provenance.
	var transaction := {"contract_id":Arrival.CONTRACT,"before_world":before,"after_world":after,
		"source_root_id":get_instance_id(),"world_core_id":get_instance_id(),"registry_id":_registry.get_instance_id(),
		"owner_session_id":1,"player_runtime_id":_record.get_instance_id(),"player_identity":identity,
		"coordinator_generation":1,"transition_id":"schema-only","loading_scope":{},"finish_identity":{},"finish_reply":{}}
	_check(Arrival.accepts(transaction),"v2 exact14 value schema accepts the separately captured actual positive Player identity")
	var changed: Dictionary = transaction.duplicate(true); changed.contract_id = "hardcore.source.map_arrival.v1"
	_check(not Arrival.accepts(changed),"v1 identifier cannot authorize the new14-field value contract")
	changed = transaction.duplicate(true); changed.erase("player_identity")
	_check(not Arrival.accepts(changed),"v2 rejects a13-field transaction missing the actual Player identity")
	changed = transaction.duplicate(true); changed.extra = true
	_check(not Arrival.accepts(changed),"v2 rejects unknown transaction fields")
	changed = transaction.duplicate(true); changed.player_identity.life_generation = 0
	_check(not Arrival.accepts(changed),"v2 value schema rejects a life-zero after-world combat identity")
	changed = transaction.duplicate(true); changed.player_identity.world = before
	_check(not Arrival.accepts(changed),"v2 Player identity must address the transaction exact after-world")
	changed = transaction.duplicate(true); changed.player_identity.runtime_id += 1
	_check(not Arrival.accepts(changed),"v2 Player identity cannot substitute another runtime object")
	changed = transaction.duplicate(true); changed.player_identity.extra = true
	_check(not Arrival.accepts(changed),"v2 Player identity is exact3 fields")

func _exercise_arrival() -> void:
	var id: int = _record.get_instance_id()
	var before: Dictionary = _registry.capture_world()
	var first: Dictionary = before.duplicate(true); first.runtime_map_id = 913203; first.world_epoch += 1
	_arrival_scope = TemporalScope.new()
	_check(_arrival_scope.configure_source({"runtime_present":true,"life_generation":1,"inside_world":true,
		"queued_for_retirement":false,"parent_scope_id":before.world_runtime_id,"can_process":true,
		"process_processing_enabled":true,"physics_processing_enabled":true,"ordinary_p_enabled":true,
		"raw_h_enabled":true,"physics_priority":0,"process_priority":0,"process_mode":0}),"real attached temporal scope has its separate original Node incarnation life")
	_check(_record.bind_original_temporal_scope(_arrival_scope),"actual canonical Player Handle binds that same temporal scope")
	var scope_before: Dictionary = _arrival_scope.snapshot()
	var hp_before: int = _model.current_hp
	var body_before: RID = _motion.get_body_rid()
	var leases_before: int = _registry.remaining_lease_count()
	_check(_registry.capture_attached_player_map_arrival_identity(id,before,first).is_empty(),"life-zero premap display cannot be frozen into an arrival combat identity")
	_check(not _registry.commit_attached_player_map_arrival(id,before,first,{"world":first,"runtime_id":id,"life_generation":1}) and _registry.capture_world() == before,"literal life1 cannot substitute for actual Player life before original transition")
	_check(_model.begin_combat_transition("arrival-first-map"),"real original transition advances the one actual Player life")
	var identity: Dictionary = _registry.capture_attached_player_map_arrival_identity(id,before,first)
	_check(not identity.is_empty() and identity.life_generation == _model.current_life() and identity.life_generation == 1 and identity.is_read_only(),"canonical Registry freezes the actual positive original life with the exact after-world")
	if identity.is_empty(): return
	_schema_checks(identity,before,first)
	var changed: Dictionary = identity.duplicate(true); changed.life_generation += 1
	_check(not _registry.commit_attached_player_map_arrival(id,before,first,changed) and _registry.capture_world() == before,"mismatched positive life fails before any Registry or Handle world mutation")
	var skipped: Dictionary = first.duplicate(true); skipped.world_epoch += 1
	_check(_registry.capture_attached_player_map_arrival_identity(id,before,skipped).is_empty(),"real attached identity capture rejects skipped world epochs")
	var foreign: Dictionary = first.duplicate(true); foreign.profile_id = "another_profile"
	_check(_registry.capture_attached_player_map_arrival_identity(id,before,foreign).is_empty(),"actual Player identity cannot transfer to another Profile")
	var first_committed: bool = _registry.commit_attached_player_map_arrival(id,before,first,identity)
	_check(first_committed,"real attached Player crosses first arrival only with its frozen actual life")
	if not first_committed: return
	_world_context = first
	_check(_registry.capture_world() == first and _record.identity() == identity and _record.original_world_context() == first,"Registry and canonical Handle commit exact after-world and captured identity together")
	_check(_arrival_scope.snapshot() == scope_before and _model.current_hp == hp_before and _model.current_life() == identity.life_generation and _motion.get_body_rid() == body_before and _registry.remaining_lease_count() == leases_before and _link.resolve_record() == _record,"arrival preserves actual scope HP life Native body and persistent storage leases")
	_check(not _registry.commit_attached_player_map_arrival(id,before,first,identity),"consumed before-world cannot replay Registry mutation")
	_check(_model.finish_combat_transition("arrival-first-map"),"original first transition token completes without new life authority")
	_first_action = ActorRef.capture_domain(_registry,_record)
	_check(_first_action != null and _first_action.resolve_record(false) == _record,"actual first-map ActorRef captures the committed positive identity")
	_check(_model.begin_combat_transition("arrival-next-map"),"next original map transition advances the same actual Player life")
	var second: Dictionary = first.duplicate(true); second.runtime_map_id = 910001; second.world_epoch += 1
	var second_identity: Dictionary = _registry.capture_attached_player_map_arrival_identity(id,first,second)
	_check(not second_identity.is_empty() and second_identity.life_generation == 2 and _first_action != null and _first_action.resolve_record(false) == null,"arrival captures real life2 while an accepted older life reference becomes stale")
	var projectile := Projectile.new()
	var old: Object = _registry.register_actor(projectile,1,&"projectile",1)
	_check(old != null,"real production projectile enters the old world Registry")
	if old == null: return
	var old_id: int = old.get_instance_id()
	var old_identity: Dictionary = old.identity()
	var old_link: RefCounted = ActorLink.capture(_registry,old)
	var old_action: RefCounted = ActorRef.capture_domain(_registry,old)
	_check(old_link != null and old_action != null,"real old-world ActorLink and ActorRef retain their original canonical storage")
	_check(not _registry.can_commit_attached_player_map_arrival(id,first,second,second_identity),"nonretiring old actor prevents mutation even with exact captured Player life")
	_check(old.queue_retirement(),"old actor enters genuine queued retirement before arrival")
	_record.set_world_membership(false)
	_check(not _registry.commit_attached_player_map_arrival(id,first,second,second_identity),"arrival rejects a detached canonical Player without discarding old debt")
	_record.set_world_membership(true); _record.set_parent_scope_id(first.world_runtime_id)
	_check(_model.finish_combat_transition("arrival-next-map") and _model.begin_combat_transition("arrival-life-changed-before-commit"),"a separate real original transition can invalidate an earlier frozen identity")
	_check(not _registry.commit_attached_player_map_arrival(id,first,second,second_identity) and _registry.capture_world() == first and _record.original_world_context() == first,"stale frozen life2 is rejected after actual life advances; no world mutated")
	var current_identity: Dictionary = _registry.capture_attached_player_map_arrival_identity(id,first,second)
	_check(not current_identity.is_empty() and current_identity.life_generation == _model.current_life() and current_identity.life_generation == 3,"fresh capture reads actual life3 rather than guessing from map epoch")
	var second_scope: Dictionary = _arrival_scope.snapshot()
	_check(_registry.commit_attached_player_map_arrival(id,first,second,current_identity),"next attached arrival accepts queued old actor debt and exact latest real life")
	_world_context = second
	_check(_record.identity() == current_identity and _arrival_scope.snapshot() == second_scope and _model.current_hp == hp_before and _motion.get_body_rid() == body_before,"next arrival retains actual Player scope HP and Native body while committing frozen life")
	_check(old.original_world_context() == first and old.identity() == old_identity and old_link != null and old_link.resolve_record() == old and old.is_queued_for_retirement(),"old actor retains original world identity and real storage debt after current-world CAS")
	_check(old_action != null and old_action.resolve_record(false) == null,"old accepted ActorRef becomes world-stale without erasing retained storage")
	_check(_registry.retire_runtime_actor(old_id) and _registry.remaining_actor_count() == 2,"actual retired old actor storage remains until accepted leases release")
	if old_action != null: old_action.dispose_domain()
	if old_link != null: old_link.dispose()
	_check(_registry.remaining_actor_count() == 1 and _registry.resolve_runtime_actor(old_id) == null,"last original storage lease performs real old-actor destruction")
	_check(_model.finish_combat_transition("arrival-life-changed-before-commit"),"last actual transition token completes at its original boundary")

func on_phase(phase: String, _frame: Dictionary) -> bool:
	if phase == "H_GROUP" and not _done:
		_exercise_arrival()
		_done = true
	if phase != "PUBLISH": return true
	return _host.publish_snapshot({"done":_done,"checks":_checks},[])
