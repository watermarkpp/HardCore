extends "res://tests/framework/feature_capacity_atomic_test.gd"

class FaultStatsEnemy extends Enemy:
	var reject_stats := false
	func direct_spell_runtime_stats_into(output: Dictionary) -> bool:
		if reject_stats: return false
		return super.direct_spell_runtime_stats_into(output)

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	world = World.new(); world.configure(self,PlayerState)
	var clock := Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	target = FaultStatsEnemy.new(); target.setup(GameData.get_monster_by_id(19),null); add_child(target)
	target.process_mode = Node.PROCESS_MODE_DISABLED
	target.max_hp = 10000; target.current_hp = 10000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	runtime = Runtime.new(); check(runtime.configure(world,clock,combat),"actual effect service configured")
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"real qualified binding enabled")
	bindings = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	var batch: RefCounted = Batch.create(world,"late-delivery:once","hc.skill.wizard.ice_storm",bindings,{}).batch
	batch.begin_base_scope()
	target.take_damage(100,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	batch.finish_base_scope()
	check(runtime.submit_batch(batch),"real post-HP fact queued")
	for iteration in 120:
		runtime.pump()
		if runtime.pending_count() == 0: break
		await get_tree().process_frame
	check(runtime.active_count() == 1 and runtime.metrics().ticks == 0,"one accepted periodic state waits for its original due time")
	check(clock.advance_simulation(1.75),"existing simulation clock advances to 750ms after the first due time")
	check(runtime.has_due(),"actual heap reports the overdue work before service")
	var hp := target.current_hp
	for iteration in 120:
		runtime.pump()
		if not runtime.has_due(): break
		await get_tree().process_frame
	check(runtime.metrics().ticks == 1 and target.current_hp == hp-5,"actual production tick commits exactly five HP")
	check(not runtime.has_due(),"post-pump observer sees no remaining due work")
	check(runtime.metrics().get("tick_delivery_count",-1) == 1
		and runtime.metrics().get("maximum_tick_delivery_lateness_usec",-1) == 750000,
		"consumption-boundary metrics retain the 750ms late tick after heap sampling can no longer see it")
	clock.advance_simulation(0.25)
	for iteration in 120:
		runtime.pump()
		if not runtime.has_due(): break
		await get_tree().process_frame
	check(runtime.metrics().ticks == 2 and runtime.metrics().get("tick_delivery_count",-1) == 2
		and runtime.metrics().get("maximum_tick_delivery_lateness_usec",-1) == 750000,
		"later on-time delivery preserves maximum lateness without duplicating or rescheduling ticks")
	check(runtime.errors.is_empty(),"no mutation or delivery error")
	runtime.clear()
	clock = await _seed(combat,"on-time")
	clock.advance_simulation(1.0); await _drain()
	check(runtime.metrics().ticks == 1 and runtime.metrics().tick_delivery_count == 1
		and runtime.metrics().maximum_tick_delivery_lateness_usec == 0,"on-time consumption records zero simulated lateness")
	var before: Dictionary = runtime.metrics(); hp = target.current_hp
	var epoch := Engine.get_process_frames()
	runtime.pump(); runtime.pump()
	check(Engine.get_process_frames() == epoch and runtime.metrics() == before and target.current_hp == hp,
		"two pumps in one process epoch neither recount nor resubmit an already consumed phase")
	get_tree().paused = true
	var paused_at: int = clock.simulation_usec()
	await get_tree().create_timer(0.025,true).timeout
	check(not clock.advance_simulation(2.0) and runtime.pump() == 0 and clock.simulation_usec() == paused_at
		and runtime.metrics() == before,"paused wall time creates no simulated tick debt, count or lateness")
	get_tree().paused = false
	runtime.clear()
	clock = await _seed(combat,"exact-period")
	clock.advance_simulation(2.0); hp = target.current_hp; await _drain()
	check(runtime.metrics().ticks == 2 and runtime.metrics().tick_delivery_count == 2 and target.current_hp == hp-10,
		"late first phase and on-time second phase each commit exactly once")
	check(not runtime.has_due() and runtime.metrics().maximum_tick_delivery_lateness_usec == 1000000
		and not (runtime.metrics().maximum_tick_delivery_lateness_usec < 1000000),
		"exactly one full period late fails the strict gate even when post-service heap is empty")
	runtime.clear()
	clock = await _seed(combat,"natural-expiry")
	for phase in 4:
		clock.advance_simulation(1.0); await _drain()
	check(runtime.metrics().ticks == 4 and runtime.metrics().tick_delivery_count == 4 and runtime.metrics().expired == 1
		and runtime.metrics().invalidated == 0 and runtime.active_count() == 0,"natural expiry records four successful attempts and a separate terminal outcome")
	before = runtime.metrics(); clock.advance_simulation(2.0); await _drain()
	check(runtime.metrics() == before,"expired states cannot be counted as further attempted deliveries")
	runtime.clear()
	clock = await _seed(combat,"port-rejection")
	(target as FaultStatsEnemy).reject_stats = true
	clock.advance_simulation(1.0); hp = target.current_hp; await _drain()
	check(runtime.metrics().tick_delivery_count == 1 and runtime.metrics().ticks == 0 and runtime.metrics().failed == 1
		and runtime.errors == ["periodic_target_stats"] and target.current_hp == hp,
		"explicit stats fault reaches the actual damage port: rejected attempt is separate from successful delivery and writes no HP")
	(target as FaultStatsEnemy).reject_stats = false
	runtime.clear()
	clock = await _seed(combat,"invalid-target")
	target.queue_free(); clock.advance_simulation(1.0); await _drain()
	check(runtime.metrics().tick_delivery_count == 0 and runtime.metrics().ticks == 0 and runtime.metrics().invalidated == 1
		and runtime.metrics().expired == 0 and runtime.active_count() == 0,"invalidated target is cancelled before delivery and never reported as a successful tick")
	runtime.clear(); combat.queue_free()
	check(ContentLayers.set_feature_module_enabled("hc.ignite",false),"default-off module restored")
	await get_tree().process_frame
	proof.write_receipt("periodic_delivery_lateness_test",checks,errors.size())
	print("PERIODIC_DELIVERY_LATENESS_%s checks=%d errors=%s" % ["PASS" if errors.is_empty() else "FAIL",checks,str(errors)])
	get_tree().quit(0 if errors.is_empty() else 1)

func _seed(combat: Node, identity: String) -> RefCounted:
	var clock := Clock.new(); clock.configure(self)
	runtime = Runtime.new(); check(runtime.configure(world,clock,combat),"fresh real runtime for "+identity)
	var batch: RefCounted = Batch.create(world,"audit-a:"+identity,"hc.skill.wizard.ice_storm",bindings,{}).batch
	batch.begin_base_scope()
	target.take_damage(100,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
	batch.finish_base_scope(); check(runtime.submit_batch(batch),"real fact accepted for "+identity)
	await _drain()
	check(runtime.active_count() == 1,"one real state installed for "+identity)
	return clock

func _drain() -> void:
	for iteration in 120:
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false,"bounded test workload drains")
