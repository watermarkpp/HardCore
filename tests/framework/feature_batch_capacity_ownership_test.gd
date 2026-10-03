extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Runtime := preload("res://scripts/features/runtime/effect_runtime.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var _zone_generation := 1
var current_map_id := 910001
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var world := World.new()
	world.configure(self, PlayerState)
	var clock := Clock.new()
	clock.configure(self)
	var combat := Combat.new()
	add_child(combat)
	var runtime := Runtime.new()
	check(runtime.configure(world, clock, combat), "existing runtime is sole reservation owner")
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "real source compiled")
	var bindings: Array = PlayerState.feature_bundle().event_index["damage_committed:hc.skill.wizard.ice_storm"]
	var ticket: RefCounted = runtime.reserve_action("hc.skill.wizard.ice_storm", bindings, 1, "owned:abandoned")
	check(ticket != null, "actual producer receives one bounded promise")
	var created: Dictionary = Batch.create(world, "owned:abandoned", "hc.skill.wizard.ice_storm", bindings, {}, 0, ticket)
	check(created.success, "real batch claims that exact promise")
	var batch: RefCounted = created.batch
	created.clear()
	ticket.close()
	check(runtime.reservation_snapshot().actions == 1 and runtime.reservation_snapshot().facts == 1, "producer retirement cannot steal claimed batch capacity")
	check(not bool(Batch.create(world, "owned:abandoned", "hc.skill.wizard.ice_storm", bindings, {}, 0, ticket).success), "closed old producer never starts a second batch")
	batch = null
	check(runtime.reservation_snapshot().actions == 0 and runtime.reservation_snapshot().facts == 0 and not runtime.has_work(), "last batch owner releases an abandoned claim even while old ticket is retained")
	ticket.close()
	check(runtime.reservation_snapshot().actions == 0, "repeated old close cannot leak or reopen capacity")
	var unused: RefCounted = runtime.reserve_action("hc.skill.wizard.ice_storm", bindings, 1, "owned:unused")
	check(unused != null, "released capacity is available for new valid identity")
	unused.close()
	check(not runtime.has_work(), "unclaimed producer cancellation remains immediate")
	check(runtime.errors.is_empty(), "ownership transitions report no hidden errors")
	runtime.clear()
	if not proof.write_receipt("feature_batch_capacity_ownership_test", checks, failures.size()): failures.append("receipt")
	print("FEATURE_BATCH_CAPACITY_OWNERSHIP_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, str(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)
