extends Node

## S1 RED→GREEN: same-species DOT replacement contract (user ruling 2026-10-05).
## A repeated accepted ApplyStatus of the same certified species must publish
## ONE atomic new incarnation: the new weaker damage still replaces, next_due
## restarts from the actual application simulation time, expiry restarts with
## the full new duration, and the replaced prior incarnation ends as a
## `replaced` terminal without rolling back its already committed HP facts.
## The historical strongest_keep_phase refresh path is intentionally expected
## to fail here until the production runtime implements the ruling.

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const World := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Clock := preload("res://scripts/layers/runtime/execution/time_domains.gd")
const Batch := preload("res://scripts/features/runtime/damage_batch.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Combat := preload("res://scripts/layers/runtime/combat_runtime_service.gd")

var _zone_generation := 1
var current_map_id := 910001
var checks := 0
var errors: Array[String] = []
var proof := Proof.new()

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: errors.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var world := World.new(); world.configure(self, PlayerState)
	var clock := Clock.new(); clock.configure(self)
	var combat := Combat.new(); add_child(combat)
	var target := Enemy.new(); target.setup(GameData.get_monster_by_id(19), null); add_child(target)
	target.set_physics_process(false)
	target.max_hp = 1000; target.current_hp = 1000
	target.direct_spell_magic_defense_min = 0; target.direct_spell_magic_defense_max = 0
	check(ContentLayers.set_feature_module_enabled("hc.ignite", true), "default-off ignite module enables for the replacement contract")
	var bindings: Array = PlayerState.feature_bundle().event_index.get("damage_committed:hc.skill.wizard.ice_storm", [])
	check(bindings.size() == 1, "production qualification compiles the declared ignite source")
	var runtime_type: Variant = load("res://scripts/features/runtime/effect_runtime.gd")
	var runtime: RefCounted = runtime_type.new()
	runtime.configure(world, clock, combat)

	# --- First application (A): accepted 100 actual loss -> 5/tick, period 1s, 4s. ---
	var batch_a: RefCounted = Batch.create(world, "periodic:replace:A", "hc.skill.wizard.ice_storm", bindings,
		{"profile_id": PlayerState.active_profile_id}).batch
	batch_a.begin_base_scope()
	target.take_damage(100, null, {"feature_damage_batch": batch_a, "source_class": "direct", "damage_channel": "magic_defense"})
	batch_a.finish_base_scope()
	check(runtime.submit_batch(batch_a), "first same-species command is accepted")
	await _drain_commands(runtime)
	check(runtime.active_count() == 1 and runtime.metrics().started == 1,
		"first application owns exactly one species state head")
	var t_before_a_ticks: int = target.current_hp
	clock.advance_simulation(1.0)
	await _pump_due(runtime)
	var a_committed: int = t_before_a_ticks - target.current_hp
	check(a_committed == 5, "old incarnation tick already committed before replacement stays owned (5 at second 1)")

	# --- Second application (B) at t=1.0s: weaker 40 loss -> 2/tick. ---
	var batch_b: RefCounted = Batch.create(world, "periodic:replace:B", "hc.skill.wizard.ice_storm", bindings,
		{"profile_id": PlayerState.active_profile_id}).batch
	batch_b.begin_base_scope()
	target.take_damage(40, null, {"feature_damage_batch": batch_b, "source_class": "direct", "damage_channel": "magic_defense"})
	batch_b.finish_base_scope()
	check(runtime.submit_batch(batch_b), "second same-species command is accepted")
	await _drain_commands(runtime)
	var metrics: Dictionary = runtime.metrics()
	check(runtime.active_count() == 1, "same species still owns exactly one state head after repeated applications")
	check(int(metrics.get("replaced", -1)) == 1,
		"the prior incarnation ends as a replaced terminal, not a refresh (metrics.replaced==1)")
	check(int(metrics.get("refreshed", -1)) == 0, "strongest_keep_phase refresh terminal is no longer produced")
	var state := _single_state_snapshot(runtime)
	# t=1.0s is the actual application time of B: next_due must be 1.0s + 1.0s period.
	check(int(state.get("next_due", -1)) == 2000000,
		"next_due restarts from the actual application simulation time plus the new period (2.0s)")
	check(int(state.get("expires", -1)) == 5000000,
		"expiry restarts with the full new duration from the application time (5.0s)")
	check(int(state.get("raw_per_tick", -1)) == 2,
		"the new weaker damage replaces the old value instead of keeping the strongest")

	# --- Remaining horizon: duration 4s / period 1s = 4 boundary ticks at 2s,3s,4s,5s each 2 damage. ---
	var hp_after_replace: int = target.current_hp
	for index in range(4):
		clock.advance_simulation(1.0)
		await _pump_due(runtime)
		check(target.current_hp == hp_after_replace - 2 * (index + 1),
			"replacement incarnation ticks use the new accepted damage at second %d" % (index + 2))
	check(runtime.active_count() == 0 and runtime.heap_count() == 0, "replacement incarnation drains by its own expiry")
	# Total loss = 100 (A base take_damage) + a_committed (old tick) + 40 (B base)
	# + 8 (four replacement ticks). Feature-batch base damage is real HP loss.
	check(target.current_hp == 1000 - 100 - a_committed - 40 - 8, "committed old facts are not rolled back and total loss is exact")
	var final_metrics: Dictionary = runtime.metrics()
	check(int(final_metrics.get("replaced", 0)) == 1 and int(final_metrics.get("started", 0)) == 1
		and int(final_metrics.get("refreshed", 0)) == 0, "terminal counters stay: 1 started, 1 replaced, 0 refreshed")
	check(runtime.errors.is_empty(), "no hidden runtime failure in the replacement path")
	target.queue_free(); combat.queue_free()
	await get_tree().process_frame
	_finish()

func _single_state_snapshot(runtime: RefCounted) -> Dictionary:
	# Smallest owned projection of the single live state head (no live-data dump).
	for handle: String in runtime._states.keys():
		var state: Dictionary = runtime._states[handle]
		return {"next_due": int(state.get("next_due", -1)), "expires": int(state.get("expires", -1)),
			"raw_per_tick": int(state.get("raw_per_tick", -1))}
	return {}

func _drain_commands(runtime: RefCounted) -> void:
	for iteration in range(120):
		runtime.pump()
		if runtime.pending_count() == 0: return
		await get_tree().process_frame
	check(false, "command queue terminates")

func _pump_due(runtime: RefCounted) -> void:
	for iteration in range(120):
		runtime.pump()
		if not runtime.has_due(): return
		await get_tree().process_frame
	check(false, "due queue terminates")

func _finish() -> void:
	var ok: bool = errors.is_empty()
	print("DOT_REPLACE_CONTRACT_PASS checks=%d %s" % [checks, "errors=%s" % str(errors) if not ok else "errors=[]"])
	proof.write_receipt("dot_replace_contract_test", checks, errors.size())
	get_tree().quit(0 if ok else 1)
