extends "res://tests/framework/feature_capacity_atomic_test.gd"

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	world = World.new(); world.configure(self,PlayerState)
	var clock := Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	target = Enemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.set_physics_process(false); target.max_hp = 100000; target.current_hp = 100000
	second = Enemy.new(); second.setup(GameData.get_monster_by_id(64),null); add_child(second)
	second.set_physics_process(false); second.max_hp = 100000; second.current_hp = 100000
	runtime = Runtime.new(); check(runtime.configure(world,clock,combat),"actual effect runtime configured")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"qualified test source enabled")
	bindings = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size() == 1,"real compiled binding used")
	# Keep one real fact pending at every producer boundary. The individual
	# consumer quantum is invoked explicitly to force this legal interleaving;
	# the final drain below still uses the actual shared-budget pump.
	_enqueue_pair("queue:prime")
	runtime._dispatch_one_fact()
	var previous: Array[WeakRef] = []
	var retained_complete_refs := 0
	var occupancy_valid := true
	for index in range(256):
		var current := _enqueue_pair("queue:continuous:"+str(index))
		runtime._dispatch_one_fact()
		for reference: WeakRef in previous:
			if reference.get_ref() != null: retained_complete_refs += 1
		runtime._dispatch_one_fact()
		occupancy_valid = occupancy_valid and runtime.pending_count() == 1
		previous = current
	check(occupancy_valid,"continuous producers preserve exactly one necessary pending fact")
	check(retained_complete_refs == 0,"fully consumed batches release their ActorRef objects even while queue remains nonempty: "+str(retained_complete_refs))
	check(runtime._batches.size() <= runtime.pending_count(),"retained batch containers are bounded by necessary pending facts")
	var receipts_before: int = runtime._receipts.size()
	var admitted_before: int = runtime.metrics().admitted_facts
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.pending_count() == 0 and runtime._batches.is_empty(),"production budget pump drains the remaining fact and every queue container")
	check(runtime.metrics().admitted_facts == 514,"every real fact is dispatched exactly once in the 257 two-receiver batches")
	check(runtime._receipts.size() == 514 and runtime._receipts.size() >= receipts_before,"queue retirement preserves all historical deduplication receipts")
	for reference: WeakRef in previous:
		check(reference.get_ref() == null,"final fully consumed batch releases its own target handle")
	check(runtime.metrics().admitted_facts == admitted_before+1,"final drain processes precisely the sole pending fact")
	var refreshes: int = runtime.metrics().refreshed
	_enqueue_pair("queue:continuous:0")
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.pending_count() == 0 and runtime.metrics().refreshed == refreshes,"old release replay remains deduplicated after its queue container is reclaimed")
	check(runtime._receipts.size() == 514,"replay neither loses nor adds an old receipt")
	check(runtime.errors.is_empty(),"all queue operations complete without hidden capacity or identity errors")
	runtime.clear()
	check(runtime.pending_count() == 0 and runtime._batches.is_empty(),"world teardown resets the queue")
	_enqueue_pair("queue:after-clear")
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.pending_count() == 0 and runtime._receipts.size() == 2,"explicitly cleared owner can accept and drain a new queue")
	runtime.clear(); target.queue_free(); second.queue_free(); combat.queue_free()
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"test source withdrawn")
	await get_tree().process_frame
	if not proof.write_receipt("feature_queue_retention_test",checks,errors.size()): errors.append("receipt")
	print("FEATURE_QUEUE_RETENTION_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL",checks,str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)

func _enqueue_pair(release_id: String) -> Array[WeakRef]:
	var batch: RefCounted = Batch.create(world,release_id,"hc.skill.wizard.ice_storm",bindings,{"profile_id":PlayerState.active_profile_id}).batch
	batch.begin_base_scope()
	target.take_damage(20,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	second.take_damage(20,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	batch.finish_base_scope()
	var references: Array[WeakRef] = [weakref(batch._entries[0].target),weakref(batch._entries[1].target)]
	if not runtime.submit_batch(batch): errors.append("legal pair submission failed: "+release_id)
	return references
