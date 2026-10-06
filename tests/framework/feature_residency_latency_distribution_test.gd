extends Node
## S4 row 9: Windows sustained-performance distribution on the SAME machine
## (fixed baseline 272430b36+). The legacy V3/V4 failures belong to the second
## tree's different semantic source and are not comparable; this scene instead
## produces this tree's own same-machine record: a cold pass and a warm pass of
## the full sixteen-layer residency (480 heads, 4 simulated seconds each) with
## per-frame wall-interval percentiles, pending-fact queue-age tracks and
## per-frame service counts. Structural assertions only — no product SLA is
## claimed (startup/perf SLA stays OPEN in the ledger).
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Player := preload("res://scripts/player.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Compiler := preload("res://scripts/features/compilation/feature_compiler.gd")
const Presentation := preload("res://scripts/features/presentation/presentation_port.gd")
const SKILL := "hc.skill.wizard.ice_storm"
const RECEIVERS := 30
const LAYERS := 16
const RESIDENT_HEADS := RECEIVERS*LAYERS
const FRAMES_PER_SECOND := 60
const SIM_SECONDS := 4
var _zone_generation := 1
var current_map_id := 910001
var checks := 0
var errors: Array[String] = []
var proof := Proof.new()
var world: RefCounted
var clock: RefCounted
var runtime: RefCounted
var targets: Array[EnemyActor] = []
var source: PlayerCharacter
var combat: Node
var visual: RefCounted

class ObservedEnemy extends Enemy:
	func take_feature_periodic_damage(_amount: int, _attacker: Node2D, _credit: Dictionary, _receipt: Dictionary) -> void:
		pass
func _ready() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1; proof.record(value, label)
	if not value: errors.append(label)
func _ground_to_screen(value: Vector2) -> Vector2: return value*10.0
func _screen_to_ground(value: Vector2) -> Vector2: return value/10.0
func _percentile(values: Array, fraction: float) -> int:
	if values.is_empty(): return 0
	var sorted := values.duplicate(); sorted.sort()
	var index := int(round(float(sorted.size()-1)*fraction))
	return int(sorted[maxi(0, mini(index, sorted.size()-1))])

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	PlayerState.active_profile_id = "residency-latency-dist"
	world = World.new(); world.configure(self, PlayerState)
	clock = Clock.new(); clock.configure(self)
	combat = Combat.new(); add_child(combat)
	for index in RECEIVERS:
		var actor: ObservedEnemy = ObservedEnemy.new()
		actor.setup(GameData.get_monster_by_id(19), null); add_child(actor)
		actor.set_physics_process(false)
		actor.configure_runtime_map_projection(current_map_id, _ground_to_screen, _screen_to_ground)
		actor.set_combat_position(_ground_to_screen(Vector2(1.0+float(index%6)*0.72, 12.2+float(index/6)*0.64)), &"residency_latency_dist_unit_position")
		actor.max_hp = 100000; actor.current_hp = 100000
		actor.direct_spell_anti_magic_points = 0
		actor.direct_spell_magic_defense_min = 0; actor.direct_spell_magic_defense_max = 0
		actor.direct_spell_stats_valid = true
		targets.append(actor)
	source = Player.new(); add_child(source); source.set_physics_process(false)
	visual = Presentation.new(); visual.configure(world, true)
	runtime = Runtime.new(); runtime.configure(world, clock, combat, visual)
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "default-off verification module enabled through the real service")
	var base: Array = PlayerState.feature_bundle().event_index.get("damage_committed:"+SKILL, [])
	check(base.size() == 1, "one real compiled ignite binding feeds the residency")
	if base.is_empty(): _finish(); return
	var layered: Array = []
	for index in LAYERS:
		var binding: Dictionary = base[0].duplicate(true)
		binding.source.instance_id = "latency.dist.layer:"+str(index)
		binding.handle = Compiler.source_handle(binding.source)
		binding.definition.config["status_layer"] = "latency.dist.layer."+str(index)
		layered.append(binding)
	check(layered.size() == LAYERS, "sixteen legal layer bindings compile")
	# Two same-machine passes: cold (first allocation, cold caches) and warm
	# (immediately repeated under the same live runtime).
	var passes: Array = []
	for pass_index in 2:
		var pass_name := "cold" if pass_index == 0 else "warm"
		var baseline_ticks: int = int(runtime.metrics().ticks)
		var baseline_lateness: int = int(runtime.metrics().maximum_tick_delivery_lateness_usec)
		var ticket: RefCounted = runtime.reserve_action(SKILL, layered, RECEIVERS, "latency:dist:"+pass_name)
		check(ticket != null and runtime.last_admission_reason == "", pass_name+" pass reserves the full layered residency")
		if ticket == null: _finish(); return
		var created: Dictionary = Batch.create(world, "latency:dist:"+pass_name, SKILL, layered, {"profile_id":PlayerState.active_profile_id}, 0, ticket)
		check(bool(created.success), pass_name+" pass accepts its layered batch")
		if not bool(created.success): _finish(); return
		var batch: RefCounted = created.batch; batch.begin_base_scope()
		for actor: EnemyActor in targets:
			actor.take_damage(100, source, {"feature_damage_batch":batch, "source_class":"direct", "damage_channel":"magic_defense"})
		batch.finish_base_scope()
		check(runtime.submit_batch(batch), pass_name+" pass transfers its facts")
		var submit_frame := Engine.get_process_frames()
		var intervals: Array = []
		var served_per_frame: Array = []
		var pending_track: Array = []
		var previous_usec := Time.get_ticks_usec()
		var facts_cleared_frame := -1
		for frame_index in range(FRAMES_PER_SECOND*SIM_SECONDS):
			await get_tree().process_frame
			var now_usec := Time.get_ticks_usec()
			intervals.append(now_usec-previous_usec); previous_usec = now_usec
			var served: int = runtime.pump()
			served_per_frame.append(served)
			pending_track.append(runtime.pending_count())
			if facts_cleared_frame < 0 and runtime.pending_count() == 0: facts_cleared_frame = Engine.get_process_frames()-submit_frame
			clock.advance_simulation(1.0/float(FRAMES_PER_SECOND))
		check(facts_cleared_frame > 0 and facts_cleared_frame <= FRAMES_PER_SECOND,
			pass_name+" pass dispatches every accepted fact within one simulated second (age frame "+str(facts_cleared_frame)+")")
		# The sampling window ends after four simulated seconds; the Budget
		# fair-rotation service pace (the sustained-performance datum this
		# scene exists to record) may trail the due-wave arrival, so the
		# completion assertions run on a dedicated drain tail, not inside the
		# distribution window.
		var drain_frames := 0
		while int(runtime.metrics().ticks) - baseline_ticks < RESIDENT_HEADS*SIM_SECONDS and drain_frames < FRAMES_PER_SECOND*4:
			await get_tree().process_frame
			runtime.pump()
			clock.advance_simulation(1.0/float(FRAMES_PER_SECOND))
			drain_frames += 1
		check(int(runtime.metrics().ticks) - baseline_ticks == RESIDENT_HEADS*SIM_SECONDS,
			pass_name+" pass delivers exactly "+str(RESIDENT_HEADS*SIM_SECONDS)+" due ticks (window ticks="+str(int(runtime.metrics().ticks)-baseline_ticks)+" tail_frames="+str(drain_frames)+")")
		check(int(runtime.metrics().maximum_tick_delivery_lateness_usec) < 8*1000000,
			pass_name+" pass shows bounded (not unbounded) tick delay under shared-budget fair rotation; actual max lateness "+str(int(runtime.metrics().maximum_tick_delivery_lateness_usec))+"us is recorded as the sustained datum, no SLA claimed")
		var record := {"pass":pass_name,
			"frame_interval_usec":{"p50":_percentile(intervals,0.50),"p95":_percentile(intervals,0.95),"p99":_percentile(intervals,0.99),"max":int(intervals.max()),"samples":intervals.size()},
			"frames_over_60hz_budget":int(intervals.filter(func(v: int) -> bool: return v > 16667).size()),
			"served_per_frame":{"p50":_percentile(served_per_frame,0.50),"p95":_percentile(served_per_frame,0.95),"max":int(served_per_frame.max())},
			"pending_peak":int(pending_track.max()),"pending_track_frames_over_zero":int(pending_track.filter(func(v: int) -> bool: return v > 0).size()),
			"facts_cleared_frame":facts_cleared_frame,
			"max_tick_lateness_usec":int(runtime.metrics().maximum_tick_delivery_lateness_usec)}
		passes.append(record)
		print("RESIDENCY_LATENCY_DIST ", JSON.stringify(record))
		# Retire this pass completely before the next one so warm starts from
		# zero residual heads (no cross-pass tick coupling).
		for retire_frame in range(FRAMES_PER_SECOND*6):
			await get_tree().process_frame
			runtime.pump()
			clock.advance_simulation(0.05)
			if runtime.active_count() == 0 and runtime.heap_count() == 0: break
		check(runtime.active_count() == 0 and runtime.heap_count() == 0,
			pass_name+" pass retires every head before the next pass starts")
	check(runtime.errors.is_empty(), "both passes complete without hidden runtime errors")
	print("RESIDENCY_LATENCY_DIST_COMPARE cold_p50=%d warm_p50=%d cold_p99=%d warm_p99=%d served_cold_p95=%d served_warm_p95=%d" % [
		int(passes[0]["frame_interval_usec"]["p50"]), int(passes[1]["frame_interval_usec"]["p50"]),
		int(passes[0]["frame_interval_usec"]["p99"]), int(passes[1]["frame_interval_usec"]["p99"]),
		int(passes[0]["served_per_frame"]["p95"]), int(passes[1]["served_per_frame"]["p95"])])
	for tick_index in range(SIM_SECONDS+1):
		clock.advance_simulation(1.0)
		for frame in range(30): await get_tree().process_frame
		runtime.pump()
		if runtime.active_count() == 0 and runtime.heap_count() == 0: break
	check(runtime.active_count() == 0 and runtime.heap_count() == 0,
		"the residency retires every head at its own full duration after both passes")
	check(_tail_drained() and visual.node_count() == 0 and runtime._batches.is_empty(),
		"retire tail bookkeeping returns every slot after the distribution workload")
	runtime.clear()
	targets.map(func(actor: Node) -> void: actor.queue_free()); combat.queue_free(); source.queue_free()
	await get_tree().process_frame
	_finish()
func _tail_drained() -> bool:
	var snapshot: Dictionary = runtime.reservation_snapshot()
	for key: Variant in snapshot:
		if str(key) == "receipts": continue
		if int(snapshot[key]) != 0: return false
	return true
func _finish() -> void:
	check(proof.write_receipt("feature_residency_latency_distribution_test", checks, errors.size()), "receipt")
	print("RESIDENCY_LATENCY_DIST_RESULT_",("PASS" if errors.is_empty() else "FAIL")," checks=",checks," failures=",str(errors))
	get_tree().quit(0 if errors.is_empty() else 1)
