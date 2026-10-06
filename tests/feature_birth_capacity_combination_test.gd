extends "res://tests/m30_r4/test_m30_summon_reproduction.gd"
## S2 birth-closure x feature-capacity combination (fixed baseline 272430b36+).
## The real formal world runs BOTH systems at once on the same bodies:
##   - the SummonQueue birth closure keeps its ordinal, landing and
##     materialization budgets while features run, and every slot is freed by
##     real damage/death exactly once, and
##   - the feature runtime holds its full sixteen-layer residency (480 heads)
##     with every due tick served inside its own period, and real deaths
##     retire every head through the fatal path with a fully drained tail.
## Structural combination proof; no performance acceptance is claimed.
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const SKILL := "hc.skill.wizard.ice_storm"
const LAYERS := 16

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await Fixture.wait_for_formal_world(self, game, "birth_capacity")
	var plan: Array[Dictionary] = []
	for index in range(3):
		var id: int = [182,126,160][index]
		plan.append({"id":id,"ground":Fixture.FIXTURE_GROUND_POSITION+Vector2(index*4,0),
			"respawn":-1.0,"context":{"respawn_enabled":false,"spawn_slot_id":"cap:%d" % id}})
	var published: Array[EnemyActor] = await Fixture.publish_targets(self,game,plan,"birth_capacity")
	var caster: PlayerCharacter = game.player
	caster.max_hp = 999999
	caster.current_hp = caster.max_hp
	game._set_player_world_position(game._canonical_ground_gu_to_screen_px(
		Fixture.FIXTURE_GROUND_POSITION + Fixture.CASTER_GROUND_OFFSET))
	for value: Variant in game._active_enemy_cache.values():
		if value is EnemyActor:
			value.set_physics_process(false)
			if value not in published:
				value.set_combat_position(caster.global_position + Vector2(3000,3000), &"birth_capacity_clear")
	var sources: Array[EnemyActor] = []
	for index in range(3):
		var source: EnemyActor = published[index] if published.size()==3 else null
		check(source != null, "formal summon source present")
		if source == null: get_tree().quit(1); return
		source.set_physics_process(false); source.dormant = false; source.target = caster
		sources.append(source)
	for index in range(20):
		await get_tree().physics_frame
		for source in sources:
			if source.is_boss:
				source._boss_health_stage = 5; source.current_hp = 1; source._apply_health_stage_mechanics()
			else:
				source._summon_cooldown = 0
				source._update_behavior_summon(0); source._update_behavior_summon(0.5)
	var queue: HCM30SummonQueue = game._hc_m30_get_summon_queue()
	for _drain_frame in range(360):
		if queue._jobs.is_empty(): break
		await get_tree().physics_frame
	check(queue._jobs.is_empty(), "the summon queue drains every materialization job before the residency")
	for _tick in range(360):
		for ref_dict: Dictionary in queue._children.values():
			for ref: WeakRef in ref_dict.values():
				var child: EnemyActor = ref.get_ref()
				if is_instance_valid(child): child.set_physics_process(false)
		var invariant := true
		for slot in ["cap:182", "cap:126", "cap:160"]:
			invariant = invariant and queue._active(slot) + int(queue._reserved.get(slot, 0)) <= (15 if slot == "cap:160" else 5)
		check(invariant, "summon ordinal invariant holds during drain")
	check(int(queue.snapshot().max_materializations_in_tick) <= 1, "formal materialization budget retained with features armed")
	# --- Feature residency over the live born bodies (sources + all children).
	# The summon trigger stage drained the sources (boss staged at 1 HP) and
	# newborn bodies keep their table HP (the weakest would die to the base
	# write). Declare the same stress-health input the natural workload uses so
	# the residency base damage cannot fatally retire a receiver; beats,
	# periods and damage amounts stay unchanged.
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "default-off feature module enabled in the formal world")
	var base: Array = PlayerState.feature_bundle().event_index.get("damage_committed:"+SKILL, [])
	check(base.size() == 1, "one real compiled ignite binding feeds the layered residency")
	if base.is_empty(): get_tree().quit(1); return
	var receivers: Array[EnemyActor] = []
	for source in sources: receivers.append(source)
	for ref_dict: Dictionary in queue._children.values():
		for ref: WeakRef in ref_dict.values():
			var child: EnemyActor = ref.get_ref()
			if is_instance_valid(child): receivers.append(child)
	var expected_receivers := 3 + 5 + 5 + 15
	check(receivers.size() == expected_receivers, "the birth closure supplies exactly %d live receivers for the residency" % expected_receivers)
	for actor: EnemyActor in receivers:
		actor.max_hp = 100000; actor.current_hp = 100000
	var world: RefCounted = game._world_context
	var clock: RefCounted = game._time_domains
	var runtime: RefCounted = Runtime.new()
	check(runtime.configure(world, clock, game._combat_runtime), "the production world clock and HP port own the combined runtime")
	game._feature_effect_runtime = runtime
	var layered: Array = []
	for index in LAYERS:
		var binding: Dictionary = base[0].duplicate(true)
		binding.source.instance_id = "birth.capacity.layer:"+str(index)
		binding.handle = Compiler.source_handle(binding.source)
		binding.definition.config["status_layer"] = "birth.capacity.layer."+str(index)
		layered.append(binding)
	var ticket: RefCounted = runtime.reserve_action(SKILL, layered, receivers.size(), "birth:capacity")
	check(ticket != null and runtime.last_admission_reason == "", "the full layered residency reserves over live born bodies")
	if ticket == null: get_tree().quit(1); return
	var created: Dictionary = Batch.create(world, "birth:capacity", SKILL, layered, {"profile_id":PlayerState.active_profile_id}, 0, ticket)
	check(bool(created.success), "the accepted reservation accepts its layered batch")
	if not bool(created.success): get_tree().quit(1); return
	var batch: RefCounted = created.batch; batch.begin_base_scope()
	for actor: EnemyActor in receivers:
		actor.take_damage(100, caster, {"feature_damage_batch":batch, "source_class":"direct", "damage_channel":"magic_defense"})
	batch.finish_base_scope()
	check(runtime.submit_batch(batch), "the layered batch transfers")
	check(runtime.pending_count() == receivers.size(), "every live receiver owns one fact")
	ContentLayers.set_feature_module_enabled("hc.ignite", false)
	while runtime.pending_count() > 0: runtime._dispatch_one_fact()
	var residency := LAYERS*receivers.size()
	check(runtime.active_count() == residency and runtime.heap_count() == residency,
		"%d layered heads hold simultaneously over born bodies actual=%d heap=%d started=%d" % [residency, runtime.active_count(), runtime.heap_count(), int(runtime.metrics().started)])
	# Four natural simulation seconds at the real world frame cadence: the
	# formal per-frame pump serves every due tick with at most one frame of
	# delivery age, which is the cadence the production world actually promises.
	for tick_index in range(4):
		for _frame in range(60):
			await get_tree().physics_frame
		var invariant := true
		for slot in ["cap:182", "cap:126", "cap:160"]:
			invariant = invariant and queue._active(slot) + int(queue._reserved.get(slot, 0)) <= (15 if slot == "cap:160" else 5)
		check(invariant, "summon ordinal invariant holds during resident tick second "+str(tick_index+1))
	# The headless clock may lag the frame count; wait for the residency's own
	# final boundary instead of assuming a fixed frame-to-simulation ratio.
	for _wait_frame in range(1200):
		if int(runtime.metrics().ticks) >= residency*4 and not runtime.has_due(): break
		await get_tree().physics_frame
	check(int(runtime.metrics().ticks) == residency*4
		and int(runtime.metrics().maximum_tick_delivery_lateness_usec) < 1000000,
		"all %d due ticks are served inside their own period actual_ticks=%d lateness=%d" % [residency*4, int(runtime.metrics().ticks), int(runtime.metrics().maximum_tick_delivery_lateness_usec)])
	# --- Real deaths retire BOTH ledgers exactly once.
	for actor: EnemyActor in receivers:
		actor.take_damage(999999, caster, {"source": "birth_capacity_fatal"})
	check(runtime.active_count() == 0 and runtime.heap_count() == 0,
		"every real death retires every feature head through the fatal path")
	for _frame in range(200):
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due() and runtime.child_count() == 0: break
		await get_tree().process_frame
	var tail: Dictionary = runtime.reservation_snapshot()
	check(int(tail.actions) == 0 and int(tail.facts) == 0 and int(tail.states) == 0
		and int(tail.promised_receipts) == 0 and int(tail.children) == 0 and int(tail.promised_children) == 0,
		"the feature retire tail returns every slot after the combined workload")
	for slot in ["cap:182", "cap:126", "cap:160"]:
		check(queue._active(slot) == 0 and int(queue._reserved.get(slot, 0)) == 0,
			"real deaths free every summon slot of "+slot)
	check(runtime.errors.is_empty() and int(queue.snapshot().spawn_failed) == 0,
		"the combined workload completes without hidden feature or birth failures")
	print("BIRTH_CAPACITY_COMBINATION_%s checks=%d failures=%d snapshot=%s" % [
		"PASS" if failures == 0 else "FAIL", checks, failures, JSON.stringify(queue.snapshot())])
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)
