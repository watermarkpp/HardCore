extends Node

# Full-duration semantics apply to FIRST installation too, even when a real
# committed batch is consumed later. Test-owned clock, real HP/batch/consumer.
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value: failures.append(label)

func _ready() -> void: _run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "explicit default-off module enables")
	var bindings: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm", [])
	check(bindings.size() == 1, "production compiler supplies the ordinary one-species binding")
	if bindings.size() != 1: _finish(); return
	var world := World.new(); world.configure(self, PlayerState)
	var clock := Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	var target := Enemy.new(); target.setup(GameData.get_monster_by_id(19), null); add_child(target)
	target.set_physics_process(false)
	target.max_hp = 1000; target.current_hp = 1000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	var runtime := Runtime.new()
	check(runtime.configure(world, clock, combat), "original effect owner is configured")
	runtime.require_reservations = true
	var ticket: RefCounted = runtime.reserve_action("hc.skill.wizard.ice_storm", bindings, 1, "apply-time:first")
	check(ticket != null, "capacity is reserved before the real base HP write")
	if ticket == null: runtime.clear(); target.queue_free(); combat.queue_free(); _finish(); return
	var made := Batch.create(world, "apply-time:first", "hc.skill.wizard.ice_storm", bindings,
		{"profile_id": PlayerState.active_profile_id}, clock.simulation_usec(), ticket)
	check(made.success, "real reservation is claimed exactly once")
	if not made.success: ticket.close(); runtime.clear(); target.queue_free(); combat.queue_free(); _finish(); return
	var batch: RefCounted = made.batch
	check(batch.begin_base_scope(), "real synchronous base scope opens")
	target.take_damage(100, null, {"feature_damage_batch": batch, "source_class": "direct", "damage_channel": "magic_defense"})
	check(target.current_hp == 900, "100 actual base HP loss precedes effect consumption")
	check(batch.finish_base_scope() and runtime.submit_batch(batch), "sealed fact transfers to the original consumer")
	batch.finish_production(); ticket.close()
	check(runtime.pending_count() == 1 and runtime.active_count() == 0, "one real fact is pending without a prematurely installed state")
	var queued: Dictionary = runtime._batches[runtime._batch_head].entries[0].fact
	check(queued.accepted_simulation_usec == 0, "immutable original fact retains its historical accepted timestamp")
	# Deliberate queue delay exceeds one original period. No HP/time authority is replaced.
	clock.advance_simulation(1.25)
	await _pump(runtime)
	check(runtime.active_count() == 1 and runtime.heap_count() == 1, "first late application creates one current state")
	check(runtime.metrics().ticks == 0 and target.current_hp == 900, "first installation does not retroactively tick an unapplied status")
	var state: Dictionary = runtime._states.values()[0] if runtime.active_count() == 1 else {}
	check(state.get("next_due", -1) == 2250000, "first next_due equals actual apply time plus new period")
	check(state.get("expires", -1) == 5250000, "first expiry grants the complete new duration")
	check(queued.accepted_simulation_usec == 0, "application scheduling never rewrites the historical fact")
	var after_install: int = target.current_hp
	clock.advance_simulation(0.999)
	await _pump(runtime)
	check(target.current_hp == after_install, "no periodic HP write before the new first due boundary")
	clock.advance_simulation(0.001)
	await _pump(runtime)
	check(target.current_hp == 895, "first due boundary commits exactly five actual HP loss")
	for index in range(3):
		clock.advance_simulation(1.0)
		await _pump(runtime)
		check(target.current_hp == 890 - 5 * index, "remaining full-duration boundary " + str(index))
	check(runtime.active_count() == 0 and runtime.heap_count() == 0 and not runtime.has_work(), "state and producer finish on their own complete horizon")
	check(runtime.metrics().ticks == 4 and runtime.metrics().actual_loss == 20, "four deliveries and twenty actual periodic HP loss remain separate")
	check(runtime.errors.is_empty(), "no capacity or scheduling error was hidden")
	runtime.clear(); target.queue_free(); combat.queue_free()
	await get_tree().process_frame
	_finish()

func _pump(runtime: RefCounted) -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0 and not runtime.has_due(): return
		await get_tree().process_frame
	check(false, "bounded original consumer drains available work")

func _finish() -> void:
	var written := proof.write_receipt("dot_application_time_test", proof.records.size(), failures.size())
	print("DOT_APPLICATION_TIME_", "PASS" if written and failures.is_empty() else "FAIL", " checks=", proof.records.size(), " failures=", failures)
	get_tree().quit(0 if written and failures.is_empty() else 1)
