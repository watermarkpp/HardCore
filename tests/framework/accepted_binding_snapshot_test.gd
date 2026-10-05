extends "res://tests/framework/periodic_refresh_horizon_test.gd"

const Reservation := preload("res://scripts/features/contracts/effect_reservation.gd")

class ClaimProbe extends "res://scripts/features/runtime/effect_runtime.gd":
	var claim_calls := 0
	func _claim_reservation(sequence: int, identity: Dictionary, release_id: String,
		skill_id: String, accepted_bindings: Array, branch := "", ticket_id := 0) -> Dictionary:
		claim_calls += 1
		return super._claim_reservation(sequence,identity,release_id,skill_id,accepted_bindings,branch,ticket_id)

class FakeIssuer extends RefCounted:
	var lineage: Dictionary = {}
	var claim_calls := 0
	func _reservation_binding_snapshot_matches(_sequence: int, _identity: Dictionary, _release: String,
		_skill: String, _bindings: Array, _branch: String, _ticket: int) -> bool: return true
	func _reservation_chain_context(_sequence: int, _release: String, _branch: String) -> Dictionary: return lineage
	func _reservation_source_class(_sequence: int, _release: String, _branch: String) -> String: return "periodic"
	func _claim_reservation(_sequence: int, _identity: Dictionary, _release: String,
		_skill: String, _bindings: Array, _branch: String, _ticket: int) -> Dictionary:
		claim_calls+=1
		return {"success":true,"maximum_facts":1}
	func _close_reservation_batch(_sequence: int, _branch: String) -> void: pass

func _query(ticket: RefCounted, identity: Dictionary, release: String, skill: String,
	accepted_bindings: Array) -> bool:
	return bool(ticket.call("matches_accepted_bindings",identity,release,skill,accepted_bindings))

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id="accepted-binding-snapshot"
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/periodic_chain_registry.json")
		and ContentLayers.set_feature_module_enabled("hc.validation.periodic_chain",true),"the formal compiler supplies both finite chain bindings")
	bindings=PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size()==2,"this proof starts from a compiled source, not an invented binding")
	world=World.new(); world.configure(self,PlayerState); clock=Clock.new(); clock.configure(self)
	var combat:=Combat.new(); add_child(combat)
	source_a=Player.new(); add_child(source_a); source_a.set_physics_process(false)
	check(source_a.begin_combat_transition("snapshot") and source_a.finish_combat_transition("snapshot"),"the actual player source has a valid life")
	target=ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
	target.set_combat_position(_ground_to_screen(Vector2(1,0)),&"accepted_binding_snapshot_position")
	target.max_hp=5000; target.current_hp=5000
	target.direct_spell_anti_magic_points=0; target.direct_spell_magic_defense_min=0
	target.direct_spell_magic_defense_max=0; target.direct_spell_stats_valid=true
	runtime=ClaimProbe.new()
	check(runtime.configure(world,clock,combat) and runtime.configure_child_executor(_unexpected_child),"one real runtime owns every admission and claim")
	var skill: String="hc.skill.wizard.ice_storm"
	var release: String="binding-snapshot:root"
	var ordinary_bindings: Array=[]
	for binding: Dictionary in bindings:
		if binding.definition.handler_id=="hc.ignite.v1": ordinary_bindings.append(binding)
	for selected: Array in [bindings,ordinary_bindings]:
		_test_unissued_cancel(skill,selected,false)
		_test_unissued_cancel(skill,selected,true)
	var claims_before_original_case: int=runtime.claim_calls
	var ticket: RefCounted=runtime.reserve_action(skill,bindings,1,release,1)
	check(ticket!=null,"the root receives a nonempty capacity ticket before HP")
	if ticket==null:
		_cleanup(combat); return
	check(ticket.has_method("matches_accepted_bindings"),"a runtime-issued ticket can inspect its accepted binding snapshot without consuming release")
	if not ticket.has_method("matches_accepted_bindings"):
		_cleanup(combat); return
	var before: Dictionary=runtime.reservation_snapshot()
	var metrics: Dictionary=runtime.metrics()
	var old_mp: int=source_a.current_mp
	check(_query(ticket,world.capture_world(),release,skill,bindings)
		and _query(ticket,world.capture_world(),release,skill,bindings.duplicate(true)),"repeated exact snapshot inspection accepts independently copied plain bindings")
	var other_world: Dictionary=world.capture_world().duplicate(true); other_world.world_epoch+=1
	check(not _query(ticket,other_world,release,skill,bindings),"a different world cannot borrow the proof")
	check(not _query(ticket,world.capture_world(),release+":old",skill,bindings),"an old or different release cannot borrow the proof")
	check(not _query(ticket,world.capture_world(),release,"hc.skill.warrior.fire_sword",bindings),"a different registered skill cannot borrow the proof")
	var changed: Array=bindings.duplicate(true); changed[0].definition.config.fraction=0.5
	check(Batch.validate_bindings(skill,changed),"the changed numeric binding is independently valid, so rejection requires exact accepted identity")
	check(not _query(ticket,world.capture_world(),release,skill,changed),"independently valid changed numbers still cannot reuse the old snapshot")
	var malformed: Array=bindings.duplicate(true); malformed[0].handle="altered-handle"
	check(not _query(ticket,world.capture_world(),release,skill,malformed),"a changed source handle cannot borrow accepted identity")
	var forged: RefCounted=Reservation.create(runtime,ticket.sequence())
	check(not _query(forged,world.capture_world(),release,skill,bindings),"a second object with the same sequence is not the issued ticket")
	check(runtime.reservation_snapshot()==before and runtime.metrics()==metrics and runtime.claim_calls==claims_before_original_case
		and target.current_hp==5000 and source_a.current_mp==old_mp,"all proof queries leave claims, capacity, HP, MP and runtime metrics unchanged")
	var rejected:=Batch.create(world,release,skill,changed,{},0,ticket,null,ticket.chain_context(release))
	check(not rejected.success and ticket.can_begin_release(release),"a changed batch fails without stealing the original legal release")
	var forged_batch:=Batch.create(world,release,skill,bindings,{},0,forged,null,ticket.chain_context(release))
	check(not forged_batch.success and ticket.can_begin_release(release),"a forged object cannot claim the original branch")
	var made:=Batch.create(world,release,skill,bindings,{"profile_id":PlayerState.active_profile_id},0,ticket,null,ticket.chain_context(release))
	check(made.success,"the original callback still claims its complete accepted configuration")
	if not made.success:
		_cleanup(combat); return
	var batch: RefCounted=made.batch
	check(not _query(ticket,world.capture_world(),release,skill,bindings),"a consumed release cannot be certified for another batch")
	forged.close()
	check(batch.begin_base_scope(),"the real batch owns the original HP scope")
	target.take_damage(10,source_a,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	check(batch.finish_base_scope() and runtime.submit_batch(batch),"the unique real HP fact transfers to the original runtime")
	batch.finish_production()
	check(not _query(ticket,world.capture_world(),release,skill,bindings),"a closed action never regains a snapshot proof while accepted state remains")
	await _pump()
	check(runtime.active_count()==1 and target.current_hp==4990,"the accepted root actually starts its real periodic state")
	check(clock.advance_simulation(4.0),"the explicit unit clock reaches all four original deadlines")
	await _pump()
	check(target.periodic_calls==4 and target.periodic_release_ids.size()==4 and target.current_hp==4950,
		"four distinct periodic batches each commit exact real HP once")
	check(runtime.claim_calls-claims_before_original_case==7,"two denied claims, one root claim and four periodic claims retain the original one-shot protocol")
	check(not runtime.has_work() and runtime.errors.is_empty(),"periodic producer, state, receipts and root promises all retire")
	var plain: Array=[]
	for binding: Dictionary in bindings:
		if binding.definition.handler_id=="hc.ignite.v1": plain.append(binding)
	check(plain.size()==1,"the ordinary compatibility case selects the registered non-chain handler explicitly")
	var ordinary: RefCounted=runtime.reserve_action(skill,plain,1,"binding-snapshot:ordinary")
	check(ordinary!=null and not _query(ordinary,world.capture_world(),"binding-snapshot:ordinary",skill,plain),"a non-chain reservation stays on the original full binding validation path")
	var ordinary_batch:=Batch.create(world,"binding-snapshot:ordinary",skill,plain,{},0,ordinary)
	check(ordinary_batch.success,"the ordinary reserved batch remains compatible")
	if ordinary_batch.success: ordinary_batch.batch.finish_production()
	var bad: Array=bindings.duplicate(true)
	for binding: Dictionary in bad:
		if binding.definition.handler_id=="hc.ignite.v1": binding.definition.config.max_ticks=0
	check(not Batch.validate_bindings(skill,bad),"the spoof case is rejected by the original full configuration validator")
	var spoofer:=FakeIssuer.new()
	spoofer.lineage={"contract_id":"hardcore.combat.chain_context.v1","root_release_id":"spoof:root",
		"release_id":"spoof:tick","parent_release_id":"spoof:root","root_skill_id":skill,"generation":0,"maximum_generation":1}
	var spoof_ticket: RefCounted=Reservation.create_child(spoofer,1,"spoof:tick")
	check(not _query(spoof_ticket,world.capture_world(),"spoof:tick",skill,bad),"an unrelated object implementing the same method names cannot issue a binding proof")
	var spoof_batch:=Batch.create(world,"spoof:tick",skill,bad,{},0,spoof_ticket,null,spoofer.lineage,"periodic")
	check(not spoof_batch.success and spoofer.claim_calls==0,"a non-runtime issuer cannot skip full validation or consume any fake release")
	if spoof_batch.success: spoof_batch.batch.finish_production()
	var stale: RefCounted=runtime.reserve_action(skill,bindings,1,"binding-snapshot:stale",1)
	check(stale!=null,"a final real ticket exists before world retirement")
	before=runtime.reservation_snapshot(); var claims: int=runtime.claim_calls
	_zone_generation+=1
	check(not _query(stale,world.capture_world(),"binding-snapshot:stale",skill,bindings)
		and runtime.reservation_snapshot()==before and runtime.claim_calls==claims,"stale-world proof inspection refuses without mutating or consuming the old producer")
	_cleanup(combat)

func _test_unissued_cancel(skill: String, selected: Array, by_destructor: bool) -> void:
	var release := "binding-cancel:%d:%s" % [selected.size(), "destructor" if by_destructor else "close"]
	var baseline: Dictionary=runtime.reservation_snapshot()
	var hp: int=target.current_hp
	var mp: int=source_a.current_mp
	var issued: RefCounted=runtime.reserve_action(skill,selected,1,release,1)
	check(issued!=null,"cancellation case has one real issued producer " + release)
	if issued==null: return
	var reserved: Dictionary=runtime.reservation_snapshot()
	var unissued: RefCounted=Reservation.create(runtime,issued.sequence())
	check(not _query(unissued,world.capture_world(),release,skill,selected),
		"unissued same-sequence object cannot certify the accepted producer " + release)
	check(not unissued.claim(world.capture_world(),release,skill,selected).success,
		"unissued same-sequence object cannot consume any original producer " + release)
	if not by_destructor: unissued.close()
	unissued=null
	check(runtime.reservation_snapshot()==reserved and issued.can_begin_release(release),
		"unissued close or last-reference deletion preserves the exact original capacity and release " + release)
	var made:=Batch.create(world,release,skill,selected,{},0,issued,null,issued.chain_context(release))
	check(made.success,"original producer still claims exactly once after unissued retirement " + release)
	check(made.success and not issued.claim(world.capture_world(),release,skill,selected).success,
		"the genuine producer cannot claim a second batch " + release)
	if made.success:
		made.batch.finish_production()
	issued=null
	check(runtime.reservation_snapshot()==baseline and target.current_hp==hp and source_a.current_mp==mp,
		"completed qualification probe restores capacity without HP or MP mutation " + release)
	for abandoned_by_destructor in [false,true]:
		var cancellable: RefCounted=runtime.reserve_action(skill,selected,1,release+":legitimate:%s" % abandoned_by_destructor,1)
		check(cancellable!=null,"legitimate unused action receives its own nonempty reservation " + release)
		if cancellable==null: return
		if not abandoned_by_destructor: cancellable.close()
		cancellable=null
		check(runtime.reservation_snapshot()==baseline,
			"issued close and issued destructor still release only their own unused promise " + release)

func _cleanup(combat: Node) -> void:
	runtime.clear()
	var empty:=true
	for count: int in runtime.reservation_snapshot().values(): empty=empty and count==0
	check(empty and not runtime.has_work(),"the test-owned world releases all remaining capacity")
	check(ContentLayers.reload_feature_catalog(),"the default catalog is restored after explicit world retirement")
	target.queue_free(); source_a.queue_free(); combat.queue_free()
	_finish_snapshot()

func _finish_snapshot() -> void:
	var written:=proof.write_receipt("accepted_binding_snapshot_test",proof.records.size(),errors.size())
	print("ACCEPTED_BINDING_SNAPSHOT_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
