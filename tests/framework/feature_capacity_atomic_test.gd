extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var checks := 0
var errors: Array[String] = []
var world: RefCounted
var runtime: RefCounted
var target: EnemyActor
var second: EnemyActor
var bindings: Array = []

func check(value: bool, label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: errors.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	world = World.new(); world.configure(self,PlayerState)
	var clock := Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	target = Enemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.max_hp = 100000; target.current_hp = 100000
	second = Enemy.new(); second.setup(GameData.get_monster_by_id(64),null); add_child(second)
	second.set_physics_process(false); second.max_hp = 100000; second.current_hp = 100000
	runtime = Runtime.new(); check(runtime.configure(world,clock,combat),"real runtime configured")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"default-off module explicitly enabled for fixture")
	bindings = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size() == 1,"actual compiled binding used")
	for index in range(2):
		var count := Batch.MAX_FACTS if index == 0 else Batch.MAX_FACTS-1
		var full := _batch("capacity:full:"+str(index),count)
		check(full.errors.is_empty() and full.facts().size() == count,"complete real HP facts fill one legal batch "+str(index))
		check(runtime.submit_batch(full),"real queue accepts legal full batch "+str(index))
	check(runtime.pending_count() == Runtime.MAX_PENDING_FACTS-1,"real queue reaches capacity minus one")
	var complete_pair := _batch("capacity:pair",2)
	var pair_hp := [target.current_hp,second.current_hp]
	check(not runtime.submit_batch(complete_pair),"one free slot refuses the whole two-receiver batch")
	check(runtime.pending_count() == Runtime.MAX_PENDING_FACTS-1 and complete_pair.facts().size() == 2,"refused multi-receiver transfer installs no partial queue entry")
	var boundary := _batch("capacity:boundary",1)
	check(runtime.submit_batch(boundary),"one remaining slot accepts the whole boundary batch")
	check(runtime.pending_count() == Runtime.MAX_PENDING_FACTS,"real pending queue reaches its exact bound")
	var candidate := _batch("capacity:retry",1)
	var committed_hp := target.current_hp
	check(not runtime.submit_batch(candidate),"full queue rejects submission explicitly")
	check(candidate.errors.is_empty() and candidate.facts().size() == 1,"rejected fact remains valid and sealed")
	check(target.current_hp == committed_hp,"capacity rejection never reverses committed HP")
	for iteration in range(600):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.pending_count() == 0,"actual occupied queue drains through production budget")
	check(runtime.submit_batch(candidate),"capacity rejection leaves batch unconsumed for an exact later submission")
	check(runtime.pending_count() == 1,"retry enqueues its complete fact once")
	check(not runtime.submit_batch(candidate),"accepted retry cannot submit twice")
	check(target.current_hp == committed_hp,"retry transports the existing fact without applying base damage again")
	check(runtime.submit_batch(complete_pair) and runtime.pending_count() == 3,"exact retry transports both AOE receiver facts atomically")
	check(not runtime.submit_batch(complete_pair),"accepted two-receiver batch remains one-shot")
	check(second.current_hp == pair_hp[1],"second receiver HP is neither reversed nor applied again")
	var unsealed: RefCounted = Batch.create(world,"capacity:unsealed","hc.skill.wizard.ice_storm",bindings,{"profile_id":PlayerState.active_profile_id}).batch
	unsealed.begin_base_scope()
	target.take_damage(1,null,{"feature_damage_batch":unsealed,"source_class":"direct","damage_channel":"magic_defense"})
	check(not runtime.submit_batch(unsealed),"an unsealed producer cannot transfer incomplete work")
	unsealed.finish_base_scope()
	check(runtime.submit_batch(unsealed),"rejected unsealed producer can complete and submit its exact fact")
	runtime.clear(); target.queue_free(); second.queue_free(); combat.queue_free()
	await get_tree().process_frame
	if not proof.write_receipt("feature_capacity_atomic_test",checks,errors.size()): errors.append("receipt")
	print(("FRAMEWORK_CAPACITY_ATOMIC_PASS" if errors.is_empty() else "FRAMEWORK_CAPACITY_ATOMIC_FAIL")+" checks="+str(checks)+" errors="+str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)

func _batch(release_id: String, count: int) -> RefCounted:
	var batch: RefCounted = Batch.create(world,release_id,"hc.skill.wizard.ice_storm",bindings,{"profile_id":PlayerState.active_profile_id}).batch
	batch.begin_base_scope()
	for index in range(count):
		var receiver: EnemyActor = target if index%2 == 0 else second
		receiver.take_damage(1,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	batch.finish_base_scope()
	return batch
