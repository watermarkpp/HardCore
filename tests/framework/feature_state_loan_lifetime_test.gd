extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Player := preload("res://scripts/player.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Presentation := preload("res://scripts/features/presentation/presentation_port.gd")
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var errors: Array[String] = []
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted
var combat: Node
var source_a: PlayerCharacter
var source_b: PlayerCharacter
var receivers: Array[EnemyActor] = []
var bindings: Array = []
var child_deliveries := 0

class ObservedEnemy extends Enemy:
	var credits: Array[Dictionary] = []
	func take_feature_periodic_damage(amount: int, attacker: Node2D, credit: Dictionary, receipt: Dictionary) -> void:
		credits.append(credit.duplicate(true))
		super.take_feature_periodic_damage(amount,attacker,credit,receipt)

class ObservedPresentation extends Presentation:
	var retire_on_stop := false
	var retired_in_stop := false
	var runtime_owner: RefCounted
	func stop(handle: String) -> void:
		super.stop(handle)
		if retire_on_stop and not retired_in_stop:
			retired_in_stop=true
			runtime_owner.clear()

func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)

func _ready() -> void: _run.call_deferred()
func _ground_to_screen(value: Vector2) -> Vector2: return value*10.0
func _screen_to_ground(value: Vector2) -> Vector2: return value/10.0

func _actor(point: Vector2,hp: int) -> EnemyActor:
	var enemy := ObservedEnemy.new()
	enemy.setup(GameData.get_monster_by_id(19),null); add_child(enemy)
	enemy.set_physics_process(false)
	enemy.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
	enemy.set_combat_position(_ground_to_screen(point),&"state_loan_unit_position")
	enemy.max_hp=5000; enemy.current_hp=hp
	enemy.direct_spell_anti_magic_points=0
	enemy.direct_spell_magic_defense_min=0; enemy.direct_spell_magic_defense_max=0
	enemy.direct_spell_stats_valid=true
	return enemy

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id="state-loan-lifetime"
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/state_loan_lifetime_registry.json"),
		"formal registry accepts only the already-supported direct/child test module")
	print("STATE_LOAN_CATALOG ",JSON.stringify(ContentLayers.feature_load_errors))
	if not errors.is_empty(): _finish(); return
	check(ContentLayers.set_feature_module_enabled("hc.validation.state_loan_lifetime",true),"test module is explicitly enabled")
	bindings=PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size()==2,"one persistent and one finite child subscription use formal bindings")
	world=World.new(); world.configure(self,PlayerState)
	clock=Clock.new(); clock.configure(self)
	combat=Combat.new(); add_child(combat)
	source_a=Player.new(); add_child(source_a); source_a.set_physics_process(false)
	source_b=Player.new(); add_child(source_b); source_b.set_physics_process(false)
	check(source_a.begin_combat_transition("unit:source:A") and source_a.finish_combat_transition("unit:source:A")
		and source_b.begin_combat_transition("unit:source:B") and source_b.finish_combat_transition("unit:source:B"),
		"both actual Player sources enter valid lifetimes through their production transition authority")
	var view:=ObservedPresentation.new(); view.configure(world,true)
	runtime=Runtime.new()
	check(runtime.configure(world,clock,combat,view) and runtime.configure_child_executor(_execute_unit_child),
		"unit owner supplies the actual mapped HP port and one explicit child consumer")
	var large: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,85,"loans:large",85)
	print("STATE_LOAN_85_ADMISSION ",runtime.last_admission_reason)
	check(large!=null,"85 receiver finite chain admits resident states rather than reserving every historical state creation")
	if large!=null:
		check(runtime.reservation_snapshot().states==85,"resident state promise for one persistent binding is85")
		large.close()
	check(runtime.reservation_snapshot().actions==0,"unused large admission cancels before HP")
	# A bounded runtime/HP unit: there are exactly two legal receiver allowances.
	# It isolates storage/life handoff; it does not replace Root's production planner.
	receivers=[_actor(Vector2(1,0),1000),_actor(Vector2.ZERO,1)]
	var first: RefCounted=_submit("loans:life",[10,1],source_a,"A")
	check(first!=null,"life probe has its own accepted root")
	if first==null: _finish(); return
	# Exactly two facts are observed before the already queued child may run.
	runtime._dispatch_one_fact(); runtime._dispatch_one_fact()
	check(runtime.active_count()==1 and runtime.child_count()==1,"live old state and sealed fatal fact retain the same root before child consumption")
	check(runtime.reservation_snapshot().states==1,"one origin state spends one of the two resident loans")
	var old_ref: RefCounted=preload("res://scripts/features/contracts/actor_ref.gd").capture(world,receivers[0])
	receivers[0].take_damage(receivers[0].current_hp,source_b,{"source_class":"direct","damage_channel":"magic_defense"})
	check(receivers[0].collision_layer==0 and old_ref.resolve()==null,"an independent real death invalidates the old state and immediately removes collision")
	for enemy: EnemyActor in receivers: enemy.queue_free()
	receivers=[_actor(Vector2(1,0),1000),_actor(Vector2.ZERO,1000)]
	check(old_ref.resolve(false)==null,"queued old life has no mutation qualification while both replacement allowances are materialized")
	await _pump()
	check(child_deliveries==1 and receivers[0].current_hp==999 and receivers[1].current_hp==999,
		"the retained committed fatal fact still performs its actual child HP exactly once")
	check(runtime.active_count()==2 and runtime.heap_count()==2 and view.node_count()==2,
		"replacement consumes returned origin loans without retaining the invalid old-life state")
	check(runtime.reservation_snapshot().states==0,"the two live replacement states hold both origin loans")
	check(runtime.metrics().invalidated==1 and runtime.errors.is_empty(),"loan reclamation gives the old life one explicit terminal outcome")
	for step in range(4): clock.advance_simulation(1.0); await _pump()
	check(not runtime.has_work() and runtime.heap_count()==0 and _promises_empty(),"all child/state/receipt/loan owners reach the original complete terminal boundary")
	for enemy: EnemyActor in receivers: enemy.queue_free()
	await get_tree().process_frame
	# Multiple accepted roots can refresh one state, while only its origin lends
	# the storage. No older root, source or historical credit is discarded.
	receivers=[_actor(Vector2(1,0),5000),_actor(Vector2.ZERO,5000)]
	check(_submit("loans:refresh:A",[10,10],source_a,"A")!=null,"A accepts two initial states")
	await _pump()
	clock.advance_simulation(0.5)
	check(_submit("loans:refresh:B",[1],source_b,"B")!=null,"B accepts a weaker refresh grant")
	await _pump()
	clock.advance_simulation(0.5)
	check(_submit("loans:refresh:C",[20],source_b,"C")!=null,"C accepts a stronger refresh grant")
	await _pump()
	var selected: Dictionary={}
	for state: Dictionary in runtime._states.values():
		if state.target.resolve()==receivers[0]: selected=state
	check(not selected.is_empty() and selected.raw_per_tick==20 and selected.chain_owners.size()==3,
		"weak and strong refresh retain all three accepted roots without multiplying the state node")
	# 2026-10-05 user ruling: the last accepted same-species application owns
	# the head — its source and historical credit replace the prior roots —
	# while all three accepted roots stay chained to the one state node.
	check(not selected.is_empty() and selected.source!=null and selected.command.historical_credit.get("marker")=="C"
		and selected.source.identity().runtime_id==source_b.get_instance_id(),
		"the last accepted application owns the state: source and historical credit replace prior roots")
	check(runtime.active_count()==2 and runtime.reservation_snapshot().actions==3 and runtime.reservation_snapshot().states==4,
		"shared state ownership and two spare refresh-root loan pools remain separate")
	var before: int=receivers[0].current_hp
	source_a.queue_free(); await get_tree().process_frame
	check(ContentLayers.set_feature_module_enabled("hc.validation.state_loan_lifetime",false),"accepted states survive source withdrawal")
	clock.advance_simulation(1.0); await _pump()
	check(receivers[0].current_hp==before-20 and receivers[0].credits.back().get("marker")=="C",
		"later real periodic HP carries the last accepted source and credit after another root's destruction")
	clock.advance_simulation(3.0); await _pump()
	check(not runtime.has_work() and _promises_empty() and runtime.active_count()==0 and view.node_count()==0,
		"refresh origin loans and every retained root retire only after the shared state ends")
	check(runtime.errors.is_empty(),"unit loan/life/refresh paths complete without hidden capacity errors")
	for enemy: EnemyActor in receivers: enemy.queue_free()
	await get_tree().process_frame
	# The supported presentation port may synchronously clear during retirement.
	# Reclaimed storage does not grant the old command a replacement owner.
	check(ContentLayers.set_feature_module_enabled("hc.validation.state_loan_lifetime",true),"clear probe explicitly republishes its own test source")
	receivers=[_actor(Vector2(1,0),1000),_actor(Vector2.ZERO,1)]
	check(_submit("loans:clear",[10,1],source_b,"B")!=null,"clear probe accepts its own finite root")
	runtime._dispatch_one_fact(); runtime._dispatch_one_fact()
	receivers[0].take_damage(receivers[0].current_hp,source_b,{"source_class":"direct","damage_channel":"magic_defense"})
	for enemy: EnemyActor in receivers: enemy.queue_free()
	receivers=[_actor(Vector2(1,0),1000),_actor(Vector2.ZERO,1000)]
	view.runtime_owner=runtime; view.retire_on_stop=true
	await _pump()
	check(view.retired_in_stop,"loan reclamation reaches a real stop-port retirement callback")
	check(receivers[0].current_hp==999 and receivers[1].current_hp==999,"retirement cannot roll back the child HP already committed")
	check(not runtime.has_work() and runtime.active_count()==0 and runtime.heap_count()==0
		and view.node_count()==0 and _promises_empty(),"clear in loan return leaves no old or replacement scheduling/storage owner")
	check(not runtime._pumping and runtime.errors.is_empty(),"original public consumer closes after loan-return retirement without resurrecting old work")
	runtime.clear()
	for enemy: EnemyActor in receivers: enemy.queue_free()
	source_b.queue_free(); combat.queue_free(); await get_tree().process_frame
	check(ContentLayers.reload_feature_catalog(),"retired unit restores the formal default registry")
	_finish()

func _submit(release: String,amounts: Array,source: Node2D,marker: String) -> RefCounted:
	var ticket: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,2,release,2)
	if ticket==null: return null
	var made:=Batch.create(world,release,"hc.skill.wizard.ice_storm",bindings,
		{"profile_id":PlayerState.active_profile_id,"marker":marker},clock.simulation_usec(),ticket,null,ticket.chain_context(release))
	if not made.success: ticket.close(); return null
	var batch: RefCounted=made.batch; batch.begin_base_scope()
	for index in range(amounts.size()):
		receivers[index].take_damage(int(amounts[index]),source,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	if not batch.finish_base_scope() or not runtime.submit_batch(batch): batch.finish_production(); ticket.close(); return null
	ticket.close(); return ticket

func _execute_unit_child(request: Dictionary,ticket: RefCounted,frozen_bindings: Array,source: Node2D,resources: RefCounted) -> Dictionary:
	# This controlled unit consumer uses the real owned batch and Combat HP.
	# Real Root/planner/release geometry integration is covered separately.
	if not ticket.authorizes_child_request(request): return {"success":false,"reason":"unit_child_owner"}
	var lease: RefCounted=request.child_action_lease
	var command: Dictionary=lease.command()
	var lineage: Dictionary=lease.chain_context()
	var made:=Batch.create(world,lineage.release_id,"hc.child.death_burst.v1",frozen_bindings,
		command.historical_credit,clock.simulation_usec(),ticket,resources,lineage,"child",command.root_skill_id)
	if not made.success: return {"success":false,"reason":made.reason}
	var batch: RefCounted=made.batch; batch.begin_base_scope()
	var rng:=RandomNumberGenerator.new(); rng.seed=731
	for enemy: EnemyActor in receivers:
		var result: Dictionary=combat.apply_feature_child_damage(enemy,command.raw_damage,source,rng,command.historical_credit,batch)
		if not result.success: batch.finish_base_scope(); batch.finish_production(); return result
	var sealed: bool=batch.finish_base_scope()
	var submitted: bool=sealed and runtime.submit_batch(batch)
	if not submitted: batch.finish_production()
	child_deliveries+=1
	return {"success":submitted,"reason":"" if submitted else "unit_child_transfer"}

func _promises_empty() -> bool:
	for count: int in runtime.reservation_snapshot().values():
		if count!=0: return false
	return true

func _pump() -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded public consumer completes")

func _finish() -> void:
	var written:=proof.write_receipt("feature_state_loan_lifetime_test",proof.records.size(),errors.size())
	print("FEATURE_STATE_LOAN_LIFETIME_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
