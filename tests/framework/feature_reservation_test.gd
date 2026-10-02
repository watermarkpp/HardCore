extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var world: RefCounted
var runtime: RefCounted
var bindings: Array
var target: EnemyActor

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	world = World.new(); world.configure(self,PlayerState)
	var clock := Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	runtime = Runtime.new(); runtime.configure(world,clock,combat)
	target = preload("res://scripts/enemy.gd").new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.max_hp = 10000; target.current_hp = 10000
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"real default-off module enabled explicitly")
	bindings = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size() == 1,"actual compiled trigger is used")
	check(runtime.has_method("reserve_action"),"runtime can promise capacity before any damage fact exists")
	if not runtime.has_method("reserve_action"): _finish(); return
	var full: RefCounted = _reserve(bindings,Batch.MAX_FACTS)
	check(full != null,"one action can reserve the exact existing global state capacity")
	check(not runtime.configure(world,clock,combat),"an accepted producer already owns its clock and port before its first fact")
	check(_reserve(bindings,1) == null,"another action cannot consume already promised global capacity")
	check(target.current_hp == 10000 and runtime.pending_count() == 0,"reservation rejection precedes HP and fact creation")
	if full != null: full.close()
	check(int(runtime.reservation_snapshot().actions) == 0,"unreleased cancelled action returns its entire reservation")
	var abandoned: RefCounted = _reserve(bindings,2)
	check(abandoned != null and int(runtime.reservation_snapshot().actions) == 1,"producer capability has no hidden strong owner in the runtime")
	abandoned = null
	check(int(runtime.reservation_snapshot().actions) == 0,"last producer reference releases unused capacity without a timer or TTL")
	check(_reserve(bindings,-1) == null and _reserve(bindings,Batch.MAX_FACTS+1) == null,"negative/oversized bounds reject before accepting an action")
	var empty: RefCounted = _reserve(bindings,0)
	check(empty != null,"proved empty world retains a legal empty release without inventing a target")
	if empty != null: empty.close()
	var distinct: Array[RefCounted] = []
	for index in 16:
		var candidate := bindings.duplicate(true)
		candidate[0].source.instance_id = "reservation:source:"+str(index)
		candidate[0].handle = Compiler.source_handle(candidate[0].source)
		distinct.append(_reserve(candidate,2))
	check(not distinct.has(null),"sixteen distinct future sources fit each possible receiver")
	check(_reserve(bindings,2) == null,"seventeenth source rejects even when global space is plentiful")
	for ticket: RefCounted in distinct:
		if ticket != null: ticket.close()
	var same: Array[RefCounted] = []
	for index in 17: same.append(_reserve(bindings,2))
	check(not same.has(null),"seventeen concurrent refresh promises share one source slot rather than imposing an action-count limit")
	for ticket: RefCounted in same:
		if ticket != null: ticket.close()
	var ticket: RefCounted = _reserve(bindings,2,"reservation:release")
	check(ticket != null,"fresh real action receives a reservation")
	if ticket == null: _finish(); return
	var factory: Variant = Batch
	check(not bool(factory.create(world,"reservation:wrong-action","hc.skill.wizard.ice_storm",bindings,{},0,ticket).success),"a new reservation cannot attach itself to another action's release identity")
	check(not bool(preload("res://scripts/features/contracts/plain_graph.gd").capture({"reservation":ticket}).success),"live producer capability cannot enter persisted or imported plain data")
	var created: Dictionary = factory.create(world,"reservation:release","hc.skill.wizard.ice_storm",bindings,{},clock.simulation_usec(),ticket)
	check(bool(created.success),"accepted ticket transfers once to its real base producer")
	check(not bool(factory.create(world,"reservation:duplicate-producer","hc.skill.wizard.ice_storm",bindings,{},0,ticket).success),"same ticket cannot create another producer under a different release label")
	if not bool(created.success): _finish(); return
	var batch: RefCounted = created.batch; batch.begin_base_scope()
	target.take_damage(100,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	batch.finish_base_scope()
	check(runtime.submit_batch(batch),"complete damage fact transfers into its reserved queue space")
	ticket.close()
	check(int(runtime.reservation_snapshot().actions) == 1,"producer closure retains capacity while the consumer still owns work")
	for index in 30:
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.pending_count() == 0 and runtime.active_count() == 1 and runtime.errors.is_empty(),"accepted work creates its promised real state without a late capacity rejection")
	check(int(runtime.reservation_snapshot().actions) == 0 and int(runtime.reservation_snapshot().receipts) == 0,"sealed one-shot producer plus exhausted consumer retires only its own receipt")
	check(not runtime.submit_batch(batch),"retained sealed batch cannot reenter after receipt retirement")
	check(not bool(factory.create(world,"reservation:release","hc.skill.wizard.ice_storm",bindings,{},0,ticket).success),"retained retired ticket cannot recreate the old producer")
	var old: RefCounted = _reserve(bindings,2)
	_zone_generation += 1
	var fresh: RefCounted = _reserve(bindings,2)
	check(fresh != null and old != null,"new world can reserve independently")
	check(not bool(factory.create(world,"reservation:old-world","hc.skill.wizard.ice_storm",bindings,{},0,old).success),"old ticket cannot borrow a new world's open reservation")
	if fresh != null: fresh.close()
	if old != null: old.close()
	check(int(runtime.reservation_snapshot().actions) == 0,"old-world callbacks cannot leak or release another action's reservation")
	_finish()

func _reserve(values: Array, count: int, release_id := "") -> RefCounted:
	return runtime.call("reserve_action","hc.skill.wizard.ice_storm",values,count,release_id)

func _finish() -> void:
	if runtime != null: runtime.clear()
	if not proof.write_receipt("feature_reservation_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_RESERVATION_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
