extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const RELEASES := 2200
const TARGETS := 30
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool,label: String) -> void:
	proof.record(value,label); checks += 1
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true; PlayerState.reset_progress(false)
	var world := World.new(); world.configure(self,PlayerState)
	var clock := Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	var runtime := Runtime.new(); runtime.configure(world,clock,combat); runtime.require_reservations = true
	check(ContentLayers.set_feature_module_enabled("hc.ignite",true),"actual compiled default-off module enabled for retirement proof")
	var bindings: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm",[])
	check(bindings.size() == 1 and bindings[0].definition.config.chance == 1.0,"actual guaranteed source requires one receipt per delivered receiver")
	var receivers: Array[EnemyActor] = []
	for index in TARGETS:
		var actor := preload("res://scripts/enemy.gd").new(); actor.setup(GameData.get_monster_by_id(19),null); add_child(actor)
		actor.set_physics_process(false); actor.max_hp = 100000; actor.current_hp = 100000
		receivers.append(actor)
	var oldest_batch: RefCounted
	var oldest_ticket: RefCounted
	var completed := 0
	var maximum_receipts := 0
	var maximum_records := 0
	var bounded := true
	var samples: Array[Dictionary] = []
	var started := Time.get_ticks_usec()
	for index in RELEASES:
		var release_id := "retirement:release:"+str(index)
		var ticket: RefCounted = runtime.reserve_action("hc.skill.wizard.ice_storm",bindings,TARGETS,release_id)
		if ticket == null: failures.append("preaccept capacity at release "+str(index)+": "+runtime.last_admission_reason); break
		var created: Dictionary = Batch.create(world,release_id,"hc.skill.wizard.ice_storm",bindings,{},0,ticket)
		if not bool(created.success): failures.append("producer creation at release "+str(index)); break
		var batch: RefCounted = created.batch; batch.begin_base_scope()
		for actor: EnemyActor in receivers:
			actor.take_damage(10,null,{"feature_damage_batch":batch,"source_class":"direct","damage_channel":"magic_defense"})
		batch.finish_base_scope()
		if not runtime.submit_batch(batch): failures.append("accepted transfer at release "+str(index)); break
		ticket.close()
		if index == 0: oldest_batch = batch; oldest_ticket = ticket
		# Structural lifetime proof, not a frame/performance benchmark: drive the
		# real consumer quantum explicitly; no fake HP, receipt or state counters.
		while runtime.pending_count() > 0:
			runtime._dispatch_one_fact()
			maximum_receipts = maxi(maximum_receipts,runtime._receipts.size())
			maximum_records = maxi(maximum_records,runtime._reservations.size())
		bounded = bounded and runtime._receipts.is_empty() and runtime._reservations.is_empty() \
			and runtime._batches.is_empty() and runtime.active_count() == TARGETS
		if not runtime.errors.is_empty(): failures.append("consumer failure at release "+str(index)+": "+str(runtime.errors)); break
		completed += 1
		if index%200 == 0:
			samples.append({"release":index+1,"memory_static":int(Performance.get_monitor(Performance.MEMORY_STATIC)),
				"objects":int(Performance.get_monitor(Performance.OBJECT_COUNT)),"states":runtime.active_count(),"receipts":runtime._receipts.size()})
			await get_tree().process_frame
	check(completed == RELEASES,"all 2200 accepted thirty-receiver releases finish after crossing the old 65536-receipt lifetime bound")
	check(int(runtime.metrics().admitted_facts) == RELEASES*TARGETS,"all 66000 real committed HP facts were consumed exactly once")
	# 2026-10-05 user ruling: same-species repeats atomically replace one head
	# (replaced terminals), the strongest_keep_phase refresh terminal is gone.
	check(int(runtime.metrics().started) == TARGETS and int(runtime.metrics().replaced) == RELEASES*TARGETS-TARGETS
		and int(runtime.metrics().refreshed) == 0,
		"thirty same-species heads start once and every later accepted source atomically replaces its incarnation")
	var exact_hp := true
	for actor: EnemyActor in receivers: exact_hp = exact_hp and actor.current_hp == 100000-10*RELEASES
	check(exact_hp,"every target retains the exact completed base damage total")
	check(bounded and maximum_receipts <= TARGETS and maximum_records <= 1,"receipt and producer storage remain bounded by active work, not historical release count")
	check(int(runtime.metrics().peak_receipts) == TARGETS and int(runtime.metrics().retired_receipts) == RELEASES*TARGETS,
		"write-boundary telemetry records the true thirty-receipt peak and all 66000 terminal retirements")
	check(runtime.presentation().events.size() <= 256,"presentation telemetry retains its existing bounded storage")
	await get_tree().create_timer(0.01).timeout
	check(oldest_batch != null and not runtime.submit_batch(oldest_batch),"delayed retained old batch cannot submit again after thousands of retirements")
	if oldest_ticket != null:
		check(not bool(Batch.create(world,"retirement:release:0","hc.skill.wizard.ice_storm",bindings,{},0,oldest_ticket).success),
			"delayed callback cannot reopen the retired producer identity")
	print("FEATURE_RECEIPT_RETIREMENT_TRACE "+JSON.stringify({"completed":completed,"facts":runtime.metrics().admitted_facts,
		"maximum_observed_receipts_after_dispatch":maximum_receipts,"maximum_records":maximum_records,"elapsed_usec":Time.get_ticks_usec()-started,
		"metrics":runtime.metrics(),"memory_observations_only":samples,"performance_acceptance":"NOT_RUN"}))
	runtime.clear()
	if not proof.write_receipt("feature_receipt_retirement_test",checks,failures.size()): failures.append("receipt")
	print("FEATURE_RECEIPT_RETIREMENT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
