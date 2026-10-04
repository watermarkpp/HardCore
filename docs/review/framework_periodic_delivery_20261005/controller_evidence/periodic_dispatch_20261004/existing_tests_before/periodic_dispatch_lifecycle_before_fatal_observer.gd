extends Node

# Controlled runtime/HP protocol unit. Root/planner/geometry is exercised by
# periodic_child_root_test; this test's child consumer has no live receivers.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Player := preload("res://scripts/player.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
var _zone_generation := 1
var current_map_id := 910004
var proof := Proof.new()
var errors: Array[String] = []
var bindings: Array = []
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted
var combat: Node
var target: EnemyActor
var child_commands: Array[Dictionary] = []
var held_during_stop := false
var nested_calls := 0

class ObservedEnemy extends Enemy:
	var batches: Array[RefCounted] = []
	var credits: Array[Dictionary] = []
	var after_commit := Callable()
	var ordinary_calls := 0
	func take_feature_periodic_damage(amount: int, attacker: Node2D, credit: Dictionary, receipt: Dictionary) -> void:
		ordinary_calls+=1
		super.take_feature_periodic_damage(amount,attacker,credit,receipt)
	func take_feature_periodic_chain_damage(amount: int, attacker: Node2D, credit: Dictionary,
		receipt: Dictionary, batch: RefCounted) -> void:
		batches.append(batch); credits.append(credit.duplicate(true))
		super.take_feature_periodic_chain_damage(amount,attacker,credit,receipt,batch)
		if after_commit.is_valid(): after_commit.call()

func _ready() -> void: _run.call_deferred()
func check(value: bool,label: String) -> void:
	proof.record(value,label)
	if not value: errors.append(label)
func _ground_to_screen(value: Vector2) -> Vector2: return value*10.0
func _screen_to_ground(value: Vector2) -> Vector2: return value/10.0
func _empty_promises() -> bool:
	for value: int in runtime.reservation_snapshot().values():
		if value!=0: return false
	return true
func _pump() -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count()==0 and runtime.child_count()==0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded public protocol consumer completes")

func _empty_child(request: Dictionary,ticket: RefCounted,frozen: Array,source: Node2D,resources: RefCounted) -> Dictionary:
	check(ticket.authorizes_child_request(request),"empty unit child retains its actual request-owner capability")
	check(target.current_hp==0 and not target.can_receive_damage(),"empty unit child has no live receiver after the actual first death")
	var lease: RefCounted=request.child_action_lease
	var chain: Dictionary=lease.chain_context(); var command: Dictionary=lease.command()
	child_commands.append(command)
	var made:=Batch.create(world,chain.release_id,"hc.child.death_burst.v1",frozen,
		command.historical_credit,clock.simulation_usec(),ticket,resources,chain,"child",command.root_skill_id)
	if not made.success: return {"success":false,"reason":made.reason}
	var batch: RefCounted=made.batch
	var sealed: bool=batch.begin_base_scope() and batch.finish_base_scope()
	check(sealed and batch.pending_fact_count()==0,"legitimate empty child closes the real producer without fabricated HP or a queue entry")
	batch.finish_production()
	return {"success":sealed,"reason":""}

func _nested_pump() -> void:
	check(runtime.pump()==0,"HP observer cannot reenter the active consumer or borrow its inline fact")
	nested_calls+=1
func _stop_state() -> void:
	var handle: String=runtime._states.keys()[0]
	runtime._stop(handle)
	held_during_stop=runtime.reservation_snapshot().actions==1 and runtime.active_count()==0
func _change_world() -> void: _zone_generation+=1

func _run() -> void:
	PlayerState.test_mode=true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id="periodic-lifecycle-unit"
	check(ContentLayers.reload_feature_catalog("res://assets/data/features/validation/periodic_chain_registry.json")
		and ContentLayers.set_feature_module_enabled("hc.validation.periodic_chain",true),"explicit default-off periodic module supplies formal immutable bindings")
	bindings=PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size()==2,"protocol unit retains both declared subscriptions")
	if bindings.size()!=2: _finish(); return
	for mode: String in ["baseline","stop_after_fatal","clear_after_hp","world_after_hp","queued_free_after_hp","source_destroyed"]:
		await _case(mode)
	check(ContentLayers.reload_feature_catalog(),"retired unit restores the formal default catalog")
	_finish()

func _case(mode: String) -> void:
	_zone_generation+=1; child_commands.clear(); held_during_stop=false
	world=World.new(); world.configure(self,PlayerState)
	clock=Clock.new(); clock.configure(self)
	combat=Combat.new(); add_child(combat)
	var source:=Player.new(); add_child(source); source.set_physics_process(false)
	check(source.begin_combat_transition(mode) and source.finish_combat_transition(mode),mode+" enters an actual source lifetime")
	target=ObservedEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false)
	target.configure_runtime_map_projection(current_map_id,_ground_to_screen,_screen_to_ground)
	target.set_combat_position(_ground_to_screen(Vector2.ONE),&"periodic_lifecycle_unit_position")
	target.max_hp=5000; target.current_hp=20 if mode=="stop_after_fatal" else 200
	target.direct_spell_anti_magic_points=0
	target.direct_spell_magic_defense_min=0; target.direct_spell_magic_defense_max=0; target.direct_spell_stats_valid=true
	runtime=Runtime.new()
	check(runtime.configure(world,clock,combat) and runtime.configure_child_executor(_empty_child),mode+" configures one real runtime and HP port")
	var root: String="periodic:lifecycle:"+mode
	var ticket: RefCounted=runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,1,root,1)
	check(ticket!=null,mode+" reserves the complete root before its base HP")
	if ticket==null: runtime.clear(); target.queue_free(); source.queue_free(); combat.queue_free(); return
	var made:=Batch.create(world,root,"hc.skill.wizard.ice_storm",bindings,{"profile_id":PlayerState.active_profile_id,"marker":mode},
		clock.simulation_usec(),ticket,null,ticket.chain_context(root))
	check(made.success,mode+" claims the actual accepted direct producer")
	if not made.success: ticket.close(); runtime.clear(); target.queue_free(); source.queue_free(); combat.queue_free(); return
	var base: RefCounted=made.batch; base.begin_base_scope()
	target.take_damage(10,source,{"feature_damage_batch":base,"source_class":"direct","damage_channel":"magic_defense"})
	check(base.finish_base_scope() and runtime.submit_batch(base),mode+" transfers one real base fact")
	ticket.close(); await _pump()
	check(runtime.active_count()==1 and runtime.heap_count()==1,mode+" has one admitted status and no fabricated periodic work")
	if mode=="baseline": target.after_commit=_nested_pump
	elif mode=="stop_after_fatal": target.after_commit=_stop_state
	elif mode=="clear_after_hp": target.after_commit=runtime.clear
	elif mode=="world_after_hp": target.after_commit=_change_world
	elif mode=="queued_free_after_hp": target.after_commit=target.queue_free
	elif mode=="source_destroyed": source.queue_free(); await get_tree().process_frame
	var before: int=target.current_hp
	clock.advance_simulation(1.0); await _pump()
	check(target.current_hp==before-10,mode+" preserves the actually committed periodic HP")
	check(target.batches.size()==1 and target.ordinary_calls==0,mode+" uses the reserved periodic chain port exactly once")
	if target.batches.size()==1:
		var old: RefCounted=target.batches[0]
		var old_chain: Dictionary=old.chain_context()
		check(old.facts().size()==1 and old_chain.release_id!=root and old_chain.parent_release_id==root,
			mode+" freezes one distinct tick identity and the original parent")
		var snapshot: Dictionary=runtime.reservation_snapshot()
		var rejected:=Batch.create(world,old_chain.release_id,"hc.skill.wizard.ice_storm",bindings,{},clock.simulation_usec(),
			old.reservation(),null,old_chain,"periodic")
		check(not rejected.success and runtime.reservation_snapshot()==snapshot,mode+" delayed old ticket cannot reclaim capacity or create new work")
		var rng:=RandomNumberGenerator.new(); rng.seed=48015
		var rng_before: int=rng.state; var hp: int=target.current_hp
		var duplicate: Dictionary=combat.apply_feature_periodic_chain_damage(target,10,null,rng,{},old)
		check(not duplicate.success and target.current_hp==hp and rng.state==rng_before,
			mode+" delayed consumed batch rejects before RNG and HP")
	if mode=="stop_after_fatal":
		check(held_during_stop and child_commands.size()==1,"in-flight fatal producer retains its root after status retirement until its one child is consumed")
		check(target.collision_layer==0 and target.collision_mask==0,"fatal protocol callback cannot delay collision retirement")
	elif mode in ["baseline","source_destroyed"]:
		clock.advance_simulation(1.0); await _pump()
		check(target.batches.size()==2 and target.batches[0].chain_context().release_id!=target.batches[1].chain_context().release_id,
			mode+" consecutive actual ticks cannot reuse a retired receipt identity")
		check(target.credits.back().marker==mode,"original accepted historical credit survives later periodic delivery")
		clock.advance_simulation(2.0); await _pump()
		check(target.current_hp==150 and runtime.metrics().ticks==4,mode+" delivers all four authored ticks without extra damage")
	else:
		check(runtime.active_count()==0 and child_commands.is_empty(),mode+" retires old scheduling without inventing a child")
	check(_empty_promises() and not runtime.has_work() and runtime.errors.is_empty() and not runtime._pumping,
		mode+" closes every producer state receipt and consumer scope")
	runtime.clear()
	if is_instance_valid(target): target.queue_free()
	if is_instance_valid(source): source.queue_free()
	combat.queue_free(); await get_tree().process_frame

func _finish() -> void:
	var written:=proof.write_receipt("periodic_dispatch_lifecycle_test",proof.records.size(),errors.size())
	print("PERIODIC_DISPATCH_LIFECYCLE_",("PASS" if written and errors.is_empty() else "FAIL")," checks=",proof.records.size()," errors=",errors)
	get_tree().quit(0 if written and errors.is_empty() else 1)
